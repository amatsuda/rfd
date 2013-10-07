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
      startx = prompt ? prompt.length : 1
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
