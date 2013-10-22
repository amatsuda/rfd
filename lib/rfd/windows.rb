module Rfd
  class Window
    attr_reader :window, :maxy, :maxx, :begy, :begx

    def self.draw_borders
      [[5, Curses.stdscr.maxx, 0, 0], [5, Curses.cols - 30, 0, 0], [Curses.stdscr.maxy - 5, Curses.stdscr.maxx, 4, 0]].each do |height, width, top, left|
        w = Curses.stdscr.subwin height, width, top, left
        w.bkgdset Curses.color_pair(Curses::COLOR_CYAN)
        w.box 0, 0
        w.close
      end
    end

    def initialize
      @window = Curses.stdscr.subwin @maxy, @maxx, @begy, @begx
    end

    def wmove(y, x = 0)
      window.setpos y, x
    end

    def waddstr(str, clear_to_eol_before_add: false)
      window.clrtoeol if clear_to_eol_before_add
      window.addstr str
    end

    def wclear
      window.clear
    end

    def wrefresh
      window.refresh
    end
  end

  class HeaderLeftWindow < Window
    def initialize
      @maxy, @maxx, @begy, @begx = 3, Curses.cols - 32, 1, 1
      super
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
      @maxy, @maxx, @begy, @begx = 3, 29, 1, Curses.cols - 30
      super
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
      window.clrtoeol
      waddstr s.to_s
      wrefresh
    end
  end

  class MainWindow < Window
    attr_reader :current_index
    def initialize(dir = '.')
      @maxy, @begy, @current_index = Curses.lines - 7, 5, 0

      spawn_panes 2
    end

    def newpad(items)
      if defined? @window
        @window.clear
        @window.close
      end
      columns = items.size / maxy + 1

      @window = Curses::Pad.new maxy, width * (((columns - 1) / @number_of_panes + 1) * @number_of_panes)
      draw_items_to_each_pane items
    end

    def spawn_panes(num)
      @number_of_panes = num
    end

    def display(page)
      @window.refresh 0, (Curses.cols - 2) * page, begy, 1, begy + maxy - 1, Curses.cols - 2
    end

    def activate_pane(num)
      @current_index = num
    end

    def pane_index_at(y: nil, x: nil)
      (y >= window.begy) && (window.begy + window.maxy > y) && (x / width)
    end

    # overriding attr_reader
    def begx
      window.begx
    end

    def width
      (Curses.cols - 2) / @number_of_panes
    end

    def max_items
      maxy * @number_of_panes
    end

    def draw_item(item, current: false)
      window.setpos item.index % maxy, width * @current_index
      window.attron(Curses.color_pair(item.color) | (current ? Curses::A_UNDERLINE : Curses::A_NORMAL)) do
        window.addstr item.to_s
      end
    end

    def draw_items_to_each_pane(items)
      items.each_slice(maxy).each.with_index do |arr, col_index|
        arr.each.with_index do |item, i|
          @window.setpos i, width * col_index
          @window.attron(Curses.color_pair(item.color) | Curses::A_NORMAL) { @window.addstr item.to_s }
        end
      end
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
      @maxy, @maxx, @begy, @begx = 1, Curses.cols, Curses.lines - 1, 0
      super
    end

    def set_prompt(str)
      window.attron(Curses.color_pair(Curses::COLOR_WHITE) | Curses::A_BOLD) do
        wmove 0
        window.clrtoeol
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
        window.clrtoeol
        waddstr str
      end
      wrefresh
    end
  end
end
