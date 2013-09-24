module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  class Window
    def draw(contents)
      @win.setpos 2, 2
      @win.addstr contents
      @win.refresh
    end
  end

  class BaseWindow < Window
    def initialize(dir = '.')
      @win = Curses.stdscr
      @win.box ?|, ?-, ?*
      @main = MainWindow.new dir
    end
  end

  class MainWindow < Window
    def initialize(dir)
      @win = Curses.stdscr.subwin Curses.stdscr.maxy - 6, Curses.stdscr.maxx, 6, 0
      @win.box ?|, ?-, ?*
    end
  end
end
