# frozen_string_literal: true
require 'curses'
require 'fileutils'
require 'time'
require 'tmpdir'
require 'rubygems/package'
require 'zip'
require 'zip/filesystem'
require 'reline'
require 'rouge'
require_relative 'rfd/commands'
require_relative 'rfd/item'
require_relative 'rfd/windows'
require_relative 'rfd/logging'
require_relative 'rfd/reline_ext'
require_relative 'rfd/file_ops'
require_relative 'rfd/viewer'
require_relative 'rfd/sub_window'
require_relative 'rfd/preview_window'
require_relative 'rfd/navigation_window'
require_relative 'rfd/preview/server'
require_relative 'rfd/preview/client'
require_relative 'rfd/help_generator'

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
    include Rfd::FileOps
    include Rfd::Viewer

    attr_reader :header_l, :header_r, :main, :command_line, :items, :displayed_items, :current_row, :current_page, :current_dir, :current_zip

    # :nodoc:
    def initialize
      @main = MainWindow.new
      @header_l = HeaderLeftWindow.new
      @header_r = HeaderRightWindow.new
      @command_line = CommandLineWindow.new
      @debug = DebugWindow.new if ENV['DEBUG']
      @direction, @dir_history, @last_command, @times, @yanked_items, @sub_window = nil, [], nil, nil, nil, nil
      @preview_enabled = true  # Preview is shown by default

      # Start preview server for async video preview
      start_preview_server
    end

    def preview_client
      @preview_client
    end

    def start_preview_server
      return if ENV['RFD_SKIP_PREVIEW_SERVER']

      @preview_socket_path = "/tmp/rfd_preview_#{Process.pid}.sock"
      File.unlink(@preview_socket_path) rescue nil

      # Fork the preview server process
      @preview_server_pid = fork do
        # Detach from terminal and close inherited file descriptors
        $stdin.reopen('/dev/null')
        $stdout.reopen('/dev/null')
        $stderr.reopen('/dev/null')

        $0 = 'rfd-preview-server'
        server = Preview::Server.new(@preview_socket_path)
        server.run
      end

      # In parent: wait for socket and connect client
      sleep 0.2  # Give server time to start
      @preview_client = Preview::Client.new(@preview_socket_path)
      retries = 20
      while retries > 0 && !@preview_client.connected?
        @preview_client.connect
        break if @preview_client.connected?
        sleep 0.05
        retries -= 1
      end
    rescue => e
      # If server startup fails, log and continue without async preview
      Rfd.logger&.error("Preview server startup failed: #{e.message}")
      @preview_client = nil
    end

    def stop_preview_server
      @preview_client&.close
      if @preview_server_pid
        Process.kill('TERM', @preview_server_pid) rescue nil
        Process.wait(@preview_server_pid) rescue nil
      end
      File.unlink(@preview_socket_path) rescue nil if @preview_socket_path
    end

    # The main loop.
    def run
      Curses.stdscr.timeout = 100  # Non-blocking getch with 100ms timeout
      loop do
        begin
          # Check for async preview results
          if @preview_client&.ready?
            if (result = @preview_client.poll_result)
              render_preview_result(result)
              Curses.doupdate
            end
          end

          number_pressed = false
          c = Curses.getch
          next if c.nil? || c == -1  # Timeout, continue loop

          # Let sub_window handle input first if it wants to
          if @sub_window && @sub_window.handle_input(c)
            Curses.doupdate
            next
          end

          ret = case c
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
      stop_preview_server
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
      @sub_window.render if @sub_window
      @current_row
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

    # Close the sub window if open
    def close_sub_window
      if @sub_window
        was_preview = @sub_window.is_a?(PreviewWindow)
        @sub_window.close
        @sub_window = nil
        # Restore preview if it was enabled and we closed a non-preview window
        if @preview_enabled && !was_preview
          @sub_window = PreviewWindow.new(self)
          @sub_window.render
        end
        move_cursor current_row
      end
    end

    # Get a char as a String from user input.
    def get_char
      Curses.stdscr.timeout = -1  # Blocking mode for user input
      c = Curses.getch
      Curses.stdscr.timeout = 100  # Restore non-blocking mode
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
      Curses.stdscr.timeout = -1  # Blocking mode for user input
      begin
        while (c = Curses.getch)
          next unless [?N, ?Y, ?n, ?y, 3, 27] .include? c  # N, Y, n, y, ^c, esc
          clear_command_line
          break (c == 'y') || (c == 'Y')
        end
      ensure
        Curses.stdscr.timeout = 100  # Restore non-blocking mode
      end
    end

    def move_cursor_by_click(y: nil, x: nil)
      if (idx = main.pane_index_at(y: y, x: x))
        row = current_page * max_items + main.maxy * idx + y - main.begy
        move_cursor row if (row >= 0) && (row < items.size)
      end
    end

    def help
      lines = HelpGenerator.generate.lines
      h = [lines.size + 2, Curses.lines - 6].min
      w = [lines.map(&:size).max + 4, Curses.cols - 4].min
      y = (Curses.lines - h) / 2
      x = (Curses.cols - w) / 2

      win = Curses::Window.new(h, w, y, x)
      win.bkgdset Curses.color_pair(Curses::COLOR_CYAN)
      Rfd::Window.draw_ncursesw_border(win, h, w)
      win.setpos(0, 2)
      win.addstr(' Help (press any key to close) ')

      win.bkgdset Curses.color_pair(Curses::COLOR_WHITE)
      lines.first(h - 2).each_with_index do |line, i|
        win.setpos(i + 1, 2)
        win.addstr(line.chomp[0, w - 4])
      end
      win.refresh
      Curses.stdscr.timeout = -1
      Curses.getch
      Curses.stdscr.timeout = 100
      win.close
      move_cursor current_row
    end

    private

    def execute_external_command(pause: false)
      Curses.def_prog_mode
      Curses.close_screen
      yield
    ensure
      Curses.reset_prog_mode
      if pause
        Curses.stdscr.timeout = -1
        Curses.getch
        Curses.stdscr.timeout = 100
      end
      #NOTE needs to draw borders and ls again here since the stdlib Curses.refresh fails to retrieve the previous screen
      Rfd::Window.draw_borders
      Curses.refresh
      ls
    end

    def debug(str)
      @debug.debug str
    end
  end
end
