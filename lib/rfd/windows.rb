module Rfd
  class Window
    attr_reader :window

    def wmove(y, x = 0)
      Curses.wmove window, y, x
    end

    def waddstr(str, clear_to_eol_before_add: false)
      wclrtoeol if clear_to_eol_before_add
      Curses.waddstr window, str
    end

    def mvwaddstr(y, x, str)
      Curses.mvwaddstr window, y, x, str
    end

    def wclear
      Curses.wclear window
    end

    def wrefresh
      Curses.wrefresh window
    end

    def maxx
      Curses.getmaxx window
    end

    def maxy
      Curses.getmaxy window
    end

    def begx
      Curses.getbegx window
    end

    def begy
      Curses.getbegy window
    end

    def subwin(height, width, top, left)
      Curses.derwin Curses.stdscr, height, width, top, left
    end

    def wclrtoeol
      Curses.wclrtoeol window
    end

    def draw_border(*border_param)
      border_window = subwin maxy + 2, maxx + 2, begy - 1, begx - 1
      Curses.wbkgd border_window, Curses.COLOR_PAIR(Curses::COLOR_CYAN)
      Curses.wborder border_window, *border_param
    end
  end

  class HeaderLeftWindow < Window
    def initialize
      @window = subwin 3, Curses.COLS - 32, 1, 1
      draw_border 0, 0, 0, 0, 0, 0, Curses::ACS_LTEE, 0
    end

    def draw_path_and_page_number(path: nil, current: 1, total: nil)
      @path_and_page_number = %Q[Page: #{"#{current}/ #{total}".ljust(11)}  Path: #{path}]
      wmove 0
      waddstr @path_and_page_number, clear_to_eol_before_add: true
      wrefresh
    end

    def draw_current_file_info(current_file)
      draw_current_filename current_file.full_display_name
      draw_stat current_file
    end

    def draw_current_filename(current_file_name)
      @current_file_name = "File: #{current_file_name}"
      wmove 1
      waddstr @current_file_name, clear_to_eol_before_add: true
    end

    def draw_stat(item)
      @stat = "      #{item.size_or_dir.ljust(13)}#{item.mtime} #{item.mode}"
      wmove 2
      waddstr @stat, clear_to_eol_before_add: true
    end
  end

  class HeaderRightWindow < Window
    def initialize
      @window = subwin 3, 29, 1, Curses.COLS - 30
      draw_border 0, 0, 0, 0, Curses::ACS_TTEE, 0, Curses::ACS_BTEE, Curses::ACS_RTEE
    end

    def draw_marked_items(count: 0, size: 0)
      wmove 1
      waddstr %Q[#{"#{count}Marked".rjust(11)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(16)}], clear_to_eol_before_add: true
    end

    def draw_total_items(count: 0, size: 0)
      wmove 2
      waddstr %Q[#{"#{count}Files".rjust(10)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(17)}], clear_to_eol_before_add: true
      wrefresh
    end

    def debug(s)
      wmove 0, 0
      wclrtoeol
      waddstr s.to_s
      wrefresh
    end
  end

  class MainWindow < Window
    class Panes
      attr_reader :current_index

      def initialize(panes)
        @panes, @current_index = panes, 0
      end

      def active
        @panes[@current_index]
      end

      def activate(index)
        @current_index = index if index < @panes.size
      end

      def activate_by_point(y: nil, x: nil)
        @panes.each.with_index do |p, i|
          @current_index = i and return p if include_point? pane: p, y: y, x: x
        end if y && x
        nil
      end

      def size
        @panes.size
      end

      def close_all
        @panes.each {|p| Curses.delwin p}
      end

      def include_point?(pane: pane, y: nil, x: nil)
        (y >= Curses.getbegy(pane)) && (Curses.getbegy(pane) + Curses.getmaxy(pane) > y) && (x >= Curses.getbegx(pane)) && (Curses.getbegx(pane) + Curses.getmaxx(pane) > x)
      end
    end

    def initialize(dir = '.')
      border_window = subwin Curses.LINES - 5, Curses.COLS, 4, 0
      Curses.wbkgd border_window, Curses::COLOR_PAIR(Curses::COLOR_CYAN)
      Curses.box border_window, 0, 0

      spawn_panes 2
    end

    def spawn_panes(num)
      @panes.close_all if defined? @panes
      width = (Curses.COLS - 2) / num
      windows = 0.upto(num - 1).inject([]) {|arr, i| arr << subwin(Curses.LINES - 7, width - 1, 5, width * i + 1)}
      @panes = Panes.new windows
      activate_pane 0
    end

    def activate_pane(num)
      @panes.activate num
    end

    def activate_pane_at(y: nil, x: nil)
      @panes.activate_by_point y: y, x: x
    end

    def window
      @panes.active
    end

    def max_items
      maxy * @panes.size
    end

    def draw_item(item, current: false)
      Curses.wattr_set window, current ? Curses::A_UNDERLINE : Curses::A_NORMAL, item.color, nil
      mvwaddstr item.index % maxy, 0, "#{item.to_s}\n"
      Curses.wstandend window
      wrefresh
    end

    def draw_items_to_each_pane(items)
      original_active_pane_index = @panes.current_index

      0.upto(@panes.size - 1) do |index|
        activate_pane index
        wclear
        wmove 0
        items[maxy * index, maxy * (index + 1)].each do |item|
          Curses.wattr_set window, Curses::A_NORMAL, item.color, nil
          waddstr "#{item.to_s}\n"
        end if items[maxy * index, maxy * (index + 1)]
        Curses.wstandend window
        wrefresh
      end
      activate_pane original_active_pane_index
    end

    def toggle_mark(item)
      mvwaddstr item.index % maxy, 0, item.current_mark if item.toggle_mark
    end
  end

  class CommandLineWindow < Window
    def initialize
      @window = subwin 1, Curses.COLS, Curses.LINES - 1, 0
    end

    def set_prompt(str)
      Curses.wattr_set window, Curses::A_BOLD, Curses::COLOR_WHITE, nil
      wmove 0
      wclrtoeol
      waddstr str
      Curses.wstandend window
    end

    def get_command(prompt: nil)
      Curses.echo
      startx = prompt ? prompt.size : 1
      s = ' ' * 100
      Curses.mvwgetstr window, 0, startx, s
      "#{prompt[1..-1] if prompt}#{s.strip}"
    ensure
      Curses.noecho
    end

    def show_error(str)
      Curses.wattr_set window, Curses::A_BOLD, Curses::COLOR_RED, nil
      wmove 0
      wclrtoeol
      waddstr str
      wrefresh
      Curses.wstandend window
    end
  end
end
