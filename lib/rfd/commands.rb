module Rfd
  module Commands
    def a
      process_command_line prompt: ':chmod '
    end

    def c
      process_command_line prompt: ':cp '
    end

    def d
      if selected_items.any?
        FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
        @row -= selected_items.count {|i| i.index <= @row}
        ls
      end
    end

    def f
      process_command_line prompt: ':find '
    end

    def F
      process_command_line prompt: ':find_reverse '
    end

    def h
      (y = @row - maxy) >= 0 and move_cursor y
    end

    def j
      if @row + 1 >= @items.size
        move_cursor 0
      else
        move_cursor @row + 1
      end
    end

    def k
      if @row == 0
        move_cursor @items.size - 1
      else
        move_cursor @row - 1
      end
    end

    def l
      (y = @row + maxy) < @items.size and move_cursor y
    end

    def m
      process_command_line prompt: ':mv '
    end

    def q
      raise StopIteration
    end

    def s
      process_command_line prompt: ':sort '
    end

    def t
      process_command_line prompt: ':touch '
    end

    def v
      view
    end

    def D
      if selected_items.any?
        FileUtils.rm_rf selected_items.map(&:path)
        @row -= selected_items.count {|i| i.index <= @row}
        ls
      end
    end

    def H
      move_cursor @current_page * max_items
    end

    def K
      process_command_line prompt: ':mkdir '
    end

    def L
      move_cursor @current_page * max_items + @displayed_items.size - 1
    end

    def M
      move_cursor @current_page * max_items + @displayed_items.size / 2
    end

    def ctrl_n
      if total_pages > 1
        if @current_page + 1 < total_pages
          move_cursor (@current_page + 1) * max_items
        else
          move_cursor 0
        end
      end
    end

    def ctrl_p
      if total_pages > 1
        if @current_page > 0
          move_cursor (@current_page - 1) * max_items
        else
          move_cursor (total_pages - 1) * max_items
        end
      end
    end

    def ctrl_r
      ls
    end

    def /
      process_command_line prompt: ':grep '
    end

    define_method(':') do
      process_command_line
    end

    def enter
      if current_item.directory?
        cd current_item
        ls
      else
        v
      end
    end

    def space
      toggle_mark
      draw_marked_items
      header_r.wrefresh
    end

    def del
      if @dir != '/'
        cd '..'
        ls
      end
    end
  end
end
