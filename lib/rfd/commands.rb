module Rfd
  module Commands
    def a
      @base.process_command_line prompt: ':chmod '
    end

    def c
      @base.process_command_line prompt: ':cp '
    end

    def d
      FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
      @row -= selected_items.count {|i| i.index <= @row}
      ls
    end

    def f
      @base.process_command_line prompt: ':find '
    end

    def F
      @base.process_command_line prompt: ':find_reverse '
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

    def q
      raise StopIteration
    end

    def s
      @base.process_command_line prompt: ':sort '
    end

    def t
      @base.process_command_line prompt: ':touch '
    end

    def v
      switch_mode MODE::MIEL
      wclear
      @viewer = ViewerWindow.new base: @base
      @viewer.draw current_item.read
      wrefresh
    end

    def D
      FileUtils.rm_rf selected_items.map(&:path)
      @row -= selected_items.count {|i| i.index <= @row}
      ls
    end

    def H
      move_cursor @current_page * maxy
    end

    def K
      @base.process_command_line prompt: ':mkdir '
    end

    def L
      move_cursor @current_page * maxy + @displayed_items.size - 1
    end

    def M
      move_cursor @current_page * maxy + @displayed_items.size / 2
    end

    def ctrl_n
      if total_pages > 1
        if @current_page + 1 < total_pages
          move_cursor (@current_page + 1) * maxy
        else
          move_cursor 0
        end
      end
    end

    def ctrl_p
      if total_pages > 1
        if @current_page > 0
          move_cursor (@current_page - 1) * maxy
        else
          move_cursor (total_pages - 1) * maxy
        end
      end
    end

    def ctrl_r
      ls
    end

    def /
      @base.process_command_line prompt: ':grep '
    end

    define_method(':') do
      @base.process_command_line
    end

    def enter
      if current_item.directory?
        cd current_item
        ls
      else
        v
      end
    end

    def del
      if @base.command_mode? && (@dir != '/')
        cd '..'
        ls
      elsif @base.miel_mode?
        switch_mode MODE::COMMAND
        close_viewer
        move_cursor
      end
    end
  end
end
