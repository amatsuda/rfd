module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  class Window
    def draw(contents)
      @win.setpos 2, 2
      @win.addstr contents
      @win.refresh
    end
  end

  class MainWindow < Window
    def initialize(dir = '.')
      @win = Curses.stdscr
    end
  end
end
