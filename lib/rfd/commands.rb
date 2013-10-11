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
      c = get_char and (@last_command = -> { find c }).call
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

    # "o"pen selected files and directories with the OS "open" command.
    def o
      if selected_items.any?
        system "open #{selected_items.map {|i| %Q["#{i.path}"]}.join(' ')}"
      elsif %w(. ..).include? current_item.name
        system %Q[open "#{current_item.path}"]
      end
    end

    # "q"uit the app.
    def q
      raise StopIteration if ask 'Are you sure want to exit? (y/n)'
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
      c = get_char and (@last_command = -> { find_reverse c }).call
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
      dir = current_item.directory? ? current_item.path : current_dir
      system %Q[osascript -e 'tell app "Terminal"
        do script "cd #{dir}"
      end tell'] if osx?
    end

    # "S"ymlink the current file or directory
    def S
      process_command_line preset_command: 'symlink'
    end

    # Mark or unmark "a"ll files and directories.
    def ctrl_a
      mark = marked_items.size != (items.size - 2)  # exclude . and ..
      items.each {|i| i.toggle_mark unless i.marked? == mark}
      draw_items
      move_cursor current_row
      draw_marked_items
      header_r.wrefresh
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
    # type the number of columns (1-9) right after ctrl-w
    def ctrl_w
      if (c = get_char)
        begin
          num = Integer c
        rescue ArgumentError
          return
        end
        spawn_panes num
        ls
      end
    end

    # Return to the previous directory (popd).
    def -
      popd
    end

    # Search files and directories from the current directory.
    def /
      process_command_line preset_command: 'grep'
    end

    # Execute a shell command in an external shell.
    define_method('!') do
      process_shell_command
    end

    # Execute a command in the controller context.
    define_method(':') do
      process_command_line
    end

    # cd into a directory, or view a file.
    def enter
      if current_item.name == '.'  # do nothing
      elsif current_item.name == '..'
        cd '..'
        ls
      elsif in_zip?
        v
      elsif current_item.directory? || current_item.zip?
        cd current_item
        ls
      else
        v
      end
    end

    # Toggle mark, and move down.
    def space
      toggle_mark
      j
      draw_marked_items
      header_r.wrefresh
    end

    # cd to the upper hierarchy.
    def del
      if current_dir != '/'
        cd '..'
        ls
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
