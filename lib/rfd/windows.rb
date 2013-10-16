module Rfd
  class Window
    ACS_URCORNER = 4194411
    ACS_LRCORNER = 4194410
    ACS_ULCORNER = 4194412
    ACS_LLCORNER = 4194413
    ACS_HLINE = 4194417
    ACS_LTEE = 4194420
    ACS_RTEE = 4194421
    ACS_BTEE = 4194422
    ACS_TTEE = 4194423
    ACS_VLINE = 4194424

    attr_reader :window

    def self.draw_borders
      Curses.attron Curses.color_pair(Curses::COLOR_CYAN) do
        Curses.addch ACS_ULCORNER
        (Curses.cols - 32).times { Curses.addch ACS_HLINE }
        Curses.addch ACS_TTEE
        29.times { Curses.addch ACS_HLINE }
        Curses.addch ACS_URCORNER

        [*1..3, *5..(Curses.lines - 3)].each do |i|
          Curses.setpos i, 0
          Curses.addch ACS_VLINE
          Curses.setpos i, Curses.cols - 1
          Curses.addch ACS_VLINE
        end
        [1, 2, 3].each do |i|
          Curses.setpos i, Curses.cols - 31
          Curses.addch ACS_VLINE
        end

        Curses.setpos 4, 0
        Curses.addch ACS_LTEE
        (Curses.cols - 32).times { Curses.addch ACS_HLINE }
        Curses.addch ACS_BTEE
        29.times { Curses.addch ACS_HLINE }
        Curses.addch ACS_RTEE

        Curses.setpos Curses.lines - 2, 0
        Curses.addch ACS_LLCORNER
        (Curses.cols - 2).times { Curses.addch ACS_HLINE }
        Curses.addch ACS_LRCORNER
      end
    end

    def wmove(y, x = 0)
      window.setpos y, x
    end

    def waddstr(str, clear_to_eol_before_add: false)
      wclrtoeol if clear_to_eol_before_add
      window.addstr str
    end

    def wclear
      window.clear
    end

    def wrefresh
      window.refresh
    end

    def maxx
      window.maxx
    end

    def maxy
      window.maxy
    end

    def begx
      window.begx
    end

    def begy
      window.begy
    end

    def wclrtoeol
      window.clrtoeol
    end
  end

  class HeaderLeftWindow < Window
    def initialize
      @window = Curses.stdscr.subwin 3, Curses.cols - 32, 1, 1
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
      @window = Curses.stdscr.subwin 3, 29, 1, Curses.cols - 30
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

      def get_index_by_point(y: nil, x: nil)
        @panes.each.with_index do |p, i|
          return i if include_point? pane: p, y: y, x: x
        end if y && x
        nil
      end

      def size
        @panes.size
      end

      def close_all
        @panes.each do |p|
          p.clear
          p.close
        end
      end

      def include_point?(pane: pane, y: nil, x: nil)
        (y >= pane.begy) && (pane.begy + pane.maxy > y) && (x >= pane.begx) && (pane.begx + pane.maxx > x)
      end
    end

    def initialize(dir = '.')
      spawn_panes 2
    end

    def spawn_panes(num)
      @panes.close_all if defined? @panes
      width = (Curses.cols - 2) / num
      windows = 0.upto(num - 1).inject([]) {|arr, i| arr << Curses.stdscr.subwin(Curses.lines - 7, width - 1, 5, width * i + 1)}
      @panes = Panes.new windows
      activate_pane 0
    end

    def activate_pane(num)
      @panes.activate num
    end

    def pane_index_at(y: nil, x: nil)
      @panes.get_index_by_point y: y, x: x
    end

    def window
      @panes.active
    end

    def max_items
      maxy * @panes.size
    end

    def draw_item(item, current: false)
      window.setpos item.index % maxy, 0
      window.attron(Curses.color_pair(item.color) | (current ? Curses::A_UNDERLINE : Curses::A_NORMAL)) do
        window.addstr "#{item.to_s}\n"
      end
      wrefresh
    end

    def draw_items_to_each_pane(items)
      original_active_pane_index = @panes.current_index

      0.upto(@panes.size - 1) do |index|
        activate_pane index
        wclear
        wmove 0
        items[maxy * index, maxy * (index + 1)].each do |item|
          window.attron(Curses.color_pair(item.color) | Curses::A_NORMAL) { waddstr "#{item.to_s}\n" }
        end if items[maxy * index, maxy * (index + 1)]
        wrefresh
      end
      activate_pane original_active_pane_index
    end

    def toggle_mark(item)
      if item.toggle_mark
        window.setpos item.index % maxy, 0
        window.addstr item.current_mark
      end
    end
  end

  class CommandLineWindow < Window
    def initialize
      @window = Curses.stdscr.subwin 1, Curses.cols, Curses.lines - 1, 0
    end

    def set_prompt(str)
      window.attron(Curses.color_pair(Curses::COLOR_WHITE) | Curses::A_BOLD) do
        wmove 0
        wclrtoeol
        waddstr str
      end
    end

    def get_command(prompt: nil)
      Curses.echo
      startx = prompt ? prompt.size : 1
      window.setpos 0, startx
      s = window.getstr
      "#{prompt[1..-1] if prompt}#{s.strip}"
    ensure
      Curses.noecho
    end

    def show_error(str)
      window.attron(Curses.color_pair(Curses::COLOR_RED) | Curses::A_BOLD) do
        wmove 0
        wclrtoeol
        waddstr str
      end
      wrefresh
    end
  end
end
