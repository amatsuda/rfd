# frozen_string_literal: true
require 'delegate'

module Rfd
  class Window < DelegateClass(Curses::Window)
    def self.draw_borders
      [[5, Curses.stdscr.maxx, 0, 0], [5, Curses.cols - 30, 0, 0], [Curses.stdscr.maxy - 5, Curses.stdscr.maxx, 4, 0]].each do |height, width, top, left|
        w = Curses.stdscr.subwin height, width, top, left
        w.bkgdset Curses.color_pair(Curses::COLOR_CYAN)
        draw_ncursesw_border(w, height, width)
        w.close
      end
    end

    # Detect if linked against ncursesw (not ncurses)
    def self.ncursesw?
      return @ncursesw if defined?(@ncursesw)

      bundle = $LOADED_FEATURES.find { |f| f =~ /curses\.bundle|curses\.so/ }
      @ncursesw = bundle && `otool -L "#{bundle}" 2>/dev/null`.include?('libncursesw')
    end

    # Draw borders using ncursesw box drawing characters
    def self.draw_ncursesw_border(window, height, width)
      if ncursesw?
        # Use Unicode box drawing characters with ncursesw
        h_line = '─' * (width - 2)
        window.setpos(0, 0)
        window.addstr("╭#{h_line}╮")

        (1..(height - 2)).each do |y|
          window.setpos(y, 0)
          window.addstr('│')
          window.setpos(y, width - 1)
          window.addstr('│')
        end

        window.setpos(height - 1, 0)
        window.addstr("╰#{h_line}╯")
      else
        # Fallback to standard box drawing for system ncurses
        window.box(0, 0)
      end
    end

    def initialize(maxy: nil, maxx: nil, begy: nil, begx: nil, window: nil)
      super window || Curses.stdscr.subwin(maxy, maxx, begy, begx)
    end

    def writeln(row, str)
      setpos row, 0
      clrtoeol
      self << str
      refresh
    end
  end

  class HeaderLeftWindow < Window
    def initialize
      super maxy: 3, maxx: Curses.cols - 32, begy: 1, begx: 1
    end

    def draw_path_and_page_number(path: nil, current: 1, total: nil)
      writeln 0, %Q[Page: #{"#{current}/ #{total}".ljust(11)}  Path: #{path}]
      noutrefresh
    end

    def draw_current_file_info(current_file)
      draw_current_filename current_file.full_display_name
      draw_stat current_file
      noutrefresh
    end

    private
    def draw_current_filename(current_file_name)
      writeln 1, "File: #{current_file_name}"
    end

    def draw_stat(item)
      writeln 2, "      #{item.size_or_dir.ljust(13)}#{item.mtime} #{item.mode}"
    end
  end

  class HeaderRightWindow < Window
    def initialize
      super maxy: 2, maxx: 29, begy: 2, begx: Curses.cols - 30
    end

    def draw_marked_items(count: 0, size: 0)
      writeln 0, %Q[#{"#{count}Marked".rjust(11)} #{size.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse.rjust(16)}]
      noutrefresh
    end

    def draw_total_items(count: 0, size: 0)
      writeln 1, %Q[#{"#{count}Files".rjust(10)} #{size.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse.rjust(17)}]
      noutrefresh
    end
  end

  class DebugWindow < Window
    def initialize
      super maxy: 1, maxx: 29, begy: 1, begx: Curses.cols - 30
    end

    def debug(s)
      writeln 0, s.to_s
      noutrefresh
    end
  end

  class MainWindow < Window
    attr_reader :current_index, :begy
    attr_writer :number_of_panes

    def initialize
      @begy, @current_index, @number_of_panes = 5, 0, 2
      super window: Curses::Pad.new(Curses.lines - 7, Curses.cols - 2)
    end

    def newpad(items)
      clear
      columns = items.size / maxy + 1
      newx = width * (((columns - 1) / @number_of_panes + 1) * @number_of_panes)
      resize maxy, newx if newx != maxx

      draw_items_to_each_pane items
    end

    def display(page)
      noutrefresh 0, (Curses.cols - 2) * page, begy, 1, begy + maxy - 1, Curses.cols - 2
    end

    def activate_pane(num)
      @current_index = num
    end

    def pane_index_at(y: nil, x: nil)
      (y >= begy) && (begy + maxy > y) && (x / width)
    end

    def width
      (Curses.cols - 2) / @number_of_panes
    end

    def max_items
      maxy * @number_of_panes
    end

    def draw_item(item, current: false)
      setpos item.index % maxy, width * @current_index
      attron(Curses.color_pair(item.color) | (current ? Curses::A_UNDERLINE : Curses::A_NORMAL)) do
        self << item.to_s
      end
    end

    def draw_items_to_each_pane(items)
      items.each_slice(maxy).each.with_index do |arr, col_index|
        arr.each.with_index do |item, i|
          setpos i, width * col_index
          attron(Curses.color_pair(item.color) | Curses::A_NORMAL) { self << item.to_s }
        end
      end
    end

    def toggle_mark(item)
      item.toggle_mark
    end
  end

  class CommandLineWindow < Window
    def initialize
      super maxy: 1, maxx: Curses.cols, begy: Curses.lines - 1, begx: 0
    end

    def set_prompt(str)
      attron(Curses.color_pair(Curses::COLOR_WHITE) | Curses::A_BOLD) do
        writeln 0, str
      end
    end

    def get_command(prompt: nil, default: nil)
      startx = prompt ? prompt.size : 1
      setpos 0, startx
      # Passing the default string to Reline
      Reline.pre_input_hook = -> {
        Reline.insert_text default || ''
      }
      s = Reline.readline prompt, true
      Rfd.logger.info "reline: #{s}"
      "#{prompt[1..-1] if prompt}#{s.strip}"
    end

    def show_error(str)
      attron(Curses.color_pair(Curses::COLOR_RED) | Curses::A_BOLD) do
        writeln 0, str
      end
      noutrefresh
    end
  end
end
