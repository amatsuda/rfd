# frozen_string_literal: true

module Rfd
  class PreviewWindow < SubWindow
    # Module for Rouge syntax highlighting support (extractable for testing)
    module RougeSupport
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
    end

    include RougeSupport
    def render
      reposition_if_needed
      @window.clear

      item = controller.current_item

      # Hide preview for current directory (.)
      if item.name == '.'
        @window.refresh
        return
      end

      draw_border(item.name)

      if item.video?
        render_video(item)
      elsif item.heic?
        render_heic(item)
      elsif item.directory?
        render_directory(item)
      elsif item.archive?
        render_archive(item)
      elsif item.image?
        render_image(item)
      elsif item.pdf?
        render_pdf(item)
      elsif item.markdown?
        render_markdown(item)
      else
        render_text(item)
      end

      @window.refresh
    end

    def handle_input(c)
      # Preview window doesn't handle input - pass through to main
      false
    end

    private

    def render_video(item)
      if controller.preview_client&.connected?
        controller.instance_variable_set(:@pending_preview_item, item)
        controller.instance_variable_set(:@pending_sub_window, @window)
        @window.setpos(@window.maxy / 2, 1)
        @window.addstr('[Loading...]'.center(max_width))
        controller.preview_client.request(
          item: item,
          width: max_width,
          height: max_height
        )
      else
        @window.setpos(@window.maxy / 2, 1)
        @window.addstr('[Video file]'.center(max_width))
      end
    end

    def render_heic(item)
      if controller.preview_client&.connected?
        controller.instance_variable_set(:@pending_preview_item, item)
        controller.instance_variable_set(:@pending_sub_window, @window)
        @window.setpos(@window.maxy / 2, 1)
        @window.addstr('[Loading...]'.center(max_width))
        controller.preview_client.request(
          item: item,
          width: max_width,
          height: max_height
        )
      else
        @window.setpos(@window.maxy / 2, 1)
        @window.addstr('[HEIC file]'.center(max_width))
      end
    end

    def render_directory(item)
      entries = Dir.children(item.path).sort.first(max_height) rescue []
      entries.each_with_index do |name, i|
        @window.setpos(i + 1, 1)
        @window.addstr(name[0, max_width].ljust(max_width))
      end
    end

    def render_archive(item)
      entries = if item.zip?
        list_zip_entries(item.path)
      elsif item.gz?
        list_tar_gz_entries(item.path)
      else
        []
      end

      tree_lines = build_archive_tree(entries)
      tree_lines.first(max_height).each_with_index do |line, i|
        @window.setpos(i + 1, 1)
        @window.addstr(line[0, max_width].ljust(max_width))
      end
    rescue => e
      @window.setpos(@window.maxy / 2, 1)
      @window.addstr('[Archive error]'.center(max_width))
    end

    def build_archive_tree(entries)
      # Build tree structure from flat paths
      tree = {}
      entries.each do |path|
        parts = path.split('/').reject(&:empty?)
        current = tree
        parts.each do |part|
          current[part] ||= {}
          current = current[part]
        end
      end

      # Render tree to lines
      lines = []
      render_tree_node(tree, '', lines, true)
      lines
    end

    def render_tree_node(node, prefix, lines, is_root)
      sorted_keys = node.keys.sort_by { |k| [node[k].empty? ? 1 : 0, k.downcase] }
      sorted_keys.each_with_index do |name, idx|
        is_last = (idx == sorted_keys.length - 1)
        children = node[name]

        if is_root
          connector = ''
          child_prefix = ''
        else
          connector = is_last ? '└── ' : '├── '
          child_prefix = is_last ? '    ' : '│   '
        end

        display_name = children.empty? ? name : "#{name}/"
        lines << "#{prefix}#{connector}#{display_name}"

        unless children.empty?
          render_tree_node(children, prefix + child_prefix, lines, false)
        end
      end
    end

    def list_zip_entries(path)
      entries = []
      Zip::File.open(path) do |zip|
        zip.each { |entry| entries << entry.name }
      end
      entries.sort
    end

    def list_tar_gz_entries(path)
      entries = []
      Zlib::GzipReader.open(path) do |gz|
        Gem::Package::TarReader.new(gz) do |tar|
          tar.each { |entry| entries << entry.full_name }
        end
      end
      entries.sort
    rescue Zlib::GzipFile::Error
      # Not a gzip file, try plain tar
      File.open(path, 'rb') do |f|
        Gem::Package::TarReader.new(f) do |tar|
          tar.each { |entry| entries << entry.full_name }
        end
      end
      entries.sort
    end

    def render_image(item)
      @window.refresh
      unless controller.send(:display_image, item.path, x: @window.begx + 1, y: @window.begy + 1, width: max_width, height: max_height)
        @window.setpos(@window.maxy / 2, 1)
        @window.addstr('[Image file]'.center(max_width))
      end
    end

    def render_pdf(item)
      @window.refresh
      unless controller.send(:display_pdf, item.path, x: @window.begx + 1, y: @window.begy + 1, width: max_width, height: max_height)
        lines = controller.send(:pdf_text, item.path, max_lines: max_height)
        if lines && lines.any?
          render_text_lines(lines)
        else
          @window.setpos(@window.maxy / 2, 1)
          @window.addstr('[PDF file]'.center(max_width))
        end
      end
    end

    def render_markdown(item)
      lines = File.readlines(item.path, encoding: 'UTF-8', invalid: :replace, undef: :replace).first(max_height) rescue []
      lines.each_with_index do |line, i|
        @window.setpos(i + 1, 1)
        text = line.chomp
        attr = if text.start_with?('#')
          Curses::A_BOLD
        elsif text =~ /^```/ || text.start_with?('    ')
          Curses.color_pair(Curses::COLOR_GREEN)
        elsif text =~ /^[-*+] /
          Curses.color_pair(Curses::COLOR_CYAN)
        else
          Curses::A_NORMAL
        end
        @window.attron(attr) do
          display_line = +''
          display_width = 0
          text.each_char do |c|
            char_width = c.bytesize == 1 ? 1 : 2
            break if display_width + char_width > max_width
            display_line << c
            display_width += char_width
          end
          @window.addstr(display_line << ' ' * (max_width - display_width))
        end
      end
    end

    def render_text(item)
      content = File.read(item.path, encoding: 'UTF-8', invalid: :replace, undef: :replace) rescue nil
      if content.nil? || content.include?("\x00")
        @window.setpos(@window.maxy / 2, 1)
        @window.addstr('[Binary file]'.center(max_width))
        return
      end

      lexer = Rouge::Lexer.guess(filename: item.name, source: content) rescue nil
      if lexer && !lexer.is_a?(Rouge::Lexers::PlainText)
        render_code(content, lexer)
      else
        render_text_lines(content.lines.first(max_height))
      end
    end

    def render_code(content, lexer)
      tokens = lexer.lex(content)
      row, col = 1, 0
      @window.setpos(row, 1)

      tokens.each do |token_type, token_text|
        color = rouge_token_color(token_type)
        token_text.each_char do |c|
          break if row > max_height
          if c == "\n"
            @window.addstr(' ' * (max_width - col)) if col < max_width
            row += 1
            col = 0
            @window.setpos(row, 1) if row <= max_height
          else
            next if col >= max_width
            char_width = c.bytesize == 1 ? 1 : 2
            next if col + char_width > max_width
            @window.attron(color) { @window.addstr(c) }
            col += char_width
          end
        end
      end
      while row <= max_height
        @window.addstr(' ' * (max_width - col))
        row += 1
        col = 0
        @window.setpos(row, 1) if row <= max_height
      end
    end

    def render_text_lines(lines)
      lines.each_with_index do |line, i|
        @window.setpos(i + 1, 1)
        display_line = +''
        display_width = 0
        line.chomp.each_char do |c|
          char_width = c.bytesize == 1 ? 1 : 2
          break if display_width + char_width > max_width
          display_line << c
          display_width += char_width
        end
        @window.addstr(display_line << ' ' * (max_width - display_width))
      end
    end
  end
end
