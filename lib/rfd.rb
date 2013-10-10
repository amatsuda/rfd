require 'ffi-ncurses'
Curses = FFI::NCurses
require 'fileutils'
require 'tmpdir'
require 'zip'
require 'zip/filesystem'
require_relative 'rfd/commands'
require_relative 'rfd/item'
require_relative 'rfd/windows'

module Rfd
  VERSION = Gem.loaded_specs['rfd'].version.to_s

  # :nodoc:
  def self.init_curses
    Curses.initscr
    Curses.raw
    Curses.noecho
    Curses.curs_set 0
    Curses.keypad Curses.stdscr, true
    Curses.start_color

    [Curses::COLOR_WHITE, Curses::COLOR_CYAN, Curses::COLOR_MAGENTA, Curses::COLOR_GREEN, Curses::COLOR_RED].each do |c|
      Curses.init_pair c, c, Curses::COLOR_BLACK
    end
  end

  # Start the app here!
  #
  # ==== Parameters
  # * +dir+ - The initial directory.
  def self.start(dir = '.')
    init_curses
    rfd = Rfd::Controller.new
    rfd.cd dir
    rfd.ls
    rfd
  end

  class Controller
    include Rfd::Commands

    attr_reader :header_l, :header_r, :main, :command_line, :items, :displayed_items, :current_row, :current_page, :current_dir, :current_zip

    # :nodoc:
    def initialize
      @main = MainWindow.new
      @header_l = HeaderLeftWindow.new
      @header_r = HeaderRightWindow.new
      @command_line = CommandLineWindow.new
      @dir_history = []
    end

    # The main loop.
    def run
      loop do
        begin
          case (c = Curses.getch)
          when Curses::KEY_RETURN
            enter
          when Curses::KEY_ESCAPE
            q
          when 32  # space
            space
          when 127  # DEL
            del
          when Curses::KEY_DOWN
            j
          when Curses::KEY_UP
            k
          when Curses::KEY_LEFT
            h
          when Curses::KEY_RIGHT
            l
          when Curses::KEY_CTRL_A..Curses::KEY_CTRL_Z
            chr = ((c - 1 + 65) ^ 0b0100000).chr
            public_send "ctrl_#{chr}" if respond_to?("ctrl_#{chr}")
          when 0..255
            if respond_to? c.chr
              public_send c.chr
            else
              debug "key: #{c}" if ENV['DEBUG']
            end
          else
            debug "key: #{c}" if ENV['DEBUG']
          end
        rescue StopIteration
          raise
        rescue => e
          command_line.show_error e.to_s
          raise if ENV['DEBUG']
        end
      end
    ensure
      Curses.endwin
    end

    # Change the number of columns in the main window.
    def spawn_panes(num)
      main.spawn_panes num
      @current_row = @current_page = 0
    end

    # The file or directory on which the cursor is on.
    def current_item
      items[current_row]
    end

    # * marked files and directories.
    def marked_items
      items.select(&:marked?)
    end

    # Marked files and directories or Array(the current file or directory).
    #
    # . and .. will not be included.
    def selected_items
      ((m = marked_items).any? ? m : Array(current_item)).reject {|i| %w(. ..).include? i.name}
    end

    # Move the cursor to specified row.
    #
    # The main window and the headers will be updated reflecting the displayed files and directories.
    # The row number can be out of range of the current page.
    def move_cursor(row = nil)
      if row
        page, item_index_in_page = row.divmod max_items
        if page != current_page
          switch_page page
        else
          if (prev_item = items[current_row])
            main.draw_item prev_item
          end
        end
        main.activate_pane item_index_in_page / maxy
        @current_row = row
      else
        @current_row = 0
      end

      item = items[current_row]
      main.draw_item item, current: true

      header_l.draw_current_file_info item
      header_l.wrefresh
    end

    # Change the current directory.
    def cd(dir, pushd: true)
      if dir.is_a?(Item) && dir.zip?
        cd_into_zip dir
      else
        target = expand_path dir
        if File.readable? target
          Dir.chdir target
          @dir_history << current_dir if current_dir && pushd
          @current_dir, @current_page, @current_row, @current_zip = target, 0, nil, nil
          main.activate_pane 0
        end
      end
    end

    def cd_into_zip(zipfile)
      @current_zip = zipfile
      @dir_history << current_dir if current_dir
      @current_dir, @current_page, @current_row = zipfile.path, 0, nil
      main.activate_pane 0
    end

    # cd to the previous directory.
    def popd
      if @dir_history.any?
        cd @dir_history.pop, pushd: false
        ls
      end
    end

    # Fetch files from current directory.
    # Then update each windows reflecting the newest information.
    def ls
      fetch_items_from_filesystem_or_zip
      sort_items_according_to_current_direction

      @current_page ||= 0
      draw_items
      move_cursor (current_row ? [current_row, items.size - 1].min : nil)

      draw_marked_items
      draw_total_items
    end

    # Sort the whole files and directories in the current directory, then refresh the screen.
    #
    # ==== Parameters
    # * +direction+ - Sort order in a String.
    #                 nil   : order by name
    #                 r     : reverse order by name
    #                 s, S  : order by file size
    #                 sr, Sr: reverse order by file size
    #                 t     : order by mtime
    #                 tr    : reverse order by mtime
    #                 c     : order by ctime
    #                 cr    : reverse order by ctime
    #                 u     : order by atime
    #                 ur    : reverse order by atime
    #                 e     : order by extname
    #                 er    : reverse order by extname
    def sort(direction = nil)
      @direction, @current_page = direction, 0
      sort_items_according_to_current_direction
      switch_page 0
      move_cursor 0
    end

    # Change the file permission of the selected files and directories.
    #
    # ==== Parameters
    # * +mode+ - Unix chmod string (e.g. +w, g-r, 755, 0644)
    def chmod(mode = nil)
      return unless mode
      begin
        Integer mode
        mode = Integer mode.size == 3 ? "0#{mode}" : mode
      rescue ArgumentError
      end
      FileUtils.chmod mode, selected_items.map(&:path)
      ls
    end

    # Change the file owner of the selected files and directories.
    #
    # ==== Parameters
    # * +user_and_group+ - user name and group name separated by : (e.g. alice, nobody:nobody, :admin)
    def chown(user_and_group)
      return unless user_and_group
      user, group = user_and_group.split(':').map {|s| s == '' ? nil : s}
      FileUtils.chown user, group, selected_items.map(&:path)
      ls
    end

    # Fetch files from current directory or current .zip file.
    def fetch_items_from_filesystem_or_zip
      unless in_zip?
        @items = Dir.foreach(current_dir).map {|fn|
          stat = File.lstat File.join(current_dir, fn)
          Item.new dir: current_dir, name: fn, stat: stat, window_width: maxx
        }.to_a
      else
        @items = [Item.new(dir: current_dir, name: '.', stat: File.stat(current_dir), window_width: maxx),
          Item.new(dir: current_dir, name: '..', stat: File.stat(File.dirname(current_dir)), window_width: maxx)]
        zf = Zip::File.new current_dir
        zf.each {|entry|
          next if entry.name_is_directory?
          stat = zf.file.stat entry.name
          @items << Item.new(dir: current_dir, name: entry.name, stat: stat, window_width: maxx)
        }
      end
    end

    # Focus at the first file or directory of which name starts with the given String.
    def find(str)
      index = items.index {|i| i.name.start_with? str}
      move_cursor index if index
    end

    # Focus at the last file or directory of which name starts with the given String.
    def find_reverse(str)
      index = items.reverse.index {|i| i.name.start_with? str}
      move_cursor items.size - index - 1 if index
    end

    # Width of the currently active pane.
    def maxx
      main.maxx
    end

    # Height of the currently active pane.
    def maxy
      main.maxy
    end

    # Number of files or directories that the current main window can show in a page.
    def max_items
      main.max_items
    end

    # Update the main window with the loaded files and directories. Also update the header.
    def draw_items
      main.draw_items_to_each_pane (@displayed_items = items[current_page * max_items, max_items])
      header_l.draw_path_and_page_number path: current_dir, current: current_page + 1, total: total_pages
    end

    # Sort the loaded files and directories in already given sort order.
    def sort_items_according_to_current_direction
      case @direction
      when nil
        @items = items.shift(2) + items.partition(&:directory?).flat_map(&:sort)
      when 'r'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort.reverse}
      when 'S', 's'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort_by {|i| -i.size}}
      when 'Sr', 'sr'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:size)}
      when 't'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.mtime <=> x.mtime}}
      when 'tr'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:mtime)}
      when 'c'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.ctime <=> x.ctime}}
      when 'cr'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:ctime)}
      when 'u'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.atime <=> x.atime}}
      when 'ur'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:atime)}
      when 'e'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort {|x, y| y.extname <=> x.extname}}
      when 'er'
        @items = items.shift(2) + items.partition(&:directory?).flat_map {|arr| arr.sort_by(&:extname)}
      end
      items.each.with_index {|item, index| item.index = index}
    end

    # Search files and directories from the current directory, and update the screen.
    #
    # * +pattern+ - Search pattern against file names in Ruby Regexp string.
    #
    # === Example
    #
    # a        : Search files that contains the letter "a" in their file name
    # .*\.pdf$ : Search PDF files
    def grep(pattern = '.*')
      regexp = Regexp.new(pattern)
      fetch_items_from_filesystem_or_zip
      @items = items.shift(2) + items.select {|i| i.name =~ regexp}
      sort_items_according_to_current_direction
      switch_page 0
      move_cursor 0

      draw_total_items
    end

    # Copy selected files and directories to the destination.
    def cp(dest)
      src = (m = marked_items).any? ? m.map(&:path) : current_item.path
      FileUtils.cp_r src, expand_path(dest)
      ls
    end

    # Move selected files and directories to the destination.
    def mv(dest)
      src = (m = marked_items).any? ? m.map(&:path) : current_item.path
      FileUtils.mv src, expand_path(dest)
      ls
    end

    # Rename selected files and directories.
    #
    # ==== Parameters
    # * +pattern+ - / separated Regexp like string
    def rename(pattern)
      from, to = pattern.split '/'
      from = Regexp.new from
      selected_items.each do |item|
        name = item.name.gsub from, to
        FileUtils.mv item.path, File.join(current_dir, name)
      end
      ls
    end

    # Soft delete selected files and directories.
    #
    # If the OS is not OSX, performs the same as `delete` command.
    def trash
      if osx?
        FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
      else
        #TODO support other OS
        FileUtils.rm_rf selected_items.map(&:path)
      end
      @current_row -= selected_items.count {|i| i.index <= current_row}
      ls
    end

    # Delete selected files and directories.
    def delete
      FileUtils.rm_rf selected_items.map(&:path)
      @current_row -= selected_items.count {|i| i.index <= current_row}
      ls
    end

    # Create a new directory.
    def mkdir(dir)
      unless in_zip?
        FileUtils.mkdir_p File.join(current_dir, dir)
        ls
      else
        Zip::File.open(current_zip.path) do |zip|
          zip.dir.mkdir dir
          ls
        end
      end
    end

    # Create a new empty file.
    def touch(filename)
      unless in_zip?
        FileUtils.touch File.join(current_dir, filename)
      else
        Zip::File.open(current_zip.path) do |zip|
          zip.file.open(filename, 'w') {|_f| }
        end
      end
      ls
    end

    # Create a symlink to the current file or directory.
    def symlink(name)
      FileUtils.ln_s current_item.path, name
      ls
    end

    # Copy selected files and directories' path into clipboard on OSX.
    def clipboard
      IO.popen('pbcopy', 'w') {|f| f << selected_items.map(&:path).join(' ')} if osx?
    end

    # Archive selected files and directories into a .zip file.
    def zip(zipfile_name)
      return unless zipfile_name
      zipfile_name << '.zip' unless zipfile_name.end_with? '.zip'

      Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
        selected_items.each do |item|
          next if item.symlink?
          if item.directory?
            Dir[File.join(item.path, '**/**')].each do |file|
              zipfile.add file.sub("#{current_dir}/", ''), file
            end
          else
            zipfile.add item.name, item.path
          end
        end
      end
      ls
    end

    # Unarchive .zip files within selected files and directories into current_directory.
    def unzip
      unless in_zip?
        selected_items.select(&:zip?).each do |f|
          FileUtils.mkdir_p File.join(current_dir, f.basename)
          Zip::File.open(f.path) do |zip|
            zip.each do |entry|
              FileUtils.mkdir_p File.join(File.join(f.basename, File.dirname(entry.to_s)))
              zip.extract(entry, File.join(f.basename, entry.to_s)) { true }
            end
          end
        end
      else
        Zip::File.open(current_zip.path) do |zip|
          zip.select {|e| selected_items.map(&:name).include? e.to_s}.each do |entry|
            FileUtils.mkdir_p File.join(current_zip.dir, current_zip.basename, File.dirname(entry.to_s))
            zip.extract(entry, File.join(current_zip.dir, current_zip.basename, entry.to_s)) { true }
          end
        end
      end
      ls
    end

    # Current page is the first page?
    def first_page?
      current_page == 0
    end

    # Do we have more pages?
    def last_page?
      current_page == total_pages - 1
    end

    # Number of pages in the current directory.
    def total_pages
      items.size / max_items + 1
    end

    # Move to the given page number.
    #
    # ==== Parameters
    # * +page+ - Target page number
    def switch_page(page)
      @current_page = page
      draw_items
    end

    # Update the header information concerning currently marked files or directories.
    def draw_marked_items
      items = marked_items
      header_r.draw_marked_items count: items.size, size: items.inject(0) {|sum, i| sum += i.size}
    end

    # Update the header information concerning total files and directories in the current directory.
    def draw_total_items
      header_r.draw_total_items count: items.size, size: items.inject(0) {|sum, i| sum += i.size}
    end

    def toggle_mark
      main.toggle_mark current_item
    end

    # Accept user input, and directly execute it as a Ruby method call to the controller.
    #
    # ==== Parameters
    # * +preset_command+ - A command that would be displayed at the command line before user input.
    def process_command_line(preset_command: nil)
      prompt = preset_command ? ":#{preset_command} " : ':'
      command_line.set_prompt prompt
      cmd, *args = command_line.get_command(prompt: prompt).split(' ')
      if cmd && !cmd.empty? && respond_to?(cmd)
        self.public_send cmd, *args
        command_line.wclear
        command_line.wrefresh
      end
    rescue Interrupt
      command_line.wclear
      command_line.wrefresh
    end

    # Accept user input, and directly execute it in an external shell.
    def process_shell_command
      command_line.set_prompt ':!'
      cmd = command_line.get_command(prompt: ':!')[1..-1]
      execute_external_command pause: true do
        system cmd
      end
    rescue Interrupt
    ensure
      command_line.wclear
      command_line.wrefresh
    end

    # Let the user answer y or n.
    #
    # ==== Parameters
    # * +prompt+ - Prompt message
    def ask(prompt = '(y/n)')
      command_line.set_prompt prompt
      command_line.wrefresh
      while (c = Curses.getch)
        next unless [78, 89, 110, 121, 3, 27] .include? c  # N, Y, n, y, ^c, esc
        command_line.wclear
        command_line.wrefresh
        break [89, 121].include? c  # Y, y
      end
    end

    # Open current file or directory with the editor.
    def edit
      execute_external_command do
        editor = ENV['EDITOR'] || 'vim'
        system %Q[#{editor} "#{current_item.path}"]
      end
    end

    # Open current file or directory with the viewer.
    def view
      pager = ENV['PAGER'] || 'less'
      execute_external_command do
        unless in_zip?
          system %Q[#{pager} "#{current_item.path}"]
        else
          begin
            tmpdir, tmpfile_name = nil
            Zip::File.open(current_zip.path) do |zip|
              tmpdir = Dir.mktmpdir
              FileUtils.mkdir_p File.join(tmpdir, File.dirname(current_item.name))
              tmpfile_name = File.join(tmpdir, current_item.name)
              File.open(tmpfile_name, 'w') {|f| f.puts zip.file.read(current_item.name)}
            end
            system %Q[#{pager} "#{tmpfile_name}"]
          ensure
            FileUtils.remove_entry_secure tmpdir if tmpdir
          end
        end
      end
    end

    private
    def execute_external_command(pause: false)
      Curses.def_prog_mode
      Curses.endwin
      yield
    ensure
      Curses.reset_prog_mode
      Curses.getch if pause
      Curses.refresh
    end

    def expand_path(path)
      File.expand_path path.is_a?(Rfd::Item) ? path.path : path.start_with?('/') || path.start_with?('~') ? path : current_dir ? File.join(current_dir, path) : path
    end

    def osx?
      @_osx ||= RbConfig::CONFIG['host_os'] =~ /darwin/
    end

    def in_zip?
      @current_zip
    end

    def debug(str)
      header_r.debug str
    end
  end
end
