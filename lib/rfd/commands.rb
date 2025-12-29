# frozen_string_literal: true
module Rfd
  module Commands
    # Change permission ("A"ttributes) of selected files and directories.
    def a
      process_command_line preset_command: 'chmod'
    end

    # "c"opy selected files and directories.
    def c
      process_command_line preset_command: 'cp'
    end

    # Soft "d"elete (actually mv to the trash folder on OSX) selected files and directories.
    def d
      if selected_items.any?
        if ask %Q[Are you sure want to trash #{selected_items.one? ? selected_items.first.name : "these #{selected_items.size} files"}? (y/n)]
          trash
        end
      end
    end

    # Open current file or directory with the "e"ditor
    def e
      edit
    end

    # "f"ind the first file or directory of which name starts with the given String.
    def f
      c = get_char and (@last_command, @last_command_reverse = -> { find c }, -> { find_reverse c }) && @last_command.call
    end

    # Move the cursor to the top of the list.
    def g
      move_cursor 0
    end

    # Move the cursor to the left pane.
    def h
      (y = current_row - maxy) >= 0 and move_cursor y
    end

    # Move the cursor down.
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
      process_command_line preset_command: 'mv'
    end

    # Redo the latest f or F.
    def n
      @last_command.call if @last_command
    end

    # Redo the latest f or F in reverse direction.
    def N
      @last_command_reverse.call if @last_command_reverse
    end

    # "o"pen selected files and directories with the OS "open" command.
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

    # "s"ort displayed files and directories in the given order.
    def s
      process_command_line preset_command: 'sort'
    end

    # Create a new file, or update its timestamp if the file already exists ("t"ouch).
    def t
      process_command_line preset_command: 'touch'
    end

    # "u"narchive .zip and .tar.gz files within selected files and directories into current_directory.
    def u
      unarchive
    end

    # "o"pen selected files and directories with the viewer.
    def v
      view
    end

    # Change o"w"ner of selected files and directories.
    def w
      process_command_line preset_command: 'chown'
    end

    # "y"ank selected file / directory names.
    def y
      yank
    end

    # Archive selected files and directories into a "z"ip file.
    def z
      process_command_line preset_command: 'zip'
    end

    # "C"opy paths of selected files and directory to the "C"lipboard.
    def C
      clipboard
    end

    # Hard "d"elete selected files and directories.
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

    # Move the cursor to the top.
    def H
      move_cursor current_page * max_items
    end

    # Move the cursor to the bottom of the list.
    def G
      move_cursor items.size - 1
    end

    # Ma"K"e a directory.
    def K
      process_command_line preset_command: 'mkdir'
    end

    # Move the cursor to the bottom.
    def L
      move_cursor current_page * max_items + displayed_items.size - 1
    end

    # Move the cursor to the "M"iddle.
    def M
      move_cursor current_page * max_items + displayed_items.size / 2
    end

    # "O"pen terminal here.
    def O
      dir = current_item.directory? ? current_item.path : current_dir.path
      escaped_dir = dir.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
      system 'osascript', '-e', %Q[tell app "Terminal" to do script "cd \\"#{escaped_dir}\\""] if osx?
    end

    # "S"ymlink the current file or directory
    def S
      process_command_line preset_command: 'symlink'
    end

    # "T"ouch the current file. This updates current item's timestamp (equivalent to `touch -t`).
    def T
      process_command_line preset_command: 'touch_t', default_argument: current_item.mtime.tr(': -', '')
    end

    # "P"review the current file in a floating window.
    def P
      preview
    end

    # Mark or unmark "a"ll files and directories.
    def ctrl_a
      mark = marked_items.size != (items.size - 2)  # exclude . and ..
      items.each {|i| i.toggle_mark unless i.marked? == mark}
      draw_items
      draw_marked_items
      move_cursor current_row
    end

    # "b"ack to the previous page.
    def ctrl_b
      ctrl_p
    end

    # "f"orward to the next page.
    def ctrl_f
      ctrl_n
    end

    # Refresh the screen.
    def ctrl_l
      ls
    end

    # Forward to the "n"ext page.
    def ctrl_n
      move_cursor (current_page + 1) % total_pages * max_items if total_pages > 1
    end

    # Back to the "p"revious page.
    def ctrl_p
      move_cursor (current_page - 1) % total_pages * max_items if total_pages > 1
    end

    # Split the main "w"indow into given number of columns.
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

    # Return to the previous directory (popd).
    def -
      popd
    end

    # Jump to home directory.
    define_method(:'~') do
      cd '~'
    end

    # Search files and directories from the current directory.
    def /
      process_command_line preset_command: 'grep'
    end

    # Change current directory (cd).
    define_method(:'@') do
      process_command_line preset_command: 'cd'
    end

    # Execute a shell command in an external shell.
    define_method(:!) do
      process_shell_command
    end

    # Execute a command in the controller context.
    define_method(:':') do
      process_command_line
    end

    # Show help screen.
    define_method(:'?') do
      help
    end

    # cd into a directory, or view a file.
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
      elsif current_item.pdf?
        system 'open', current_item.path if osx?
      else
        v
      end
    end

    # Toggle mark, and move down.
    def space
      times.times do
        toggle_mark
        move_cursor (current_row + 1) % items.size
      end
      draw_marked_items
    end

    # cd to the upper hierarchy.
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
