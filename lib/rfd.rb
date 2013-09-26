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
      @window.clear
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
      @window.setpos 0, 0
      @window.addstr contents
      @window.refresh
    end
  end

  # bordered Window
  class SubWindow < Window
    def initialize(*)
      border_window = Curses.stdscr.subwin @window.maxy + 2, @window.maxx + 2, @window.begy - 1, @window.begx - 1
      border_window.box ?|, ?-
    end
  end

  class BaseWindow < Window
    attr_reader :header, :main
    attr_writer :mode

    def initialize(dir = '.')
      init_colors

      @window = Curses.stdscr
      @window.box ?|, ?-
      @header = HeaderWindow.new
      @main = MainWindow.new base: self, dir: dir
      @main.move_cursor
      @mode = MODE::COMMAND
    end

    def init_colors
      Curses.init_pair Curses::COLOR_WHITE, Curses::COLOR_WHITE, Curses::COLOR_BLACK
      Curses.init_pair Curses::COLOR_CYAN, Curses::COLOR_CYAN, Curses::COLOR_BLACK
    end
    def command_mode?
      @mode == MODE::COMMAND
    end

    def miel_mode?
      @mode == MODE::MIEL
    end

    def move_cursor(row)
      @window.setpos row, 1
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

  class HeaderWindow < SubWindow
    def initialize
      @window = Curses.stdscr.subwin 6, Curses.stdscr.maxx - 2, 1, 1
      super
    end

    def draw_page_number(current: 1, total: nil)
      draw "Page: #{current}/ #{total}"
    end
  end

  class MainWindow < SubWindow
    include Rfd::Commands

    def initialize(base: nil, dir: nil)
      @base = base
      @window = Curses.stdscr.subwin Curses.stdscr.maxy - 9, Curses.stdscr.maxx - 2, 8, 1
      @row = 0
      super

      cd dir
      ls
      @window.refresh
    end

    def current_item
      @items[@row]
    end

    def move_cursor(row = nil)
      @base.move_cursor @window.begy + (row || @row)
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
      @window.clear
      @items = Dir.foreach(@dir).map {|fn| Item.new dir: @dir, name: fn}.to_a unless page
      @items[(page || 0) * @window.maxy, @window.maxy].each do |item|
        @window.attron Curses.color_pair(item.color) do
          @window.addstr "#{item.to_s}\n"
        end
      end
      @window.refresh
      draw_page_number
      move_cursor 0
    end

    def draw_page_number
      @base.header.draw_page_number current: @row / @window.maxy + 1, total: @items.size / @window.maxy + 1
    end
  end

  class ViewerWindow < SubWindow
    def initialize
      @window = Curses.stdscr.subwin Curses.stdscr.maxy - 9, Curses.stdscr.maxx - 2, 8, 1
    end

    def close
      @window.close
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
        Curses::COLOR_CYAN
      else
        Curses::COLOR_WHITE
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
