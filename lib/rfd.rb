require 'fileutils'

module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  module MODE
    COMMAND = :command
    MIEL = :miel
  end

  module Commands
    def a
      @base.process_command_line prompt: ':chmod '
    end

    def d
      FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
      @row -= selected_items.count {|i| i.index <= @row}
      ls
    end

    def f
      @base.process_command_line prompt: ':find '
    end

    def F
      @base.process_command_line prompt: ':find_reverse '
    end

    def j
      if @row + 1 >= @items.size
        move_cursor 0
      else
        move_cursor @row + 1
      end
    end

    def k
      if @row == 0
        move_cursor @items.size - 1
      else
        move_cursor @row - 1
      end
    end

    def q
      raise StopIteration
    end

    def s
      @base.process_command_line prompt: ':sort '
    end

    def v
      switch_mode MODE::MIEL
      wclear
      @viewer = ViewerWindow.new base: @base
      @viewer.draw current_item.read
      wrefresh
    end

    def D
      FileUtils.rm_rf selected_items.map(&:path)
      @row -= selected_items.count {|i| i.index <= @row}
      ls
    end

    def H
      move_cursor @current_page * maxy
    end

    def L
      move_cursor @current_page * maxy + @displayed_items.size - 1
    end

    def M
      move_cursor @current_page * maxy + @displayed_items.size / 2
    end

    def ctrl_n
      if total_pages > 1
        if @current_page + 1 < total_pages
          move_cursor (@current_page + 1) * maxy
        else
          move_cursor 0
        end
      end
    end

    def ctrl_p
      if total_pages > 1
        if @current_page > 0
          move_cursor (@current_page - 1) * maxy
        else
          move_cursor (total_pages - 1) * maxy
        end
      end
    end

    def /
      @base.process_command_line prompt: ':grep '
    end

    def enter
      if current_item.directory?
        cd current_item
        ls
      else
        v
      end
    end
  end

  class Window
    def draw(contents)
      FFI::NCurses.mvwaddstr @window, 0, 0, contents
    end

    def wclear
      FFI::NCurses.wclear @window
    end

    def wrefresh
      FFI::NCurses.wrefresh @window
    end

    def maxx
      return @maxx if @maxx
      @maxy, @maxx = FFI::NCurses.getmaxyx @window
      @maxx
    end

    def maxy
      return @maxy if @maxy
      @maxy, @maxx = FFI::NCurses.getmaxyx @window
      @maxy
    end

    def begx
      return @begx if @begx
      @begy, @begx = FFI::NCurses.getbegyx @window
      @begx
    end

    def begy
      return @begy if @begy
      @begy, @begx = FFI::NCurses.getbegyx @window
      @begy
    end
  end

  # bordered Window
  class SubWindow < Window
    def initialize(*)
      border_window = FFI::NCurses.derwin FFI::NCurses.stdscr, maxy + 2, maxx + 2, begy - 1, begx - 1
      FFI::NCurses.box border_window, 0, 0
    end
  end

  class BaseWindow < Window
    attr_reader :header_l, :header_r, :main
    attr_writer :mode

    def initialize(dir = '.')
      init_colors

      @window = FFI::NCurses.stdscr
      @header_l = HeaderLeftWindow.new base: self
      @header_r = HeaderRightWindow.new base: self
      @main = MainWindow.new base: self, dir: dir
      @command_line = CommandLineWindow.new base: self
      @main.move_cursor
      @mode = MODE::COMMAND
    end

    def init_colors
      FFI::NCurses.init_pair FFI::NCurses::COLOR_WHITE, FFI::NCurses::COLOR_WHITE, FFI::NCurses::COLOR_BLACK
      FFI::NCurses.init_pair FFI::NCurses::COLOR_CYAN, FFI::NCurses::COLOR_CYAN, FFI::NCurses::COLOR_BLACK
    end

    def command_mode?
      @mode == MODE::COMMAND
    end

    def miel_mode?
      @mode == MODE::MIEL
    end

    def move_cursor(row)
      FFI::NCurses.wmove @window, row, 1
    end

    def debug(str)
      @header_r.wclear
      @header_r.debug str
    end

    def colon
      process_command_line
    end

    def process_command_line(prompt: ':')
      @command_line.set_prompt prompt
      cmd, *args = @command_line.get_command(prompt: prompt).split(' ')
      if @main.respond_to? cmd
        @main.public_send cmd, *args
        @command_line.wclear
        @command_line.wrefresh
      end
      FFI::NCurses.wstandend @window
    end

    def bs
      if command_mode? && (@dir != '/')
        @main.cd '..'
        @main.ls
      elsif miel_mode?
        @mode = MODE::COMMAND
        @main.close_viewer
        @main.move_cursor
      end
    end

    def space
      @main.toggle_mark
      @main.draw_marked_items
      @header_r.wrefresh
    end

    def q
      @main.q
    end
  end

  class HeaderLeftWindow < SubWindow
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 3, base.maxx - 32, 1, 1
      super
    end

    def draw_path_and_page_number(path: nil, current: 1, total: nil)
      @path_and_page_number = %Q[Page: #{"#{current}/ #{total}".ljust(11)}  Path: #{path}]
      FFI::NCurses.wmove @window, 0, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @path_and_page_number
    end

    def draw_current_file_info(current_file)
      draw_current_filename current_file.name
      draw_stat current_file
    end

    def draw_current_filename(current_file_name)
      @current_file_name = "File: #{current_file_name}"
      FFI::NCurses.wmove @window, 1, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @current_file_name
    end

    def draw_stat(item)
      @stat = "      #{item.size_or_dir.ljust(13)}#{item.mtime} #{item.mode}"
      FFI::NCurses.wmove @window, 2, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @stat
    end
  end

  class HeaderRightWindow < SubWindow
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 3, 29, 1, base.maxx - 30
      super
    end

    def draw_marked_items(count: 0, size: 0)
      FFI::NCurses.wmove @window, 1, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, %Q[#{"#{count}Marked".rjust(11)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(16)}]
    end

    def draw_total_items(count: 0, size: 0)
      FFI::NCurses.wmove @window, 2, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, %Q[#{"#{count}Files".rjust(10)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(17)}]
    end

    def debug(s)
      FFI::NCurses.mvwaddstr @window, 0, 0, s.to_s
    end
  end

  class MainWindow < SubWindow
    include Rfd::Commands

    def initialize(base: nil, dir: nil)
      @base = base
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, base.maxy - 7, base.maxx - 2, 5, 1
      @row = 0
      super

      cd dir
      ls
    end

    def current_item
      @items[@row]
    end

    def marked_items
      @items.select(&:marked?)
    end

    def selected_items
      (m = marked_items.any?) ? marked_items : Array(current_item)
    end

    def move_cursor(row = nil)
      if row
        page = row / maxy
        if page != @current_page
          switch_page page
          @row = row
        else
          prev, @row = @row, row
        end
      end

      @row ||= 0

      @base.move_cursor (begy + (row || @row)) % maxy
      if prev && (item = @items[prev])
        FFI::NCurses.wattr_set @window, FFI::NCurses::A_NORMAL, item.color, nil
        FFI::NCurses.mvwaddstr @window, prev % maxy, 0, "#{item.to_s}\n"
      end
      item = @items[row || @row]
      FFI::NCurses.wattr_set @window, FFI::NCurses::A_UNDERLINE, item.color, nil
      FFI::NCurses.mvwaddstr @window, @row % maxy, 0, "#{item.to_s}\n"
      FFI::NCurses.wstandend @window
      wrefresh

      @base.header_l.draw_current_file_info item
      @base.header_l.wrefresh
    end

    def switch_mode(mode)
      @base.mode = mode
    end

    def close_viewer
      @viewer.close
      ls
    end

    def cd(dir)
      @row = nil
      @dir = File.expand_path(dir.is_a?(Rfd::Item) ? dir.path : @dir ? File.join(@dir, dir) : dir)
    end

    def ls(page = nil)
      unless page
        fetch_items_from_filesystem
        sort_items_according_to_current_direction
      end
      @current_page = page ? page : 0

      wclear
      draw_items
      move_cursor (@row = nil)

      draw_marked_items
      draw_total_items
      @base.header_r.wrefresh
    end

    def sort(direction = nil)
      @direction, @current_page = direction, 0
      sort_items_according_to_current_direction
      switch_page 0
      move_cursor 0
    end

    def chmod(mode)
      FileUtils.chmod mode, selected_items.map(&:path)
      fetch_items_from_filesystem
      move_cursor @row
    end

    def fetch_items_from_filesystem
      @items = Dir.foreach(@dir).map {|fn| Item.new dir: @dir, name: fn}.to_a
    end

    def find(str)
      index = @items.index {|i| i.name.start_with? str}
      move_cursor index if index
    end

    def find_reverse(str)
      index = @items.reverse.index {|i| i.name.start_with? str}
      move_cursor @items.length - index - 1 if index
    end

    def draw_items
      FFI::NCurses.wmove @window, 0, 0
      @displayed_items = @items[@current_page * maxy, maxy]
      @displayed_items.each do |item|
        FFI::NCurses.wattr_set @window, FFI::NCurses::A_NORMAL, item.color, nil
        FFI::NCurses.waddstr @window, "#{item.to_s}\n"
      end
      FFI::NCurses.wstandend @window
      wrefresh

      draw_path_and_page_number
      @base.header_l.wrefresh
    end

    def sort_items_according_to_current_direction
      case @direction
      when nil
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map(&:sort)
      when 'r'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort.reverse}
      when 'S', 's'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by {|i| -i.size}}
      when 'Sr', 'sr'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:size)}
      when 't'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.mtime <=> x.mtime}}
      when 'tr'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:mtime)}
      when 'c'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.ctime <=> x.ctime}}
      when 'cr'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:ctime)}
      when 'u'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.atime <=> x.atime}}
      when 'ur'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:atime)}
      when 'e'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.extname <=> x.extname}}
      when 'er'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:extname)}
      end
      @items.each.with_index {|item, index| item.index = index}
    end

    def grep(pattern)
      regexp = Regexp.new(pattern)
      fetch_items_from_filesystem
      @items = @items.shift(2) + @items.select {|i| i.name =~ regexp}
      sort_items_according_to_current_direction
      switch_page 0
      move_cursor 0

      draw_total_items
      @base.header_r.wrefresh
    end

    def first_page?
      @current_page == 0
    end

    def last_page?
      @current_page == total_pages - 1
    end

    def total_pages
      @items.length / maxy + 1
    end

    def switch_page(page)
      @current_page = page
      wclear
      draw_items
    end

    def draw_path_and_page_number
      @base.header_l.draw_path_and_page_number path: @dir, current: @current_page + 1, total: total_pages
    end

    def draw_marked_items
      items = marked_items
      @base.header_r.draw_marked_items count: items.size, size: items.inject(0) {|sum, i| sum += i.size}
    end

    def draw_total_items
      @base.header_r.draw_total_items count: @items.size, size: @items.inject(0) {|sum, i| sum += i.size}
    end

    def toggle_mark
      FFI::NCurses.mvwaddstr @window, @row % maxy, 0, current_item.toggle_mark
      wrefresh
      j
    end

    def debug(str)
      @base.debug str
    end
  end

  class ViewerWindow < SubWindow
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, base.maxy - 10, base.maxx - 2, 8, 1
      super
    end

    def close
      wclear
    end
  end

  class CommandLineWindow < Window
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 1, base.maxx, base.maxy - 1, 0
    end

    def set_prompt(str)
      FFI::NCurses.wattr_set @window, FFI::NCurses::A_BOLD, FFI::NCurses::COLOR_WHITE, nil
      FFI::NCurses.mvwaddstr @window, 0, 0, str
      FFI::NCurses.wstandend @window
    end

    def get_command(prompt: nil)
      FFI::NCurses.echo
      startx = prompt ? prompt.length : 1
      s = ' ' * 100
      FFI::NCurses.mvwgetstr @window, 0, startx, s
      "#{prompt[1..-1] if prompt}#{s.strip}"
    ensure
      FFI::NCurses.noecho
    end
  end

  class Item
    include Comparable
    attr_reader :name
    attr_accessor :index

    def initialize(dir: nil, name: nil)
      @dir, @name, @marked = dir, name, false
    end

    def path
      @path ||= File.join @dir, @name
    end

    def basename
      @basename ||= File.basename name, extname
    end

    def extname
      @extname ||= File.extname name
    end

    def display_name
      if mb_size(@name) <= 43
        @name
      else
        "#{mb_left(basename, 42 - extname.length)}…#{extname}"
      end
    end

    def stat
      @stat ||= File.stat path
    end

    def color
      if directory?
        FFI::NCurses::COLOR_CYAN
      else
        FFI::NCurses::COLOR_WHITE
      end
    end

    def size
      directory? ? 0 : stat.size
    end

    def size_or_dir
      directory? ? '<DIR>' : size.to_s
    end

    def atime
      stat.atime.strftime('%Y-%m-%d %H:%M:%S')
    end

    def ctime
      stat.ctime.strftime('%Y-%m-%d %H:%M:%S')
    end

    def mtime
      stat.mtime.strftime('%Y-%m-%d %H:%M:%S')
    end

    def mode
      m = stat.mode
      ret = directory? ? 'd' : symlink? ? 'l' : '-'
      [(m & 0700) / 64, (m & 070) / 8, m & 07].inject(ret) do |str, s|
        str << "#{s & 4 == 4 ? 'r' : '-'}#{s & 2 == 2 ? 'w' : '-'}#{s & 1 == 1 ? 'x' : '-'}"
      end
      if m & 04000 != 0
        ret[3] = directory? ? 's' : 'S'
      end
      if m & 02000 != 0
        ret[6] = directory? ? 's' : 'S'
      end
      if m & 01000 == 512
        ret[-1] = directory? ? 't' : 'T'
      end
      ret
    end

    def directory?
      stat.directory?
    end

    def symlink?
      stat.symlink?
    end

    def read
      File.read path
    end

    def toggle_mark
      @marked = !@marked
      current_mark
    end

    def marked?
      @marked
    end

    def current_mark
      marked? ? '*' : ' '
    end

    def mb_left(str, size)
      len = 0
      index = str.each_char.with_index do |c, i|
        break i if len + mb_char_size(c) > size
        len += mb_size c
      end
      str[0, index]
    end

    def mb_char_size(c)
      c == '…' ? 1 : c.bytesize == 1 ? 1 : 2
    end

    def mb_size(str)
      str.each_char.inject(0) {|l, c| l += mb_char_size(c)}
    end

    def mb_ljust(str, size)
      "#{str}#{' ' * [0, size - mb_size(str)].max}"
    end

    def to_s
      "#{current_mark}#{mb_ljust(display_name, 43)}#{size_or_dir.rjust(13)}"
    end

    def <=>(o)
      if directory? && !o.directory?
        1
      elsif !directory? && o.directory?
        -1
      else
        name <=> o.name
      end
    end
  end
end
