# frozen_string_literal: true

using Module.new {
  refine Module do
    def group(label, description)
      methods_before = instance_methods(false)
      yield
      Rfd::Commands.command_groups << {category: self, label: label, methods: instance_methods(false) - methods_before, description: description}
    end

    def nohelp(meth)
      Rfd::Commands.no_help_methods << meth
    end
  end
}

module Rfd
  module Commands
    @command_groups, @no_help_methods, @categories = [], [], []

    class << self
      attr_accessor :command_groups, :no_help_methods, :categories
    end

    # Navigation commands for cursor movement and directory traversal.
    module Navigation
      group 'j/k', 'Move cursor down/up.' do
        # Move cursor down.
        def j
          move_cursor (current_row + times) % items.size
        end

        # Move the cursor up.
        def k
          move_cursor (current_row - times) % items.size
        end
      end

      group 'h/l', 'Move cursor left/right between panes.' do
        # Move cursor left between panes.
        def h
          (y = current_row - maxy) >= 0 and move_cursor y
        end

        # Move the cursor to the right pane.
        def l
          (y = current_row + maxy) < items.size and move_cursor y
        end
      end

      group 'g/G', 'Go to first/last item.' do
        # Go to first item.
        def g
          move_cursor 0
        end

        # Go to last item.
        def G
          move_cursor items.size - 1
        end
      end

      group 'H/M/L', 'Go to top/middle/bottom of screen.' do
        # Go to top of screen.
        def H
          move_cursor current_page * max_items
        end

        # Go to middle of screen.
        def M
          move_cursor current_page * max_items + displayed_items.size / 2
        end

        # Go to bottom of screen.
        def L
          move_cursor current_page * max_items + displayed_items.size - 1
        end
      end

      group 'f{char}/F{char}', 'Find file starting with given character.' do
        # Find file starting with given character.
        def f
          c = get_char and (@last_command, @last_command_reverse = -> { find c }, -> { find_reverse c }) && @last_command.call
        end

        # Find file starting with given character (reverse).
        def F
          c = get_char and (@last_command, @last_command_reverse = -> { find_reverse c }, -> { find c }) && @last_command.call
        end
      end

      group 'n/N', 'Repeat last find forward/backward.' do
        # Repeat last find forward.
        def n
          @last_command.call if @last_command
        end

        # Repeat last find in reverse direction.
        def N
          @last_command_reverse.call if @last_command_reverse
        end
      end

      group '^n/^p', 'Next/previous page.' do
        # Forward to next page.
        define_method(:'^n') do
          move_cursor (current_page + 1) % total_pages * max_items if total_pages > 1
        end

        # Back to previous page.
        define_method(:'^p') do
          move_cursor (current_page - 1) % total_pages * max_items if total_pages > 1
        end

        # Back to previous page.
        nohelp define_method(:'^b') {
          public_send :'^p'
        }

        # Forward to next page.
        nohelp define_method(:'^f') {
          public_send :'^n'
        }
      end

      # Enter: Open directory or view file.
      def enter
        if current_item.name == '.'  # do nothing
        elsif current_item.name == '..'
          cd '..'
        elsif in_zip?
          v
        elsif current_item.directory? || current_item.zip?
          cd current_item
        elsif current_item.image?
          view_image
        elsif current_item.audio?
          play_audio
        elsif current_item.video? || current_item.pdf?
          system 'open', current_item.path if osx?
        else
          v
        end
      end

      # Backspace: Go to parent directory.
      def backspace
        if current_dir.path != '/'
          dir_was = times == 1 ? current_dir.name : File.basename(current_dir.join(['..'] * (times - 1)))
          cd File.expand_path(current_dir.join(['..'] * times))
          find dir_was
        end
      end

      # Go back to previous directory.
      def -
        popd
      end

      # Go to home directory.
      define_method(:'~') do
        cd '~'
      end

      # Directory tree navigation.
      define_method(:'@') do
        close_sub_window if @sub_window
        @sub_window = NavigationWindow.new(self)
        @sub_window.render
      end

      # Move cursor position by mouse click.
      nohelp def click(y: nil, x: nil)
        move_cursor_by_click y: y, x: x
      end

      # Move cursor position and enter.
      nohelp def double_click(y: nil, x: nil)
        if move_cursor_by_click y: y, x: x
          enter
        end
      end
    end

    # File operation commands for manipulating files and directories.
    module FileOperations
      # Space: Mark/unmark file and move down.
      def space
        times.times do
          toggle_mark
          move_cursor (current_row + 1) % items.size
        end
        draw_marked_items
      end

      # Mark/unmark all items.
      define_method(:'^a') do
        mark = marked_items.size != (items.size - 2)  # exclude . and ..
        items.each {|i| i.toggle_mark unless i.marked? == mark}
        draw_items
        draw_marked_items
        move_cursor current_row
      end

      # Copy selected items.
      def c
        return unless selected_items.any?
        close_sub_window if @sub_window
        @sub_window = NavigationWindow.new(self, title: 'Copy to (Enter:select ESC:cancel)', include_files: true) do |dest|
          cp dest
        end
        @sub_window.render
      end

      # Move selected items.
      def m
        return unless selected_items.any?
        close_sub_window if @sub_window
        @sub_window = NavigationWindow.new(self, title: 'Move to (Enter:select ESC:cancel)', include_files: true) do |dest|
          mv dest
        end
        @sub_window.render
      end

      # Rename selected items.
      def r
        process_command_line preset_command: 'rename'
      end

      group 'd/D', 'Trash/delete selected items.' do
        # Trash selected items.
        def d
          if selected_items.any?
            if ask %Q[Are you sure want to trash #{selected_items.one? ? selected_items.first.name : "these #{selected_items.size} files"}? (y/n)]
              trash
            end
          end
        end

        # Hard delete selected items.
        def D
          if selected_items.any?
            if ask %Q[Are you sure want to delete #{selected_items.one? ? selected_items.first.name : "these #{selected_items.size} files"}? (y/n)]
              delete
            end
          end
        end
      end

      group 't/K', 'Touch file / make directory.' do
        # Touch file.
        def t
          process_command_line preset_command: 'touch'
        end

        # Make a new directory.
        def K
          process_command_line preset_command: 'mkdir'
        end

        # Update file timestamp.
        nohelp def T
          process_command_line preset_command: 'touch_t', default_argument: current_item.mtime.tr(': -', '')
        end
      end

      group 'y/p', 'Yank/paste selected items.' do
        # Yank selected items.
        def y
          yank
        end

        # Paste yanked items.
        def p
          paste
        end
      end

      group 'z/u', 'Zip/unarchive files.' do
        # Zip files.
        def z
          process_command_line preset_command: 'zip'
        end

        # Unarchive zip/tar.gz files.
        def u
          unarchive
        end
      end

      # Change permission (chmod).
      def a
        process_command_line preset_command: 'chmod'
      end

      # Change owner (chown).
      def w
        process_command_line preset_command: 'chown'
      end

      # Create symlink.
      def S
        process_command_line preset_command: 'symlink'
      end
    end

    # Viewing commands for displaying file contents.
    module Viewing
      group 'v/e', 'View/edit file.' do
        # View file.
        def v
          view
        end

        # Edit current file.
        def e
          edit
        end
      end

      # Open with system viewer.
      def o
        if selected_items.any?
          system 'open', *selected_items.map(&:path)
        elsif %w(. ..).include? current_item.name
          system 'open', current_item.path
        end
      end

      # Toggle preview window.
      def P
        preview
      end

      # Search files (grep).
      def /
        process_command_line preset_command: 'grep'
      end

      # Sort files.
      def s
        process_command_line preset_command: 'sort'
      end
    end

    # Other utility commands.
    module Other
      # Copy path to clipboard.
      def C
        clipboard
      end

      # Open terminal here.
      def O
        dir = current_item.directory? ? current_item.path : current_dir.path
        escaped_dir = dir.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
        system 'osascript', '-e', %Q[tell app "Terminal" to do script "cd \\"#{escaped_dir}\\""] if osx?
      end

      # Set number of panes.
      define_method(:'^w') do
        if @times
          spawn_panes @times.to_i
          ls
        end
      end

      # Refresh the screen.
      define_method(:'^l') do
        ls
      end

      # Execute shell command.
      define_method(:!) do
        process_shell_command
      end

      # Execute rfd command.
      define_method(:':') do
        process_command_line
      end

      # Quit the app.
      def q
        raise StopIteration if ask 'Are you sure want to exit? (y/n)'
      end

      # Quit the app immediately.
      nohelp def q!
        raise StopIteration
      end

      # Show help screen.
      define_method(:'?') do
        help
      end

      # Number of times to repeat the next command.
      (?0..?9).each do |n|
        nohelp define_method(n) {
          @times = (@times || '') + n
        }
      end
    end

    include Navigation
    @categories << Navigation
    include FileOperations
    @categories << FileOperations
    include Viewing
    @categories << Viewing
    include Other
    @categories << Other
  end
end
