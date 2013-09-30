require 'fileutils'

module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  module MODE
    COMMAND = :command
    MIEL = :miel
  end

  module Commands
    def d
      FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
      ls
    end

    def j
      if @row + 1 >= @displayed_items.size
        switch_page last_page? ? 0 : @current_page + 1
      else
        move_cursor @row + 1
      end
    end

    def k
      if @row == 0
        switch_page (first_page? ? @total_pages - 1 : @current_page - 1)
        move_cursor @displayed_items.size - 1
      else
        move_cursor @row - 1
      end
    end

    def q
      raise StopIteration
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
      ls
    end

    def H
      move_cursor 0
    end

    def L
      move_cursor @displayed_items.size - 1
    end

    def M
      move_cursor @displayed_items.size / 2
    end

    def ctrl_n
      if @total_pages > 1
        if @current_page + 1 < @total_pages
          switch_page @current_page + 1
        else
          switch_page 0
        end
      end
    end

    def ctrl_p
      if @total_pages > 1
        if @current_page > 0
          switch_page @current_page - 1
        else
          switch_page @total_pages - 1
        end
      end
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
      FFI::NCurses.wmove @window, 0, 0
      FFI::NCurses.waddstr @window, contents
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
    attr_reader :header, :main
    attr_writer :mode

    def initialize(dir = '.')
      init_colors

      @window = FFI::NCurses.stdscr
      @header = HeaderWindow.new base: self
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
      p str
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
    end

    def q
      @main.q
    end
  end

  class HeaderWindow < SubWindow
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 6, base.maxx - 2, 1, 1
      super
    end

    def draw_path_and_page_number(path: nil, current: 1, total: nil)
      @path_and_page_number = %Q[Page: #{"#{current}/ #{total}".ljust(10)}  Path: #{path}]
      FFI::NCurses.wmove @window, 0, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @path_and_page_number
    end

    def draw_current_filename(current_file_name)
      @current_file_name = "File: #{current_file_name}"
      FFI::NCurses.wmove @window, 1, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @current_file_name
    end
  end

  class MainWindow < SubWindow
    include Rfd::Commands

    def initialize(base: nil, dir: nil)
      @base = base
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, base.maxy - 10, base.maxx - 2, 8, 1
      @row = 0
      super

      cd dir
      ls
      wrefresh
    end

    def current_item
      @items[@current_page * maxy + @row]
    end

    def selected_items
      (marked = @items.select(&:marked?)).any? ? marked : Array(current_item)
    end

    def move_cursor(row = nil)
      prev, @row = @row, row if row
      @row ||= 0

      @base.move_cursor begy + (row || @row)
      if prev
        item = @displayed_items[prev]
        FFI::NCurses.wattr_set @window, FFI::NCurses::A_NORMAL, item.color, nil
        FFI::NCurses.mvwaddstr @window, prev, 0, "#{item.to_s}\n"
      end
      item = @displayed_items[row || @row]
      FFI::NCurses.wattr_set @window, FFI::NCurses::A_UNDERLINE, item.color, nil
      FFI::NCurses.mvwaddstr @window, @row, 0, "#{item.to_s}\n"
      FFI::NCurses.wstandend @window
      wrefresh

      @base.header.draw_current_filename item.name
      @base.header.wrefresh
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
      wclear

      unless page
        @items = Dir.foreach(@dir).map {|fn| Item.new dir: @dir, name: fn}.to_a
        @total_pages = @items.size / maxy + 1
      end
      @current_page = page ? page : 0

      @displayed_items = @items[@current_page * maxy, maxy]
      @displayed_items.each do |item|
        FFI::NCurses.wattr_set @window, FFI::NCurses::A_NORMAL, item.color, nil
        FFI::NCurses.waddstr @window, "#{item.to_s}\n"
      end
      FFI::NCurses.wstandend @window
      wrefresh

      draw_path_and_page_number
      move_cursor (@row = nil)
      @base.header.wrefresh
    end

    def first_page?
      @current_page == 0
    end

    def last_page?
      @current_page == @total_pages - 1
    end

    def switch_page(page)
      ls (@current_page = page)
    end

    def draw_path_and_page_number
      @base.header.draw_path_and_page_number path: @dir, current: @current_page + 1, total: @total_pages
    end

    def toggle_mark
      FFI::NCurses.mvwaddstr @window, @row, 0, current_item.toggle_mark
      wrefresh
      j
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
      FFI::NCurses.box @window, 0, 0
    end
  end

  class Item
    attr_reader :name

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
      if directory?
        '<DIR>'
      else
        stat.size
      end
    end

    def directory?
      stat.directory?
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
      "#{current_mark}#{mb_ljust(display_name, 43)}#{size.to_s.rjust(13)}"
    end
  end
end
