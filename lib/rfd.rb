module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  class Window
    def draw(contents)
      @win.addstr contents
      @win.refresh
    end
  end

  # bordered Window
  class SubWindow < Window
    def initialize(*)
      border_window = Curses.stdscr.subwin @win.maxy + 2, @win.maxx + 2, @win.begy - 1, @win.begx - 1
      border_window.box ?|, ?-, ?*
    end
  end

  class BaseWindow < Window
    def initialize(dir = '.')
      @win = Curses.stdscr
      @win.box ?|, ?-, ?*
      @main = MainWindow.new dir
    end
  end

  class MainWindow < SubWindow
    def initialize(dir)
      @win = Curses.stdscr.subwin Curses.stdscr.maxy - 9, Curses.stdscr.maxx - 2, 8, 1
      super
    end
  end
end
