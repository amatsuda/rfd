# frozen_string_literal: true

module Rfd
  module Viewer
    # Open current file or directory with the editor.
    def edit
      execute_external_command do
        editor = ENV['EDITOR'] || 'vim'
        unless in_zip?
          system editor, current_item.path
        else
          begin
            tmpdir, tmpfile_name = nil
            Zip::File.open(current_zip) do |zip|
              tmpdir = Dir.mktmpdir
              FileUtils.mkdir_p File.join(tmpdir, File.dirname(current_item.name))
              tmpfile_name = File.join(tmpdir, current_item.name)
              File.open(tmpfile_name, 'w') {|f| f.puts zip.file.read(current_item.name)}
              system editor, tmpfile_name
              zip.add(current_item.name, tmpfile_name) { true }
            end
            ls
          ensure
            FileUtils.remove_entry_secure tmpdir if tmpdir
          end
        end
      end
    end

    # Open current file or directory with the viewer.
    def view
      pager = ENV['PAGER'] || 'less'
      execute_external_command do
        unless in_zip?
          system pager, current_item.path
        else
          begin
            tmpdir, tmpfile_name = nil
            Zip::File.open(current_zip) do |zip|
              tmpdir = Dir.mktmpdir
              FileUtils.mkdir_p File.join(tmpdir, File.dirname(current_item.name))
              tmpfile_name = File.join(tmpdir, current_item.name)
              File.open(tmpfile_name, 'w') {|f| f.puts zip.file.read(current_item.name)}
            end
            system pager, tmpfile_name
          ensure
            FileUtils.remove_entry_secure tmpdir if tmpdir
          end
        end
      end
    end

    def view_image
      return view unless current_item.image?
      if display_image(current_item.path, x: 1, y: 5, width: Curses.cols - 2, height: Curses.lines - 6)
        Curses.getch
        print "\e_Ga=d,d=C\e\\" if kitty?  # Clear Kitty graphics
        move_cursor current_row
      elsif osx?
        system 'open', current_item.path
      end
    end

    def play_audio
      return view unless current_item.audio?
      command_line.writeln 0, "Playing: #{current_item.name} (press any key to stop)"
      command_line.refresh
      player_pid = spawn_audio_player(current_item.path)
      Curses.getch
      Process.kill('TERM', player_pid) rescue nil
      Process.wait(player_pid) rescue nil
      clear_command_line
      true
    end

    def preview
      if @preview_window
        @preview_window.close
        @preview_window = nil
        move_cursor current_row
      else
        popup_h = main.maxy
        popup_w = main.width
        popup_y = main.begy
        popup_x = preview_pane_x
        @preview_window = Curses::Window.new(popup_h, popup_w, popup_y, popup_x)
        update_preview
      end
    end

    def preview_pane_x
      # Preview goes in the next pane (to the right of cursor, wrapping around)
      visible_pane = main.current_index % main.number_of_panes
      next_pane = (visible_pane + 1) % main.number_of_panes
      next_pane * main.width + 1
    end

    def update_preview
      return unless @preview_window
      # Reposition preview window if cursor pane changed
      expected_x = preview_pane_x
      if @preview_window.begx != expected_x
        @preview_window.close
        @preview_window = Curses::Window.new(main.maxy, main.width, main.begy, expected_x)
        main.display current_page  # Redraw main window where old preview was
      end
      w = @preview_window
      max_width = w.maxx - 2
      w.clear

      # Hide preview for current directory (.)
      if current_item.name == '.'
        w.refresh
        return
      end

      w.bkgdset Curses.color_pair(Curses::COLOR_CYAN)
      Rfd::Window.draw_ncursesw_border(w, w.maxy, w.maxx)
      w.setpos(0, 2)
      w.addstr(" #{current_item.name} "[0, w.maxx - 4])

      w.bkgdset Curses.color_pair(Curses::COLOR_WHITE)
      if current_item.directory?
        preview_directory(w, max_width)
      elsif current_item.image?
        preview_image(w, max_width)
      elsif current_item.pdf?
        preview_pdf(w, max_width)
      elsif current_item.markdown?
        preview_markdown(w, max_width)
      else
        preview_text(w, max_width)
      end
      w.refresh
    end

    private

    def preview_directory(w, max_width)
      entries = Dir.children(current_item.path).sort.first(w.maxy - 2) rescue []
      entries.each_with_index do |name, i|
        w.setpos(i + 1, 1)
        w.addstr(name[0, max_width].ljust(max_width))
      end
    end

    def preview_image(w, max_width)
      w.refresh
      unless display_image(current_item.path, x: w.begx + 1, y: w.begy + 1, width: max_width, height: w.maxy - 2)
        w.setpos(w.maxy / 2, 1)
        w.addstr('[Image file]'.center(max_width))
      end
    end

    def preview_pdf(w, max_width)
      w.refresh
      unless display_pdf(current_item.path, x: w.begx + 1, y: w.begy + 1, width: max_width, height: w.maxy - 2)
        # Fallback to text extraction
        lines = pdf_text(current_item.path, max_lines: w.maxy - 2)
        if lines && lines.any?
          render_text_lines(w, lines, max_width)
        else
          w.setpos(w.maxy / 2, 1)
          w.addstr('[PDF file]'.center(max_width))
        end
      end
    end

    def preview_text(w, max_width)
      content = File.read(current_item.path, encoding: 'UTF-8', invalid: :replace, undef: :replace) rescue nil
      unless content
        w.setpos(w.maxy / 2, 1)
        w.addstr('[Binary file]'.center(max_width))
        return
      end

      # Try syntax highlighting with Rouge
      lexer = Rouge::Lexer.guess(filename: current_item.name, source: content) rescue nil
      if lexer && !lexer.is_a?(Rouge::Lexers::PlainText)
        preview_code(w, max_width, content, lexer)
      else
        render_text_lines(w, content.lines.first(w.maxy - 2), max_width)
      end
    end

    def preview_code(w, max_width, content, lexer)
      tokens = lexer.lex(content)
      row, col = 1, 0
      w.setpos(row, 1)

      tokens.each do |token_type, token_text|
        color = rouge_token_color(token_type)
        token_text.each_char do |c|
          break if row > w.maxy - 2
          if c == "\n"
            # Fill rest of line with spaces
            w.addstr(' ' * (max_width - col)) if col < max_width
            row += 1
            col = 0
            w.setpos(row, 1) if row <= w.maxy - 2
          else
            next if col >= max_width
            char_width = c.bytesize == 1 ? 1 : 2
            next if col + char_width > max_width
            w.attron(color) { w.addstr(c) }
            col += char_width
          end
        end
      end
      # Fill remaining lines
      while row <= w.maxy - 2
        w.addstr(' ' * (max_width - col))
        row += 1
        col = 0
        w.setpos(row, 1) if row <= w.maxy - 2
      end
    end

    ROUGE_COLORS = {
      'Comment' => Curses::COLOR_GREEN,
      'Keyword' => Curses::COLOR_CYAN,
      'Name.Function' => Curses::COLOR_MAGENTA,
      'Name.Class' => Curses::COLOR_MAGENTA,
      'Literal.String' => Curses::COLOR_RED,
      'Literal.Number' => Curses::COLOR_RED,
      'Operator' => Curses::COLOR_CYAN,
    }.freeze

    def rouge_token_color(token_type)
      token_str = token_type.qualname
      ROUGE_COLORS.each do |prefix, color|
        return Curses.color_pair(color) if token_str.start_with?(prefix)
      end
      Curses::A_NORMAL
    end

    def preview_markdown(w, max_width)
      lines = File.readlines(current_item.path, encoding: 'UTF-8', invalid: :replace, undef: :replace).first(w.maxy - 2) rescue []
      lines.each_with_index do |line, i|
        w.setpos(i + 1, 1)
        text = line.chomp
        # Determine style based on markdown syntax
        attr = if text.start_with?('#')
          Curses::A_BOLD
        elsif text =~ /^```/ || text.start_with?('    ')
          Curses.color_pair(Curses::COLOR_GREEN)
        elsif text =~ /^[-*+] /
          Curses.color_pair(Curses::COLOR_CYAN)
        else
          Curses::A_NORMAL
        end
        w.attron(attr) do
          display_line = +''
          display_width = 0
          text.each_char do |c|
            char_width = c.bytesize == 1 ? 1 : 2
            break if display_width + char_width > max_width
            display_line << c
            display_width += char_width
          end
          w.addstr(display_line << ' ' * (max_width - display_width))
        end
      end
    end

    def render_text_lines(w, lines, max_width)
      lines.each_with_index do |line, i|
        w.setpos(i + 1, 1)
        display_line = +''
        display_width = 0
        line.chomp.each_char do |c|
          char_width = c.bytesize == 1 ? 1 : 2
          break if display_width + char_width > max_width
          display_line << c
          display_width += char_width
        end
        w.addstr(display_line << ' ' * (max_width - display_width))
      end
    end

    def kitty?
      return @_kitty if defined?(@_kitty)
      @_kitty = (ENV['TERM'] == 'xterm-kitty') || (ENV['KITTY_WINDOW_ID']) || (ENV['TERM_PROGRAM'] == 'ghostty')
    end

    def spawn_audio_player(path)
      if osx?
        Process.spawn('afplay', path, out: '/dev/null', err: '/dev/null')
      else
        # Try mpv, ffplay, or aplay in order
        %w[mpv ffplay aplay].each do |player|
          if system("which #{player} > /dev/null 2>&1")
            args = case player
                   when 'mpv' then ['--no-video', '--really-quiet', path]
                   when 'ffplay' then ['-nodisp', '-autoexit', '-loglevel', 'quiet', path]
                   else [path]
                   end
            return Process.spawn(player, *args, out: '/dev/null', err: '/dev/null')
          end
        end
        Process.spawn('cat', '/dev/null')  # Dummy process if no player found
      end
    end

    def sixel?
      return @_sixel if defined?(@_sixel)
      @_sixel = (ENV['TERM_PROGRAM'] == 'iTerm.app') || ENV['TERM']&.include?('mlterm') || (ENV['TERM'] == 'foot')
    end

    # Display an image at the specified position using Kitty or Sixel graphics.
    # Returns true if image was displayed, false if no graphics support.
    def display_image(path, x:, y:, width:, height:)
      if kitty?
        print "\e_Ga=d,d=C\e\\"  # Clear previous image
        system 'kitty', '+kitten', 'icat', '--clear', '--place', "#{width}x#{height}@#{x}x#{y}", path, out: '/dev/tty', err: '/dev/null'
        print "\e[?25l"  # Hide cursor
        true
      elsif sixel?
        print "\e[#{y};#{x}H"
        system('img2sixel', '-w', (width * 10).to_s, path, out: '/dev/tty', err: '/dev/null') ||
          system('chafa', '-f', 'sixel', '-s', "#{width}x#{height}", path, out: '/dev/tty', err: '/dev/null')
        print "\e[?25l"  # Hide cursor
        true
      else
        false
      end
    end

    # Display a PDF at the specified position by converting first page to image.
    # Returns :image if displayed as image, false otherwise.
    def display_pdf(path, x:, y:, width:, height:)
      return false unless kitty? || sixel?
      tmpfile = File.join(Dir.tmpdir, "rfd_pdf_preview_#{$$}.png")
      begin
        # Try pdftoppm first (from poppler-utils), then convert (ImageMagick)
        if system('pdftoppm', '-png', '-f', '1', '-l', '1', '-singlefile', '-scale-to', (height * 15).to_s, path, tmpfile.sub(/\.png$/, ''), out: '/dev/null', err: '/dev/null')
          display_image(tmpfile, x: x, y: y, width: width, height: height)
          :image
        elsif system('convert', '-density', '100', "#{path}[0]", '-resize', "#{width * 10}x#{height * 15}", tmpfile, out: '/dev/null', err: '/dev/null')
          display_image(tmpfile, x: x, y: y, width: width, height: height)
          :image
        else
          false
        end
      ensure
        File.unlink(tmpfile) if File.exist?(tmpfile)
      end
    end

    # Extract text from PDF for preview fallback.
    def pdf_text(path, max_lines:)
      IO.popen(['pdftotext', '-l', '1', '-layout', path, '-'], err: '/dev/null') do |io|
        io.read.lines.first(max_lines)
      end
    rescue
      nil
    end
  end
end
