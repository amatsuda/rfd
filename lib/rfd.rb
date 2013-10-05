require 'fileutils'
require_relative 'rfd/commands'
require_relative 'rfd/item'

module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  def self.start(dir = '.')
    [Curses::COLOR_WHITE, Curses::COLOR_CYAN, Curses::COLOR_MAGENTA, Curses::COLOR_GREEN, Curses::COLOR_RED].each do |c|
      Curses.init_pair c, c, Curses::COLOR_BLACK
    end

    Rfd::MainWindow.new dir
  end

  def self.maxx
    Curses.getmaxx Curses.stdscr
  end

  def self.maxy
    Curses.getmaxy Curses.stdscr
  end

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
  end

  # bordered Window
  class SubWindow < Window
    def initialize(*)
      border_window = subwin maxy + 2, maxx + 2, begy - 1, begx - 1
      Curses.box border_window, 0, 0
    end
  end

  class HeaderLeftWindow < SubWindow
    def initialize
      @window = subwin 3, Rfd.maxx - 32, 1, 1
      super
    end

    def draw_path_and_page_number(path: nil, current: 1, total: nil)
      @path_and_page_number = %Q[Page: #{"#{current}/ #{total}".ljust(11)}  Path: #{path}]
      wmove 0
      waddstr @path_and_page_number, clear_to_eol_before_add: true
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

  class HeaderRightWindow < SubWindow
    def initialize
      @window = subwin 3, 29, 1, Rfd.maxx - 30
      super
    end

    def draw_marked_items(count: 0, size: 0)
      wmove 1
      waddstr %Q[#{"#{count}Marked".rjust(11)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(16)}], clear_to_eol_before_add: true
    end

    def draw_total_items(count: 0, size: 0)
      wmove 2
      waddstr %Q[#{"#{count}Files".rjust(10)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(17)}], clear_to_eol_before_add: true
    end

    def debug(s)
      mvwaddstr 0, 0, s.to_s
    end
  end

  class MainWindow < Window
    include Rfd::Commands

    class Panes
      def initialize(panes)
        @panes, @current_index = panes, 0
      end

      def active
        @panes[@current_index]
      end

      def switch(index)
        @current_index = index if index < @panes.size
      end

      def size
        @panes.size
      end
    end

    attr_reader :header_l, :header_r, :command_line

    def initialize(dir = '.')
      @header_l = HeaderLeftWindow.new
      @header_r = HeaderRightWindow.new
      @command_line = CommandLineWindow.new

      @panes = spawn_panes 1
      border_window = subwin Rfd.maxy - 5, Rfd.maxx, 4, 0
      Curses.box border_window, 0, 0
      @row = 0

      cd dir
      ls
    end

    def run
      loop do
        case (c = Curses.getch)
        when 10  # enter
          enter
        when 27  # esc
          q
        when 32  # space
          space
        when 127  # DEL
          del
        when Curses::KEY_CTRL_A..Curses::KEY_CTRL_Z
          chr = ((c - 1 + 65) ^ 0b0100000).chr
          public_send "ctrl_#{chr}" if respond_to?("ctrl_#{chr}")
        else
          if respond_to? c.chr
            public_send c.chr
          else
            p c
          end
        end
      end
    end

    def spawn_panes(num)
      width = (Rfd.maxx - 2) / num
      windows = 0.upto(num - 1).inject([]) {|arr, i| arr << subwin(Rfd.maxy - 7, width - 1, 5, width * i + 1)}
      Panes.new windows
    end

    def window
      @panes.active
    end

    def max_items
      maxy * @panes.size
    end

    def current_item
      @items[@row]
    end

    def marked_items
      @items.select(&:marked?)
    end

    def selected_items
      (m = marked_items).any? ? m : Array(current_item)
    end

    def move_cursor(row = nil)
      if row
        page, item_index_in_page = row.divmod max_items
        pane_index = item_index_in_page / maxy
        if page != @current_page
          switch_page page
          @panes.switch pane_index
          @row = row
        else
          if (prev_item = @items[@row])
            Curses.wattr_set window, Curses::A_NORMAL, prev_item.color, nil
            mvwaddstr @row % maxy, 0, "#{prev_item.to_s}\n"
            wrefresh
          end
          @row = row
          @panes.switch pane_index
        end
      else
        @row = 0
      end

      item = @items[@row]
      Curses.wattr_set window, Curses::A_UNDERLINE, item.color, nil
      mvwaddstr @row % maxy, 0, "#{item.to_s}\n"
      Curses.wstandend window
      wrefresh

      header_l.draw_current_file_info item
      header_l.wrefresh
    end

    def cd(dir)
      @row = nil
      @dir = File.expand_path(dir.is_a?(Rfd::Item) ? dir.path : @dir ? File.join(@dir, dir) : dir)
    end

    def ls(page = nil)
      unless page
        fetch_items_from_filesystem
        sort_items_according_to_current_direction
      end
      @current_page = page ? page : 0

      draw_items
      @panes.switch 0
      wmove 0
      move_cursor @row

      draw_marked_items
      draw_total_items
      header_r.wrefresh
    end

    def sort(direction = nil)
      @direction, @current_page = direction, 0
      sort_items_according_to_current_direction
      switch_page 0
      move_cursor 0
    end

    def chmod(mode)
      FileUtils.chmod mode, selected_items.map(&:path)
      ls
    end

    def fetch_items_from_filesystem
      @items = Dir.foreach(@dir).map {|fn| Item.new dir: @dir, name: fn, window_width: maxx}.to_a
    end

    def find(str)
      index = @items.index {|i| i.name.start_with? str}
      move_cursor index if index
    end

    def find_reverse(str)
      index = @items.reverse.index {|i| i.name.start_with? str}
      move_cursor @items.length - index - 1 if index
    end

    def draw_items
      @displayed_items = @items[@current_page * max_items, max_items]
      0.upto(@panes.size - 1) do |index|
        @panes.switch index
        wclear
        wmove 0
        if (items = @displayed_items[maxy * index, maxy * (index + 1)])
          items.each do |item|
            Curses.wattr_set window, Curses::A_NORMAL, item.color, nil
            waddstr "#{item.to_s}\n"
          end
        end
        Curses.wstandend window
        wrefresh
      end

      draw_path_and_page_number
      header_l.wrefresh
    end

    def sort_items_according_to_current_direction
      case @direction
      when nil
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map(&:sort)
      when 'r'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort.reverse}
      when 'S', 's'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by {|i| -i.size}}
      when 'Sr', 'sr'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:size)}
      when 't'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.mtime <=> x.mtime}}
      when 'tr'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:mtime)}
      when 'c'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.ctime <=> x.ctime}}
      when 'cr'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:ctime)}
      when 'u'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.atime <=> x.atime}}
      when 'ur'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:atime)}
      when 'e'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.extname <=> x.extname}}
      when 'er'
        @items = @items.shift(2) + @items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:extname)}
      end
      @items.each.with_index {|item, index| item.index = index}
    end

    def grep(pattern)
      regexp = Regexp.new(pattern)
      fetch_items_from_filesystem
      @items = @items.shift(2) + @items.select {|i| i.name =~ regexp}
      sort_items_according_to_current_direction
      switch_page 0
      move_cursor 0

      draw_total_items
      header_r.wrefresh
    end

    def cp(dest)
      src = (m = marked_items).any? ? m.map(&:path) : current_item.path
      FileUtils.cp_r src, File.join(@dir, dest)
      ls
    end

    def mv(dest)
      src = (m = marked_items).any? ? m.map(&:path) : current_item.path
      FileUtils.mv src, File.join(@dir, dest)
      ls
    end

    def mkdir(dir)
      FileUtils.mkdir_p File.join(@dir, dir)
      ls
    end

    def touch(filename)
      FileUtils.touch File.join(@dir, filename)
      ls
    end

    def first_page?
      @current_page == 0
    end

    def last_page?
      @current_page == total_pages - 1
    end

    def total_pages
      @items.length / max_items + 1
    end

    def switch_page(page)
      @current_page = page
      draw_items
    end

    def draw_path_and_page_number
      header_l.draw_path_and_page_number path: @dir, current: @current_page + 1, total: total_pages
    end

    def draw_marked_items
      items = marked_items
      header_r.draw_marked_items count: items.size, size: items.inject(0) {|sum, i| sum += i.size}
    end

    def draw_total_items
      header_r.draw_total_items count: @items.size, size: @items.inject(0) {|sum, i| sum += i.size}
    end

    def toggle_mark
      mvwaddstr @row % maxy, 0, current_item.toggle_mark
      wrefresh
      j
    end

    def process_command_line(prompt: ':')
      command_line.set_prompt prompt
      cmd, *args = command_line.get_command(prompt: prompt).split(' ')
      if respond_to? cmd
        self.public_send cmd, *args
        command_line.wclear
        command_line.wrefresh
      end
      Curses.wstandend window
    end

    def view
      Curses.def_prog_mode
      Curses.endwin
      pager = ENV['PAGER'] || 'less'
      system "#{pager} #{current_item.path}"
      Curses.reset_prog_mode
      Curses.refresh
    end

    def debug(str)
      header_r.wclear
      header_r.debug str
    end
  end

  class CommandLineWindow < Window
    def initialize
      @window = subwin 1, Rfd.maxx, Rfd.maxy - 1, 0
    end

    def set_prompt(str)
      Curses.wattr_set window, Curses::A_BOLD, Curses::COLOR_WHITE, nil
      mvwaddstr 0, 0, str
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
  end
end
