require 'fileutils'

module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  module MODE
    COMMAND = :command
    MIEL = :miel
  end

  module Commands
    def d
      FileUtils.mv current_item.path, File.expand_path('~/.Trash/')
      ls
    end

    def k
      @row -= 1
      @row = @items.size - 1 if @row <= 0
      move_cursor
    end

    def j
      @row += 1
      @row = 0 if @row >= @items.size
      move_cursor
    end

    def q
      raise StopIteration
    end

    def v
      switch_mode MODE::MIEL
      FFI::NCurses.wclear @window
      @viewer = ViewerWindow.new
      @viewer.draw current_item.read
    end

    def D
      FileUtils.rm_rf current_item.path
      ls
    end

    def H
      move_cursor @row = 0
    end

    def L
      move_cursor @row = @items.size - 1
    end

    def M
      move_cursor @row = @items.size / 2
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
      FFI::NCurses.wrefresh @window
    end
  end

  class BaseWindow < Window
    attr_reader :header, :main
    attr_writer :mode

    def initialize(dir = '.')
      init_colors

      @window = FFI::NCurses.stdscr
      FFI::NCurses.box @window, 0, 0
      @header = HeaderWindow.new
      @main = MainWindow.new base: self, dir: dir
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

    def enter
      @main.enter
    end

    def bs
      if miel_mode?
        @mode = MODE::COMMAND
        @main.close_viewer
        @main.move_cursor
      end
    end

    def q
      @main.q
    end
  end

  class HeaderWindow < Window
    def initialize
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 6, FFI::NCurses.getmaxx(FFI::NCurses.stdscr) - 2, 1, 1
      FFI::NCurses.box @window, 0, 0
    end

    def draw_page_number(current: 1, total: nil)
      draw "Page: #{current}/ #{total}"
    end
  end

  class MainWindow < Window
    include Rfd::Commands

    def initialize(base: nil, dir: nil)
      @base = base
      y, x = FFI::NCurses.getmaxyx FFI::NCurses.stdscr
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, y - 9, x - 2, 8, 1
      FFI::NCurses.box @window, 0, 0
      @row = 0

      cd dir
      ls
      FFI::NCurses.wrefresh @window
    end

    def current_item
      @items[@row]
    end

    def move_cursor(row = nil)
      @base.move_cursor FFI::NCurses.getbegy(@window) + (row || @row)
    end

    def switch_mode(mode)
      @base.mode = mode
    end

    def close_viewer
      @viewer.close
      ls
    end

    def cd(dir)
      @dir = File.expand_path(dir.is_a?(Rfd::Item) ? dir.path : dir)
    end

    def ls(page = nil)
      FFI::NCurses.wclear @window
      maxy, maxx = FFI::NCurses.getmaxyx @window

      unless page
        @items = Dir.foreach(@dir).map {|fn| Item.new dir: @dir, name: fn}.to_a
        @total_pages = @items.size / maxy + 1
      end
      @current_page = page ? page : 0

      @items[@current_page * maxy, maxy].each do |item|
        FFI::NCurses.wattr_set @window, FFI::NCurses::A_NORMAL, item.color, nil
        FFI::NCurses.waddstr @window, "#{item.to_s}\n"
      end
      FFI::NCurses.wstandend @window
      FFI::NCurses.wrefresh @window
      draw_page_number
      move_cursor 0
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

    def draw_page_number
      @base.header.draw_page_number current: @current_page + 1, total: @total_pages
    end
  end

  class ViewerWindow < Window
    def initialize
      y, x = FFI::NCurses.getmaxyx FFI::NCurses.stdscr
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, y - 9, x - 2, 8, 1
    end

    def close
      FFI::NCurses.wclear @window
    end
  end

  class Item
    def initialize(dir: nil, name: nil)
      @dir, @name = dir, name
    end

    def path
      @path ||= File.join @dir, @name
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

    def to_s
      "#{@name.ljust(43)}#{size}"
    end
  end
end
