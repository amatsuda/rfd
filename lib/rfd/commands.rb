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

    # Soft "d"elete (actually mv to the trash folder) selected files and directories.
    def d
      if selected_items.any?
        if ask %Q[Are your sure want to trash #{selected_items.one? ? selected_items.first.name : "these #{selected_items.size} files"}? (y/n)]
          FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
          @current_row -= selected_items.count {|i| i.index <= current_row}
          ls
        end
      end
    end

    # Open current file or directory with the "e"ditor
    def e
      edit
    end

    # "f"ind the first file or directory of which name starts with the given String.
    def f
      process_command_line preset_command: 'find'
    end

    # Move the cursor to the left pane.
    def h
      (y = current_row - maxy) >= 0 and move_cursor y
    end

    # Move the cursor down.
    def j
      if current_row + 1 >= items.size
        move_cursor 0
      else
        move_cursor current_row + 1
      end
    end

    # Move the cursor up.
    def k
      if current_row == 0
        move_cursor items.size - 1
      else
        move_cursor current_row - 1
      end
    end

    # Move the cursor to the right pane.
    def l
      (y = current_row + maxy) < items.size and move_cursor y
    end

    # "m"ove selected files and directories.
    def m
      process_command_line preset_command: 'mv'
    end

    # "o"pen selected files and directories with the OS "open" command.
    def o
      system "open #{selected_items.map {|i| %Q["#{i.path}"]}.join(' ')}"
    end

    # "q"uit the app.
    def q
      raise StopIteration if ask 'Are your sure want to exit? (y/n)'
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

    # "o"pen selected files and directories with the viewer.
    def v
      view
    end

    # Hard "d"elete selected files and directories.
    def D
      if selected_items.any?
        if ask %Q[Are your sure want to delete #{selected_items.one? ? selected_items.first.name : "these #{selected_items.size} files"}? (y/n)]
          FileUtils.rm_rf selected_items.map(&:path)
          @current_row -= selected_items.count {|i| i.index <= current_row}
          ls
        end
      end
    end

    # "f"ind the last file or directory of which name starts with the given String.
    def F
      process_command_line preset_command: 'find_reverse'
    end

    # Move the cursor to the top.
    def H
      move_cursor current_page * max_items
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
      if total_pages > 1
        if last_page?
          move_cursor 0
        else
          move_cursor (current_page + 1) * max_items
        end
      end
    end

    # Back to the "p"revious page.
    def ctrl_p
      if total_pages > 1
        if first_page?
          move_cursor (total_pages - 1) * max_items
        else
          move_cursor (current_page - 1) * max_items
        end
      end
    end

    # Change the number of columns in the main window.
    (?1..?9).each do |n|
      define_method(n) do
        spawn_panes n.to_i
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
      if current_item.directory?
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
  end
end
