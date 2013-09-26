module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  class Window
    def draw(contents)
      @win.setpos 0, 0
      @win.addstr contents
      @win.refresh
    end
  end

  # bordered Window
  class SubWindow < Window
    def initialize(*)
      border_window = Curses.stdscr.subwin @win.maxy + 2, @win.maxx + 2, @win.begy - 1, @win.begx - 1
      border_window.box ?|, ?-
    end
  end

  class BaseWindow < Window
    def initialize(dir = '.')
      init_colors

      @win = Curses.stdscr
      @win.box ?|, ?-
      @header = HeaderWindow.new
      @main = MainWindow.new base: self, dir: dir
      @main.move_cursor 0
    end

    def init_colors
      Curses.init_pair Curses::COLOR_WHITE, Curses::COLOR_WHITE, Curses::COLOR_BLACK
      Curses.init_pair Curses::COLOR_CYAN, Curses::COLOR_CYAN, Curses::COLOR_BLACK
    end

    def move_cursor(row)
      @win.setpos row, 1
    end

    def debug(str)
      @header.draw str
    end

    def k
      @main.k
    end

    def j
      @main.j
    end

    def q
      raise StopIteration
    end

    def v
      @main.v
    end
  end

  class HeaderWindow < SubWindow
    def initialize
      @win = Curses.stdscr.subwin 6, Curses.stdscr.maxx - 2, 1, 1
      super
    end
  end

  class MainWindow < SubWindow
    def initialize(base: nil, dir: nil)
      @base, @dir = base, dir
      @win = Curses.stdscr.subwin Curses.stdscr.maxy - 9, Curses.stdscr.maxx - 2, 8, 1
      @row = 0
      super

      ls
      @win.refresh
    end

    def move_cursor(row)
      @base.move_cursor @win.begy + row
    end

    def ls
      @items = Dir.foreach(@dir).map {|fn| Item.new dir: @dir, name: fn}
      @items.each do |item|
        @win.attron Curses.color_pair(item.color) do
          @win.addstr "#{item.to_s}\n"
        end
      end
    end

    def k
      @row -= 1
      @row = @items.size - 1 if @row <= 0
      move_cursor @row
    end

    def j
      @row += 1
      @row = 0 if @row >= @items.size
      move_cursor @row
    end

    def v
      draw @items[@row].read
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
