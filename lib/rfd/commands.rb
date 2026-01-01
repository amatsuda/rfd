# frozen_string_literal: true
module Rfd
  module Commands
    # Change permission (chmod).
    def a
      process_command_line preset_command: 'chmod'
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

    # Trash/delete selected items.
    def d
      if selected_items.any?
        if ask %Q[Are you sure want to trash #{selected_items.one? ? selected_items.first.name : "these #{selected_items.size} files"}? (y/n)]
          trash
        end
      end
    end

    # Edit current file.
    def e
      edit
    end

    # Find file starting with given character.
    def f
      c = get_char and (@last_command, @last_command_reverse = -> { find c }, -> { find_reverse c }) && @last_command.call
    end

    # Go to first/last item.
    def g
      move_cursor 0
    end

    # Move cursor left/right between panes.
    def h
      (y = current_row - maxy) >= 0 and move_cursor y
    end

    # Move cursor up/down.
    def j
      move_cursor (current_row + times) % items.size
    end

    # Move the cursor up.
    def k
      move_cursor (current_row - times) % items.size
    end

    # Move the cursor to the right pane.
    def l
      (y = current_row + maxy) < items.size and move_cursor y
    end

    # "m"ove selected files and directories.
    def m
      return unless selected_items.any?
      close_sub_window if @sub_window
      @sub_window = NavigationWindow.new(self, title: 'Move to (Enter:select ESC:cancel)', include_files: true) do |dest|
        mv dest
      end
      @sub_window.render
    end

    # Repeat last find forward/backward.
    def n
      @last_command.call if @last_command
    end

    # Redo the latest f or F in reverse direction.
    def N
      @last_command_reverse.call if @last_command_reverse
    end

    # Open with system viewer.
    def o
      if selected_items.any?
        system 'open', *selected_items.map(&:path)
      elsif %w(. ..).include? current_item.name
        system 'open', current_item.path
      end
    end

    # Paste yanked files / directories into the directory on which the cursor is, or into the current directory.
    def p
      paste
    end

    # "q"uit the app.
    def q
      raise StopIteration if ask 'Are you sure want to exit? (y/n)'
    end

    # "q"uit the app!
    def q!
      raise StopIteration
    end

    # "r"ename selected files and directories.
    def r
      process_command_line preset_command: 'rename'
    end

    # Sort files.
    def s
      process_command_line preset_command: 'sort'
    end

    # Touch file / make directory.
    def t
      process_command_line preset_command: 'touch'
    end

    # Unarchive zip/tar.gz files.
    def u
      unarchive
    end

    # View/edit file.
    def v
      view
    end

    # Change owner (chown).
    def w
      process_command_line preset_command: 'chown'
    end

    # Yank/paste selected items.
    def y
      yank
    end

    # Zip/unarchive files.
    def z
      process_command_line preset_command: 'zip'
    end

    # Copy path to clipboard.
    def C
      clipboard
    end

    # Hard delete selected items.
    def D
      if selected_items.any?
        if ask %Q[Are you sure want to delete #{selected_items.one? ? selected_items.first.name : "these #{selected_items.size} files"}? (y/n)]
          delete
        end
      end
    end

    # "f"ind the last file or directory of which name starts with the given String.
    def F
      c = get_char and (@last_command, @last_command_reverse = -> { find_reverse c }, -> { find c }) && @last_command.call
    end

    # Go to top/middle/bottom of screen.
    def H
      move_cursor current_page * max_items
    end

    # Go to last item.
    def G
      move_cursor items.size - 1
    end

    # Make a new directory.
    def K
      process_command_line preset_command: 'mkdir'
    end

    # Go to bottom of screen.
    def L
      move_cursor current_page * max_items + displayed_items.size - 1
    end

    # Go to middle of screen.
    def M
      move_cursor current_page * max_items + displayed_items.size / 2
    end

    # Open terminal here.
    def O
      dir = current_item.directory? ? current_item.path : current_dir.path
      escaped_dir = dir.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
      system 'osascript', '-e', %Q[tell app "Terminal" to do script "cd \\"#{escaped_dir}\\""] if osx?
    end

    # Create symlink.
    def S
      process_command_line preset_command: 'symlink'
    end

    # Update file timestamp.
    def T
      process_command_line preset_command: 'touch_t', default_argument: current_item.mtime.tr(': -', '')
    end

    # Toggle preview window.
    def P
      preview
    end

    # Mark/unmark all items.
    def ctrl_a
      mark = marked_items.size != (items.size - 2)  # exclude . and ..
      items.each {|i| i.toggle_mark unless i.marked? == mark}
      draw_items
      draw_marked_items
      move_cursor current_row
    end

    # Back to previous page.
    def ctrl_b
      ctrl_p
    end

    # Forward to next page.
    def ctrl_f
      ctrl_n
    end

    # Refresh the screen.
    def ctrl_l
      ls
    end

    # Next/previous page.
    def ctrl_n
      move_cursor (current_page + 1) % total_pages * max_items if total_pages > 1
    end

    # Back to previous page.
    def ctrl_p
      move_cursor (current_page - 1) % total_pages * max_items if total_pages > 1
    end

    # Set number of panes.
    def ctrl_w
      if @times
        spawn_panes @times.to_i
        ls
      end
    end

    # Number of times to repeat the next command.
    (?0..?9).each do |n|
      define_method(n) do
        @times ||= ''
        @times += n
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

    # Search files (grep).
    def /
      process_command_line preset_command: 'grep'
    end

    # Directory tree navigation.
    define_method(:'@') do
      close_sub_window if @sub_window
      @sub_window = NavigationWindow.new(self)
      @sub_window.render
    end

    # Execute shell command.
    define_method(:!) do
      process_shell_command
    end

    # Execute rfd command.
    define_method(:':') do
      process_command_line
    end

    # Show help screen.
    define_method(:'?') do
      help
    end

    # Open directory or view file.
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

    # Mark/unmark file and move down.
    def space
      times.times do
        toggle_mark
        move_cursor (current_row + 1) % items.size
      end
      draw_marked_items
    end

    # Go to parent directory.
    def del
      if current_dir.path != '/'
        dir_was = times == 1 ? current_dir.name : File.basename(current_dir.join(['..'] * (times - 1)))
        cd File.expand_path(current_dir.join(['..'] * times))
        find dir_was
      end
    end

    # Move cursor position by mouse click.
    def click(y: nil, x: nil)
      move_cursor_by_click y: y, x: x
    end

    # Move cursor position and enter
    def double_click(y: nil, x: nil)
      if move_cursor_by_click y: y, x: x
        enter
      end
    end
  end
end
