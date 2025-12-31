# frozen_string_literal: true

module Rfd
  # Base class for sub-windows (preview, tree, etc.)
  class SubWindow
    attr_reader :window, :controller

    def initialize(controller)
      @controller = controller
      @window = create_window
    end

    def create_window
      Curses::Window.new(height, width, top, left)
    end

    def height
      controller.main.maxy
    end

    def width
      controller.main.width
    end

    def top
      controller.main.begy
    end

    def left
      # Sub window goes in the next pane (to the right of cursor, wrapping around)
      visible_pane = controller.main.current_index % controller.main.number_of_panes
      next_pane = (visible_pane + 1) % controller.main.number_of_panes
      next_pane * width + 1
    end

    def close
      @window.close
    end

    def max_width
      @window.maxx - 2
    end

    def max_height
      @window.maxy - 2
    end

    # Reposition window if cursor pane changed
    def reposition_if_needed
      expected_x = left
      if @window.begx != expected_x
        @window.close
        @window = Curses::Window.new(height, width, top, expected_x)
        controller.main.display controller.current_page
        true
      else
        false
      end
    end

    def draw_border(title = nil)
      @window.bkgdset Curses.color_pair(Curses::COLOR_CYAN)
      Rfd::Window.draw_ncursesw_border(@window, @window.maxy, @window.maxx)
      if title
        @window.setpos(0, 2)
        @window.addstr(" #{title} "[0, @window.maxx - 4])
      end
      @window.bkgdset Curses.color_pair(Curses::COLOR_WHITE)
    end

    # Override in subclasses
    def render
      raise NotImplementedError
    end

    # Override in subclasses - return true if input was handled
    def handle_input(c)
      false
    end

    def refresh
      @window.refresh
    end
  end
end
