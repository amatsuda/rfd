require 'fileutils'
require_relative 'rfd/commands'
require_relative 'rfd/item'

module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  def self.start(dir = '.')
    FFI::NCurses.init_pair FFI::NCurses::COLOR_WHITE, FFI::NCurses::COLOR_WHITE, FFI::NCurses::COLOR_BLACK
    FFI::NCurses.init_pair FFI::NCurses::COLOR_CYAN, FFI::NCurses::COLOR_CYAN, FFI::NCurses::COLOR_BLACK
    FFI::NCurses.init_pair FFI::NCurses::COLOR_MAGENTA, FFI::NCurses::COLOR_MAGENTA, FFI::NCurses::COLOR_BLACK
    FFI::NCurses.init_pair FFI::NCurses::COLOR_GREEN, FFI::NCurses::COLOR_GREEN, FFI::NCurses::COLOR_BLACK
    FFI::NCurses.init_pair FFI::NCurses::COLOR_RED, FFI::NCurses::COLOR_RED, FFI::NCurses::COLOR_BLACK

    Rfd::MainWindow.new dir
  end

  class Window
    def draw(contents)
      FFI::NCurses.mvwaddstr @window, 0, 0, contents
    end

    def wmove(y, x)
      FFI::NCurses.wmove @window, y, x
    end

    def wclear
      FFI::NCurses.wclear @window
    end

    def wrefresh
      FFI::NCurses.wrefresh @window
    end

    def maxx
      return @maxx if @maxx
      @maxy, @maxx = FFI::NCurses.getmaxyx @window
      @maxx
    end

    def maxy
      return @maxy if @maxy
      @maxy, @maxx = FFI::NCurses.getmaxyx @window
      @maxy
    end

    def begx
      return @begx if @begx
      @begy, @begx = FFI::NCurses.getbegyx @window
      @begx
    end

    def begy
      return @begy if @begy
      @begy, @begx = FFI::NCurses.getbegyx @window
      @begy
    end
  end

  # bordered Window
  class SubWindow < Window
    def initialize(*)
      border_window = FFI::NCurses.derwin FFI::NCurses.stdscr, maxy + 2, maxx + 2, begy - 1, begx - 1
      FFI::NCurses.box border_window, 0, 0
    end
  end

  class BaseWindow < Window
    attr_reader :main

    def initialize(main)
      @window = FFI::NCurses.stdscr
      @main = main
    end
  end

  class HeaderLeftWindow < SubWindow
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 3, base.maxx - 32, 1, 1
      super
    end

    def draw_path_and_page_number(path: nil, current: 1, total: nil)
      @path_and_page_number = %Q[Page: #{"#{current}/ #{total}".ljust(11)}  Path: #{path}]
      wmove 0, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @path_and_page_number
    end

    def draw_current_file_info(current_file)
      draw_current_filename current_file.full_display_name
      draw_stat current_file
    end

    def draw_current_filename(current_file_name)
      @current_file_name = "File: #{current_file_name}"
      wmove 1, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @current_file_name
    end

    def draw_stat(item)
      @stat = "      #{item.size_or_dir.ljust(13)}#{item.mtime} #{item.mode}"
      wmove 2, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, @stat
    end
  end

  class HeaderRightWindow < SubWindow
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 3, 29, 1, base.maxx - 30
      super
    end

    def draw_marked_items(count: 0, size: 0)
      wmove 1, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, %Q[#{"#{count}Marked".rjust(11)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(16)}]
    end

    def draw_total_items(count: 0, size: 0)
      wmove 2, 0
      FFI::NCurses.wclrtoeol @window
      FFI::NCurses.waddstr @window, %Q[#{"#{count}Files".rjust(10)} #{size.to_s.reverse.gsub( /(\d{3})(?=\d)/, '\1,').reverse.rjust(17)}]
    end

    def debug(s)
      FFI::NCurses.mvwaddstr @window, 0, 0, s.to_s
    end
  end

  class MainWindow < SubWindow
    include Rfd::Commands

    attr_reader :header_l, :header_r, :command_line, :base

    def initialize(dir = '.')
      @base = base = BaseWindow.new self

      @header_l = HeaderLeftWindow.new base: base
      @header_r = HeaderRightWindow.new base: base
      @command_line = CommandLineWindow.new base: base

      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, base.maxy - 7, base.maxx - 2, 5, 1
      @row = 0
      super

      cd dir
      ls
    end

    def run
      loop do
        case (c = FFI::NCurses.getch)
        when 10  # enter
          enter
        when 27  # esc
          q
        when 32  # space
          space
        when 127  # DEL
          del
        when FFI::NCurses::KEY_CTRL_A..FFI::NCurses::KEY_CTRL_Z
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
        page = row / maxy
        if page != @current_page
          switch_page page
          @row = row
        else
          prev, @row = @row, row
        end
      end

      @row ||= 0

      if prev && (item = @items[prev])
        FFI::NCurses.wattr_set @window, FFI::NCurses::A_NORMAL, item.color, nil
        FFI::NCurses.mvwaddstr @window, prev % maxy, 0, "#{item.to_s}\n"
      end
      item = @items[row || @row]
      FFI::NCurses.wattr_set @window, FFI::NCurses::A_UNDERLINE, item.color, nil
      FFI::NCurses.mvwaddstr @window, @row % maxy, 0, "#{item.to_s}\n"
      FFI::NCurses.wstandend @window
      wrefresh

      header_l.draw_current_file_info item
      header_l.wrefresh
    end

    def close_viewer
      @viewer.close
      ls
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

      wclear
      draw_items
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
      @items = Dir.foreach(@dir).map {|fn| Item.new dir: @dir, name: fn}.to_a
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
      wmove 0, 0
      @displayed_items = @items[@current_page * maxy, maxy]
      @displayed_items.each do |item|
        FFI::NCurses.wattr_set @window, FFI::NCurses::A_NORMAL, item.color, nil
        FFI::NCurses.waddstr @window, "#{item.to_s}\n"
      end
      FFI::NCurses.wstandend @window
      wrefresh

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
      @items.length / maxy + 1
    end

    def switch_page(page)
      @current_page = page
      wclear
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
      FFI::NCurses.mvwaddstr @window, @row % maxy, 0, current_item.toggle_mark
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
      FFI::NCurses.wstandend @window
    end

    def view
      FFI::NCurses.def_prog_mode
      FFI::NCurses.endwin
      pager = ENV['PAGER'] || 'less'
      system "#{pager} #{current_item.path}"
      FFI::NCurses.reset_prog_mode
      FFI::NCurses.refresh
    end

    def debug(str)
      header_r.wclear
      header_r.debug str
    end
  end

  class ViewerWindow < SubWindow
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, base.maxy - 10, base.maxx - 2, 8, 1
      super
    end

    def close
      wclear
    end
  end

  class CommandLineWindow < Window
    def initialize(base: nil)
      @window = FFI::NCurses.derwin FFI::NCurses.stdscr, 1, base.maxx, base.maxy - 1, 0
    end

    def set_prompt(str)
      FFI::NCurses.wattr_set @window, FFI::NCurses::A_BOLD, FFI::NCurses::COLOR_WHITE, nil
      FFI::NCurses.mvwaddstr @window, 0, 0, str
      FFI::NCurses.wstandend @window
    end

    def get_command(prompt: nil)
      FFI::NCurses.echo
      startx = prompt ? prompt.length : 1
      s = ' ' * 100
      FFI::NCurses.mvwgetstr @window, 0, startx, s
      "#{prompt[1..-1] if prompt}#{s.strip}"
    ensure
      FFI::NCurses.noecho
    end
  end
end
