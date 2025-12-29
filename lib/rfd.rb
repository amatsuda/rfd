# frozen_string_literal: true
require 'curses'
require 'fileutils'
require 'time'
require 'tmpdir'
require 'rubygems/package'
require 'zip'
require 'zip/filesystem'
require 'reline'
require_relative 'rfd/commands'
require_relative 'rfd/item'
require_relative 'rfd/windows'
require_relative 'rfd/logging'
require_relative 'rfd/reline_ext'

module Rfd
  VERSION = Gem.loaded_specs['rfd'] ? Gem.loaded_specs['rfd'].version.to_s : '0'

  # :nodoc:
  def self.init_curses
    # Set locale for proper wide character support
    ENV['LC_ALL'] ||= 'en_US.UTF-8'

    Curses.init_screen
    Curses.raw
    Curses.noecho
    Curses.curs_set 0
    Curses.stdscr.keypad = true
    print "\e[?25l"  # Hide cursor via ANSI escape sequence
    Curses.start_color

    [Curses::COLOR_WHITE, Curses::COLOR_CYAN, Curses::COLOR_MAGENTA, Curses::COLOR_GREEN, Curses::COLOR_RED].each do |c|
      Curses.init_pair c, c, Curses::COLOR_BLACK
    end

    Curses.mousemask Curses::BUTTON1_CLICKED | Curses::BUTTON1_DOUBLE_CLICKED

    # Enable extended key codes for better Unicode support
    Curses.stdscr.keypad = true
  end

  # Start the app here!
  #
  # ==== Parameters
  # * +dir+ - The initial directory.
  def self.start(dir = '.', log: nil)
    Rfd.log_to log if log

    init_curses
    Rfd::Window.draw_borders
    Curses.stdscr.noutrefresh
    rfd = Rfd::Controller.new
    rfd.cd dir
    rfd.preview  # Show preview by default
    Curses.doupdate
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
      @debug = DebugWindow.new if ENV['DEBUG']
      @direction, @dir_history, @last_command, @times, @yanked_items, @preview_window = nil, [], nil, nil, nil, nil
    end

    # The main loop.
    def run
      loop do
        begin
          number_pressed = false
          ret = case (c = Curses.getch)
          when 10, 13  # enter, return
            enter
          when 27  # ESC
            q
          when ' '  # space
            space
          when 127, Curses::KEY_BACKSPACE, Curses::KEY_DC  # DEL, Backspace, Delete
            del
          when Curses::KEY_DOWN
            j
          when Curses::KEY_UP
            k
          when Curses::KEY_LEFT
            h
          when Curses::KEY_RIGHT
            l
          when Curses::KEY_NPAGE  # Page Down
            ctrl_n
          when Curses::KEY_PPAGE  # Page Up
            ctrl_p
          when Curses::KEY_HOME
            g
          when Curses::KEY_END
            G
          when Curses::KEY_CTRL_A..Curses::KEY_CTRL_Z
            chr = ((c - 1 + 65) ^ 0b0100000).chr
            public_send "ctrl_#{chr}" if respond_to?("ctrl_#{chr}")
          when ?0..?9
            public_send c
            number_pressed = true
          when ?!..?~
            if respond_to? c
              public_send c
            else
              debug "key: #{c}" if ENV['DEBUG']
            end
          when Curses::KEY_MOUSE
            if (mouse_event = Curses.getmouse)
              case mouse_event.bstate
              when Curses::BUTTON1_CLICKED
                click y: mouse_event.y, x: mouse_event.x
              when Curses::BUTTON1_DOUBLE_CLICKED
                double_click y: mouse_event.y, x: mouse_event.x
              end
            end
          else
            debug "key: #{c}" if ENV['DEBUG']
          end
          Curses.doupdate if ret
          @times = nil unless number_pressed
        rescue StopIteration
          raise
        rescue => e
          Rfd.logger.error e if Rfd.logger
          command_line.show_error e.to_s
          raise if ENV['DEBUG']
        end
      end
    ensure
      print "\e[?25h"  # Restore cursor
      Curses.close_screen
    end

    # Change the number of columns in the main window.
    def spawn_panes(num)
      main.number_of_panes = num
      @current_row = @current_page = 0
    end

    # Number of times to repeat the next command.
    def times
      (@times || 1).to_i
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
        if (prev_item = items[current_row])
          main.draw_item prev_item
        end
        page = row / max_items
        switch_page page if page != current_page
        main.activate_pane row / maxy
        @current_row = row
      else
        @current_row = items.size > 2 ? 2 : 0
      end

      item = items[current_row]
      main.draw_item item, current: true
      main.display current_page

      header_l.draw_current_file_info item
      update_preview if @preview_window
      @current_row
    end

    # Change the current directory.
    def cd(dir = '~', pushd: true)
      dir = load_item path: expand_path(dir) unless dir.is_a? Item
      unless dir.zip?
        Dir.chdir dir
        @current_zip = nil
      else
        @current_zip = dir
      end
      if current_dir && pushd
        @dir_history << current_dir
        @dir_history.shift if @dir_history.size > 100
      end
      @current_dir, @current_page, @current_row = dir, 0, nil
      main.activate_pane 0
      ls
      @current_dir
    rescue Errno::EACCES, Errno::ENOENT => e
      command_line.show_error e.message
      nil
    end

    # cd to the previous directory.
    def popd
      cd @dir_history.pop, pushd: false if @dir_history.any?
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
      true
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
      draw_items
      switch_page 0
      move_cursor
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
          load_item dir: current_dir, name: fn
        }.to_a.partition {|i| %w(. ..).include? i.name}.flatten
      else
        @items = [load_item(dir: current_dir, name: '.', stat: File.stat(current_dir)),
          load_item(dir: current_dir, name: '..', stat: File.stat(File.dirname(current_dir)))]
        Zip::File.open(current_dir) do |zf|
          zf.each do |entry|
            next if entry.name_is_directory?
            stat = zf.file.stat entry.name
            @items << load_item(dir: current_dir, name: entry.name, stat: stat)
          end
        end
      end
    rescue Errno::EACCES => e
      command_line.show_error e.message
      @items ||= []
    rescue Zip::Error => e
      command_line.show_error "ZIP error: #{e.message}"
    end

    # Focus at the first file or directory of which name starts with the given String.
    def find(str)
      index = items.index {|i| i.index > current_row && i.name.start_with?(str)} || items.index {|i| i.name.start_with? str}
      move_cursor index if index
    end

    # Focus at the last file or directory of which name starts with the given String.
    def find_reverse(str)
      index = items.reverse.index {|i| i.index < current_row && i.name.start_with?(str)} || items.reverse.index {|i| i.name.start_with? str}
      move_cursor items.size - index - 1 if index
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
      main.newpad items
      @displayed_items = items[current_page * max_items, max_items]
      main.display current_page
      header_l.draw_path_and_page_number path: current_dir.path, current: current_page + 1, total: total_pages
    end

    SORT_KEYS = {
      's' => :size, 'S' => :size,
      't' => :mtime, 'c' => :ctime, 'u' => :atime, 'e' => :extname
    }.freeze

    # Sort the loaded files and directories in already given sort order.
    def sort_items_according_to_current_direction
      dots = items.shift(2)
      reverse = @direction&.end_with?('r')
      key = SORT_KEYS[@direction&.sub(/r$/, '')]

      sorted = items.partition(&:directory?).flat_map do |arr|
        if key
          sorted_arr = arr.sort_by(&key)
          reverse ? sorted_arr : sorted_arr.reverse
        else
          reverse ? arr.sort.reverse : arr.sort
        end
      end

      @items = dots + sorted
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
      draw_items
      draw_total_items
      move_cursor
    rescue RegexpError => e
      command_line.show_error "Invalid regex: #{e.message}"
      switch_page 0
      move_cursor
    end

    # Copy selected files and directories to the destination.
    def cp(dest)
      unless in_zip?
        src = (m = marked_items).any? ? m.map(&:path) : current_item
        FileUtils.cp_r src, expand_path(dest)
      else
        raise 'cping multiple items in .zip is not supported.' if selected_items.size > 1
        Zip::File.open(current_zip) do |zip|
          entry = zip.find_entry(selected_items.first.name).dup
          entry.name, entry.name_length = dest, dest.size
          zip.instance_variable_get(:@entry_set) << entry
        end
      end
      ls
    end

    # Move selected files and directories to the destination.
    def mv(dest)
      unless in_zip?
        src = (m = marked_items).any? ? m.map(&:path) : current_item
        FileUtils.mv src, expand_path(dest)
      else
        raise 'mving multiple items in .zip is not supported.' if selected_items.size > 1
        rename "#{selected_items.first.name}/#{dest}"
      end
      ls
    end

    # Rename selected files and directories.
    #
    # ==== Parameters
    # * +pattern+ - new filename, or a shash separated Regexp like string
    def rename(pattern)
      from, to = pattern.sub(/^\//, '').sub(/\/$/, '').split '/'
      if to.nil?
        from, to = current_item.name, from
      else
        from = Regexp.new from
      end
      unless in_zip?
        selected_items.each do |item|
          name = item.name.gsub from, to
          FileUtils.mv item, current_dir.join(name) if item.name != name
        end
      else
        Zip::File.open(current_zip) do |zip|
          selected_items.each do |item|
            name = item.name.gsub from, to
            zip.rename item.name, name
          end
        end
      end
      ls
    rescue RegexpError => e
      command_line.show_error "Invalid regex: #{e.message}"
    end

    # Soft delete selected files and directories.
    #
    # If the OS is not OSX, performs the same as `delete` command.
    def trash
      unless in_zip?
        if osx?
          FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
        else
          #TODO support other OS
          FileUtils.rm_rf selected_items.map(&:path)
        end
      else
        return unless ask %Q[Trashing zip entries is not supported. Actually the files will be deleted. Are you sure want to proceed? (y/n)]
        delete
      end
      @current_row -= selected_items.count {|i| i.index <= current_row}
      ls
    end

    # Delete selected files and directories.
    def delete
      unless in_zip?
        FileUtils.rm_rf selected_items.map(&:path)
      else
        Zip::File.open(current_zip) do |zip|
          zip.select {|e| selected_items.map(&:name).include? e.to_s}.each do |entry|
            if entry.name_is_directory?
              zip.dir.delete entry.to_s
            else
              zip.file.delete entry.to_s
            end
          end
        end
      end
      @current_row -= selected_items.count {|i| i.index <= current_row}
      ls
    end

    # Create a new directory.
    def mkdir(dir)
      unless in_zip?
        FileUtils.mkdir_p current_dir.join(dir)
      else
        Zip::File.open(current_zip) do |zip|
          zip.dir.mkdir dir
        end
      end
      ls
    end

    # Create a new empty file.
    def touch(filename)
      unless in_zip?
        FileUtils.touch current_dir.join(filename)
      else
        Zip::File.open(current_zip) do |zip|
          # zip.file.open(filename, 'w') {|_f| }  #HAXX this code creates an unneeded temporary file
          zip.instance_variable_get(:@entry_set) << Zip::Entry.new(current_zip, filename)
        end
      end

      ls
      move_cursor items.index {|i| i.name == filename}
    end

    # Create a symlink to the current file or directory.
    def symlink(name)
      FileUtils.ln_s current_item, name
      ls
    end

    # Change the timestamp of the selected files and directories.
    #
    # ==== Parameters
    # * +timestamp+ - A string that can be parsed with `Time.parse`. Note that this parameter is not compatible with UNIX `touch -t`.
    def touch_t(timestamp)
      FileUtils.touch selected_items, mtime: Time.parse(timestamp)
      ls
    end

    # Yank selected file / directory names.
    def yank
      @yanked_items = selected_items
    end

    # Paste yanked files / directories here.
    def paste
      if @yanked_items
        if current_item.directory?
          FileUtils.cp_r @yanked_items.map(&:path), current_item
        else
          @yanked_items.each do |item|
            if items.include? item
              i = 0
              while i += 1
                new_path = current_dir.join("#{item.basename}_#{i}#{item.extname}")
                break unless File.exist? new_path
              end
              new_item = new_path
              FileUtils.cp_r item, new_item
            else
              FileUtils.cp_r item, current_dir
            end
          end
        end
        ls
      end
    end

    # Copy selected files and directories' path into clipboard on OSX.
    def clipboard
      IO.popen('pbcopy', 'w') {|f| f << selected_items.map(&:path).join(' ')} if osx?
    end

    # Archive selected files and directories into a .zip file.
    def zip(zipfile_name)
      return unless zipfile_name
      zipfile_name += '.zip' unless zipfile_name.end_with? '.zip'

      Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
        selected_items.each do |item|
          next if item.symlink?
          if item.directory?
            Dir[item.join('**/**')].each do |file|
              zipfile.add file.sub("#{current_dir}/", ''), file
            end
          else
            zipfile.add item.name, item
          end
        end
      end
      ls
    end

    # Unarchive .zip and .tar.gz files within selected files and directories into current_directory.
    def unarchive
      unless in_zip?
        zips, gzs = selected_items.partition(&:zip?).tap {|z, others| break [z, *others.partition(&:gz?)]}
        zips.each do |item|
          dest_dir = current_dir.join(item.basename)
          FileUtils.mkdir_p dest_dir
          Zip::File.open(item) do |zip|
            zip.each do |entry|
              dest_path = safe_extract_path(dest_dir, entry.to_s)
              FileUtils.mkdir_p File.dirname(dest_path)
              zip.extract(entry, dest_path) { true }
            end
          end
        end
        gzs.each do |item|
          Zlib::GzipReader.open(item) do |gz|
            Gem::Package::TarReader.new(gz) do |tar|
              dest_dir = current_dir.join (gz.orig_name || item.basename).sub(/\.tar$/, '')
              tar.each do |entry|
                dest = nil
                if entry.full_name == '././@LongLink'
                  dest = safe_extract_path(dest_dir, entry.read.strip)
                  next
                end
                dest ||= safe_extract_path(dest_dir, entry.full_name)
                if entry.directory?
                  FileUtils.mkdir_p dest, mode: entry.header.mode
                elsif entry.file?
                  FileUtils.mkdir_p File.dirname(dest)
                  File.open(dest, 'wb') {|f| f.print entry.read}
                  FileUtils.chmod entry.header.mode, dest
                elsif entry.header.typeflag == '2'  # symlink
                  File.symlink entry.header.linkname, dest
                end
                unless Dir.exist? dest_dir
                  FileUtils.mkdir_p dest_dir
                  File.open(File.join(dest_dir, gz.orig_name || item.basename), 'wb') {|f| f.print gz.read}
                end
              end
            end
          end
        end
      else
        dest_dir = File.join(current_zip.dir, current_zip.basename)
        Zip::File.open(current_zip) do |zip|
          zip.select {|e| selected_items.map(&:name).include? e.to_s}.each do |entry|
            dest_path = safe_extract_path(dest_dir, entry.to_s)
            FileUtils.mkdir_p File.dirname(dest_path)
            zip.extract(entry, dest_path) { true }
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
      (items.size - 1) / max_items + 1
    end

    # Move to the given page number.
    #
    # ==== Parameters
    # * +page+ - Target page number
    def switch_page(page)
      main.display (@current_page = page)
      @displayed_items = items[current_page * max_items, max_items]
      header_l.draw_path_and_page_number path: current_dir.path, current: current_page + 1, total: total_pages
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

    # Swktch on / off marking on the current file or directory.
    def toggle_mark
      main.toggle_mark current_item
    end

    # Get a char as a String from user input.
    def get_char
      c = Curses.getch
      c if (0..255) === c.ord
    end

    def clear_command_line
      command_line.writeln 0, ""
      command_line.clear
      command_line.noutrefresh
      print "\e[?25l"  # Hide cursor
    end

    # Accept user input, and directly execute it as a Ruby method call to the controller.
    #
    # ==== Parameters
    # * +preset_command+ - A command that would be displayed at the command line before user input.
    # * +default_argument+ - A default argument for the command.
    def process_command_line(preset_command: nil, default_argument: nil)
      prompt = preset_command ? ":#{preset_command} " : ':'
      command_line.set_prompt prompt
      cmd, *args = command_line.get_command(prompt: prompt, default: default_argument).split(' ')
      if cmd && !cmd.empty?
        ret = self.public_send cmd, *args
        clear_command_line
        ret
      end
    rescue Interrupt, Rfd::CommandCancelled
      clear_command_line
    end

    # Accept user input, and directly execute it in an external shell.
    def process_shell_command
      command_line.set_prompt ':!'
      cmd = command_line.get_command(prompt: ':!')[1..-1]
      execute_external_command pause: true do
        system cmd
      end
    rescue Interrupt, Rfd::CommandCancelled
    ensure
      command_line.clear
      command_line.noutrefresh
    end

    # Let the user answer y or n.
    #
    # ==== Parameters
    # * +prompt+ - Prompt message
    def ask(prompt = '(y/n)')
      command_line.set_prompt prompt
      command_line.refresh
      while (c = Curses.getch)
        next unless [?N, ?Y, ?n, ?y, 3, 27] .include? c  # N, Y, n, y, ^c, esc
        clear_command_line
        break (c == 'y') || (c == 'Y')
      end
    end

    # Open current file or directory with the editor.
    def edit
      execute_external_command do
        editor = ENV['EDITOR'] || 'vim'
        unless in_zip?
          system editor, current_item.path
        else
          begin
            tmpdir, tmpfile_name = nil
            Zip::File.open(current_zip) do |zip|
              tmpdir = Dir.mktmpdir
              FileUtils.mkdir_p File.join(tmpdir, File.dirname(current_item.name))
              tmpfile_name = File.join(tmpdir, current_item.name)
              File.open(tmpfile_name, 'w') {|f| f.puts zip.file.read(current_item.name)}
              system editor, tmpfile_name
              zip.add(current_item.name, tmpfile_name) { true }
            end
            ls
          ensure
            FileUtils.remove_entry_secure tmpdir if tmpdir
          end
        end
      end
    end

    # Open current file or directory with the viewer.
    def view
      pager = ENV['PAGER'] || 'less'
      execute_external_command do
        unless in_zip?
          system pager, current_item.path
        else
          begin
            tmpdir, tmpfile_name = nil
            Zip::File.open(current_zip) do |zip|
              tmpdir = Dir.mktmpdir
              FileUtils.mkdir_p File.join(tmpdir, File.dirname(current_item.name))
              tmpfile_name = File.join(tmpdir, current_item.name)
              File.open(tmpfile_name, 'w') {|f| f.puts zip.file.read(current_item.name)}
            end
            system pager, tmpfile_name
          ensure
            FileUtils.remove_entry_secure tmpdir if tmpdir
          end
        end
      end
    end

    def view_image
      return view unless current_item.image?
      if kitty?
        # Display image fullscreen using Kitty graphics
        img_w, img_h = Curses.cols - 2, Curses.lines - 6
        img_x, img_y = 1, 5
        system 'kitty', '+kitten', 'icat', '--clear', '--place', "#{img_w}x#{img_h}@#{img_x}x#{img_y}", current_item.path, out: '/dev/tty', err: '/dev/null'
        Curses.getch
        print "\e_Ga=d,d=C\e\\"  # Clear Kitty graphics
        move_cursor current_row
      elsif sixel?
        # Display image using sixel at cursor position
        print "\e[6;1H"  # Move cursor to row 6, col 1
        # img2sixel with width constraint (pixels = cols * ~10)
        system('img2sixel', '-w', ((Curses.cols - 2) * 10).to_s, current_item.path, out: '/dev/tty', err: '/dev/null') ||
          system('chafa', '-f', 'sixel', '-s', "#{Curses.cols - 2}x#{Curses.lines - 6}", current_item.path, out: '/dev/tty', err: '/dev/null')
        Curses.getch
        move_cursor current_row
      elsif osx?
        system 'open', current_item.path
      end
    end

    def preview
      if @preview_window
        @preview_window.close
        @preview_window = nil
        move_cursor current_row
      else
        popup_h = main.maxy
        popup_w = main.width
        popup_y = main.begy
        popup_x = preview_pane_x
        @preview_window = Curses::Window.new(popup_h, popup_w, popup_y, popup_x)
        update_preview
      end
    end

    def preview_pane_x
      # Preview goes in the next pane (to the right of cursor, wrapping around)
      visible_pane = main.current_index % main.number_of_panes
      next_pane = (visible_pane + 1) % main.number_of_panes
      next_pane * main.width + 1
    end

    def update_preview
      return unless @preview_window
      # Reposition preview window if cursor pane changed
      expected_x = preview_pane_x
      if @preview_window.begx != expected_x
        @preview_window.close
        @preview_window = Curses::Window.new(main.maxy, main.width, main.begy, expected_x)
        main.display current_page  # Redraw main window where old preview was
      end
      w = @preview_window
      max_width = w.maxx - 2
      w.clear
      w.bkgdset Curses.color_pair(Curses::COLOR_CYAN)
      Rfd::Window.draw_ncursesw_border(w, w.maxy, w.maxx)
      w.setpos(0, 2)
      w.addstr(" #{current_item.name} "[0, w.maxx - 4])

      w.bkgdset Curses.color_pair(Curses::COLOR_WHITE)
      if current_item.directory?
        entries = Dir.children(current_item.path).sort.first(w.maxy - 2) rescue []
        entries.each_with_index do |name, i|
          w.setpos(i + 1, 1)
          w.addstr(name[0, max_width].ljust(max_width))
        end
      elsif current_item.image?
        w.refresh
        if kitty?
          # Clear any previous image in this area
          print "\e_Ga=d,d=C\e\\"
          # Display image using Kitty graphics protocol with --place
          img_w, img_h = max_width, w.maxy - 2
          img_x, img_y = w.begx + 1, w.begy + 1
          system 'kitty', '+kitten', 'icat', '--clear', '--place', "#{img_w}x#{img_h}@#{img_x}x#{img_y}", current_item.path, out: '/dev/tty', err: '/dev/null'
        else
          w.setpos(w.maxy / 2, 1)
          w.addstr('[Image file]'.center(max_width))
        end
      else
        lines = File.readlines(current_item.path, encoding: 'UTF-8', invalid: :replace, undef: :replace).first(w.maxy - 2) rescue nil
        if lines
          lines.each_with_index do |line, i|
            w.setpos(i + 1, 1)
            display_line = +''
            display_width = 0
            line.chomp.each_char do |c|
              char_width = c.bytesize == 1 ? 1 : 2
              break if display_width + char_width > max_width
              display_line << c
              display_width += char_width
            end
            w.addstr(display_line << ' ' * (max_width - display_width))
          end
        else
          w.setpos(w.maxy / 2, 1)
          w.addstr('[Binary file]'.center(max_width))
        end
      end
      w.refresh
    end

    def move_cursor_by_click(y: nil, x: nil)
      if (idx = main.pane_index_at(y: y, x: x))
        row = current_page * max_items + main.maxy * idx + y - main.begy
        move_cursor row if (row >= 0) && (row < items.size)
      end
    end

    private
    def execute_external_command(pause: false)
      Curses.def_prog_mode
      Curses.close_screen
      yield
    ensure
      Curses.reset_prog_mode
      Curses.getch if pause
      #NOTE needs to draw borders and ls again here since the stdlib Curses.refresh fails to retrieve the previous screen
      Rfd::Window.draw_borders
      Curses.refresh
      ls
    end

    def expand_path(path)
      File.expand_path path.start_with?('/', '~') ? path : current_dir ? current_dir.join(path) : path
    end

    # Safely resolve an archive entry path within a destination directory.
    # Prevents path traversal attacks (e.g., ../../etc/passwd).
    def safe_extract_path(dest_dir, entry_name)
      dest_dir = File.expand_path(dest_dir)
      dest_path = File.expand_path(File.join(dest_dir, entry_name))
      raise "Path traversal detected: #{entry_name}" unless dest_path.start_with?(dest_dir + '/')
      dest_path
    end

    def load_item(path: nil, dir: nil, name: nil, stat: nil)
      Item.new dir: dir || File.dirname(path), name: name || File.basename(path), stat: stat, window_width: main.width
    end

    def osx?
      @_osx ||= RbConfig::CONFIG['host_os'] =~ /darwin/
    end

    def kitty?
      return @_kitty if defined?(@_kitty)
      @_kitty = (ENV['TERM'] == 'xterm-kitty') || (ENV['KITTY_WINDOW_ID']) || (ENV['TERM_PROGRAM'] == 'ghostty')
    end

    def sixel?
      return @_sixel if defined?(@_sixel)
      @_sixel = (ENV['TERM_PROGRAM'] == 'iTerm.app') || ENV['TERM']&.include?('mlterm') || (ENV['TERM'] == 'foot')
    end

    def in_zip?
      @current_zip
    end

    def debug(str)
      @debug.debug str
    end
  end
end
