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
        Curses.stdscr.timeout = -1
        Curses.getch
        Curses.stdscr.timeout = 100
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
      Curses.stdscr.timeout = -1
      Curses.getch
      Curses.stdscr.timeout = 100
      Process.kill('TERM', player_pid) rescue nil
      Process.wait(player_pid) rescue nil
      clear_command_line
      true
    end

    def preview
      if @sub_window.is_a?(PreviewWindow)
        @preview_enabled = false
        close_sub_window
      else
        @preview_enabled = true
        close_sub_window if @sub_window
        @sub_window = PreviewWindow.new(self)
        @sub_window.render
      end
    end

    def update_preview
      return unless @sub_window
      @pending_preview_item = nil
      @sub_window.render
    end

    # Render result from async preview server
    def render_preview_result(result)
      return unless @sub_window && @pending_sub_window
      w = @pending_sub_window
      max_width = w.maxx - 2

      # Don't render if we've moved to a different file
      return unless @pending_preview_item
      return unless @pending_preview_item.path == current_item.path

      # Clear the content area (preserve border)
      (1...(w.maxy - 1)).each do |row|
        w.setpos(row, 1)
        w.addstr(' ' * max_width)
      end

      case result.status
      when :success
        render_successful_preview(w, result, max_width)
      when :error
        w.setpos(w.maxy / 2, 1)
        w.addstr("[Error: #{result.error}]"[0, max_width].center(max_width))
      end

      w.refresh
    end

    def render_successful_preview(w, result, max_width)
      case result.file_type
      when :directory, :text, :markdown, :pdf_text
        render_text_result(w, result.lines, max_width)
      when :code
        render_code_result(w, result.lines, max_width)
      when :video
        render_video_result(w, result, max_width)
      when :pdf, :heic
        render_pdf_result(w, result, max_width)
      when :binary
        render_text_result(w, result.lines, max_width)
      end
    end

    def render_text_result(w, lines, max_width)
      return unless lines
      lines.each_with_index do |line_data, i|
        w.setpos(i + 1, 1)
        text = line_data['text'] || line_data[:text] || ''
        attrs = line_data['attrs'] || line_data[:attrs] || []
        center = line_data['center'] || line_data[:center]

        attr = text_attr_from_names(attrs)
        display_text = center ? text.center(max_width) : text.ljust(max_width)
        w.attron(attr) { w.addstr(display_text[0, max_width]) }
      end
    end

    def render_code_result(w, lines, max_width)
      return unless lines
      lines.each_with_index do |line_data, i|
        w.setpos(i + 1, 1)
        segments = line_data['segments'] || line_data[:segments] || []
        col = 0
        segments.each do |seg|
          char = seg['char'] || seg[:char]
          color_name = seg['color'] || seg[:color]
          color = color_name ? color_pair_from_name(color_name) : Curses::A_NORMAL
          w.attron(color) { w.addstr(char) }
          col += 1
        end
        # Fill rest of line
        w.addstr(' ' * (max_width - col)) if col < max_width
      end
    end

    def render_video_result(w, result, max_width)
      metadata = result.metadata || {}
      thumbnail = result.thumbnail_path

      if thumbnail && File.exist?(thumbnail)
        # Calculate space for metadata at bottom
        metadata_lines = format_video_metadata_from_hash(metadata, max_width)
        image_height = w.maxy - 2 - metadata_lines.size

        if image_height > 2 && display_image(thumbnail, x: w.begx + 1, y: w.begy + 1, width: max_width, height: image_height)
          # Image displayed, show metadata below
          metadata_lines.each_with_index do |line, i|
            w.setpos(w.maxy - metadata_lines.size - 1 + i, 1)
            w.addstr(line[0, max_width].ljust(max_width))
          end
        else
          # No image support, show metadata
          render_video_metadata_only(w, metadata_lines, max_width)
        end
        File.unlink(thumbnail) rescue nil
      else
        # No thumbnail, just show metadata
        metadata_lines = format_video_metadata_from_hash(metadata, max_width)
        render_video_metadata_only(w, metadata_lines, max_width)
      end
    end

    def render_video_metadata_only(w, metadata_lines, max_width)
      w.setpos(1, 1)
      w.addstr('[Video file]'.center(max_width))
      metadata_lines.each_with_index do |line, i|
        w.setpos(3 + i, 1)
        w.addstr(line[0, max_width].ljust(max_width))
      end
    end

    def format_video_metadata_from_hash(metadata, max_width)
      lines = []
      lines << "Duration: #{metadata['duration'] || metadata[:duration]}" if metadata['duration'] || metadata[:duration]
      lines << "Size: #{metadata['size'] || metadata[:size]}" if metadata['size'] || metadata[:size]
      resolution = metadata['resolution'] || metadata[:resolution]
      codec = metadata['codec'] || metadata[:codec]
      lines << "#{resolution} #{codec}" if resolution
      fps = metadata['fps'] || metadata[:fps]
      lines << "#{fps} fps" if fps
      audio = metadata['audio'] || metadata[:audio]
      lines << "Audio: #{audio}" if audio
      lines
    end

    def render_pdf_result(w, result, max_width)
      thumbnail = result.thumbnail_path
      if thumbnail && File.exist?(thumbnail)
        display_image(thumbnail, x: w.begx + 1, y: w.begy + 1, width: max_width, height: w.maxy - 2)
        File.unlink(thumbnail) rescue nil
      elsif result.lines&.any?
        render_text_result(w, result.lines, max_width)
      else
        w.setpos(w.maxy / 2, 1)
        label = result.file_type == :heic ? '[HEIC file]' : '[PDF file]'
        w.addstr(label.center(max_width))
      end
    end

    def text_attr_from_names(attrs)
      return Curses::A_NORMAL unless attrs&.any?
      attr = Curses::A_NORMAL
      attrs.each do |a|
        case a.to_s
        when 'bold' then attr |= Curses::A_BOLD
        when 'green' then attr |= Curses.color_pair(Curses::COLOR_GREEN)
        when 'cyan' then attr |= Curses.color_pair(Curses::COLOR_CYAN)
        when 'red' then attr |= Curses.color_pair(Curses::COLOR_RED)
        when 'magenta' then attr |= Curses.color_pair(Curses::COLOR_MAGENTA)
        end
      end
      attr
    end

    def color_pair_from_name(name)
      case name.to_s
      when 'green' then Curses.color_pair(Curses::COLOR_GREEN)
      when 'cyan' then Curses.color_pair(Curses::COLOR_CYAN)
      when 'red' then Curses.color_pair(Curses::COLOR_RED)
      when 'magenta' then Curses.color_pair(Curses::COLOR_MAGENTA)
      else Curses::A_NORMAL
      end
    end

    private

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
      converted = convert_heic_if_needed(path)
      display_path = converted || path
      if kitty?
        print "\e_Ga=d,d=C\e\\"  # Clear previous image
        system 'kitty', '+kitten', 'icat', '--clear', '--place', "#{width}x#{height}@#{x}x#{y}", display_path, out: '/dev/tty', err: '/dev/null'
        print "\e[?25l"  # Hide cursor
        true
      elsif sixel?
        print "\e[#{y};#{x}H"
        system('img2sixel', '-w', (width * 10).to_s, display_path, out: '/dev/tty', err: '/dev/null') ||
          system('chafa', '-f', 'sixel', '-s', "#{width}x#{height}", display_path, out: '/dev/tty', err: '/dev/null')
        print "\e[?25l"  # Hide cursor
        true
      else
        false
      end
    ensure
      File.unlink(converted) if converted && File.exist?(converted)
    end

    def convert_heic_if_needed(path)
      return nil unless path.to_s.downcase.end_with?('.heic', '.heif')
      tmpfile = File.join(Dir.tmpdir, "rfd_heic_#{$$}.png")
      # Try sips (macOS), heif-convert (libheif), or ImageMagick
      if system('sips', '-s', 'format', 'png', path, '--out', tmpfile, out: '/dev/null', err: '/dev/null') ||
         system('heif-convert', path, tmpfile, out: '/dev/null', err: '/dev/null') ||
         system('convert', path, tmpfile, out: '/dev/null', err: '/dev/null')
        tmpfile
      else
        nil
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

    def extract_video_thumbnail(path)
      return nil unless kitty? || sixel?
      tmpfile = File.join(Dir.tmpdir, "rfd_video_thumb_#{$$}.png")
      if system('ffmpeg', '-y', '-i', path, '-ss', '00:00:01', '-vframes', '1', '-q:v', '2', tmpfile,
                out: '/dev/null', err: '/dev/null')
        tmpfile
      else
        nil
      end
    end

    def video_metadata(path)
      output = IO.popen(['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', path], err: '/dev/null') { |io| io.read }
      require 'json'
      JSON.parse(output)
    rescue
      nil
    end

    def format_video_metadata(metadata, max_width)
      lines = []
      if (format = metadata['format'])
        if (duration = format['duration'])
          secs = duration.to_f
          lines << "Duration: #{sprintf('%d:%02d:%02d', secs / 3600, (secs % 3600) / 60, secs % 60)}"
        end
        lines << "Size: #{(format['size'].to_i / 1024.0 / 1024).round(1)} MB" if format['size']
      end
      if (streams = metadata['streams'])
        if (video = streams.find { |s| s['codec_type'] == 'video' })
          lines << "#{video['width']}x#{video['height']} #{video['codec_name']&.upcase}"
          lines << "#{video['r_frame_rate']&.split('/')&.then { |n, d| (n.to_f / d.to_f).round(1) }} fps" if video['r_frame_rate']
        end
        if (audio = streams.find { |s| s['codec_type'] == 'audio' })
          lines << "Audio: #{audio['codec_name']&.upcase} #{audio['channels']}ch"
        end
      end
      lines
    end
  end
end
