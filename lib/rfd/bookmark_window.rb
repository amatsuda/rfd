# frozen_string_literal: true

module Rfd
  class BookmarkWindow < SubWindow
    def initialize(controller)
      super(controller)
      @cursor = 0
      @scroll = 0
      @filter = FilterInput.new { apply_filter }
      @filtered_items = nil
    end

    def all_items
      Bookmark.bookmarks
    end

    def display_items
      @filtered_items || all_items
    end

    def current_bookmarked?
      Bookmark.include?(controller.current_dir.path)
    end

    def visible_items
      display_items[@scroll, max_height - 1] || []
    end

    def current_item
      display_items[@cursor]
    end

    def render
      reposition_if_needed
      @window.clear

      draw_border('Bookmarks (@:tree ^B:add/remove ESC:close)')

      # Filter input line (row 1)
      @filter.render(@window, 1, max_width)

      # Bookmarks list starts at row 2
      visible_items.each_with_index do |path, i|
        actual_index = @scroll + i
        @window.setpos(2 + i, 1)

        display_path = path.sub(File.expand_path('~'), '~')
        if actual_index == @cursor
          @window.attron(Curses::A_REVERSE) { @window.addstr(display_path[0, max_width].ljust(max_width)) }
        else
          @window.addstr(display_path[0, max_width].ljust(max_width))
        end
      end

      @window.refresh
    end

    def handle_input(c)
      case c
      when 27  # ESC - close window
        controller.close_sub_window
        true
      when 64, ?@  # @ - switch to tree view
        controller.close_sub_window
        controller.instance_variable_set(:@sub_window, NavigationWindow.new(controller))
        controller.instance_variable_get(:@sub_window).render
        true
      when 2  # Ctrl-B - toggle bookmark for current directory
        toggle_bookmark
        true
      when 10, 13  # Enter - cd to selected bookmark
        select_item
        true
      when 14  # Ctrl-N
        move_cursor_down
        true
      when 16  # Ctrl-P
        move_cursor_up
        true
      else
        if @filter.handle_input(c)
          render
          true
        else
          false
        end
      end
    end

    private

    def apply_filter
      if @filter.empty?
        @filtered_items = nil
      else
        @filtered_items = all_items.select { |path| @filter.fuzzy_match?(path) }
      end
      @cursor = 0
      @scroll = 0
    end

    def toggle_bookmark
      Bookmark.toggle(controller.current_dir.path)
      apply_filter  # Re-apply filter in case list changed
      render
    end

    def select_item
      item = current_item
      return unless item

      controller.close_sub_window
      controller.cd(item)
    end

    def move_cursor_down
      return if @cursor >= display_items.size - 1

      @cursor += 1
      adjust_scroll
      render
    end

    def move_cursor_up
      return if @cursor <= 0

      @cursor -= 1
      adjust_scroll
      render
    end

    def adjust_scroll
      available_height = max_height - 1  # Reserve one line for filter
      if @cursor < @scroll
        @scroll = @cursor
      elsif @cursor >= @scroll + available_height
        @scroll = @cursor - available_height + 1
      end
    end
  end
end
