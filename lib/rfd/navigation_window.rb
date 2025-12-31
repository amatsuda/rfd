# frozen_string_literal: true

module Rfd
  # Tree node for directory tree browser
  TreeNode = Struct.new(:path, :name, :depth, :expanded, :children, :parent, keyword_init: true) do
    def has_subdirs?
      return false unless File.directory?(path)
      @has_subdirs = Dir.children(path).any? { |c| File.directory?(File.join(path, c)) } if @has_subdirs.nil?
      @has_subdirs
    rescue Errno::EACCES, Errno::ENOENT
      false
    end
  end

  class NavigationWindow < SubWindow
    def initialize(controller)
      super
      @nodes = []
      @cursor = 0
      @scroll = 0
      @filter_text = ''
      @filtered_nodes = nil
      build_tree
    end

    def build_tree
      @nodes = []
      root = controller.current_dir.path

      # Add . and ..
      @nodes << TreeNode.new(path: root, name: '.', depth: 0, expanded: false, children: nil, parent: nil)
      @nodes << TreeNode.new(path: File.dirname(root), name: '..', depth: 0, expanded: false, children: nil, parent: nil)

      # Add first-level directories (expanded by default)
      add_children_for(root, 0, nil, expanded: true)

      @cursor = 2 if @nodes.size > 2  # Start on first real directory
    end

    def add_children_for(dir_path, depth, parent_node, expanded: false)
      entries = Dir.children(dir_path)
        .select { |name| File.directory?(File.join(dir_path, name)) }
        .reject { |name| name.start_with?('.') }
        .sort

      entries.each do |name|
        path = File.join(dir_path, name)
        node = TreeNode.new(
          path: path,
          name: name,
          depth: depth + 1,
          expanded: expanded,
          children: nil,
          parent: parent_node
        )
        @nodes << node

        # Recursively add children if expanded
        if expanded && node.has_subdirs?
          add_children_for(path, depth + 1, node, expanded: false)
        end
      end
    rescue Errno::EACCES, Errno::ENOENT
      # Permission denied or not found, skip
    end

    def display_nodes
      @filtered_nodes || @nodes
    end

    def visible_nodes
      # Reserve one line for filter input
      display_nodes[@scroll, max_height - 1] || []
    end

    def current_node
      display_nodes[@cursor]
    end

    def render
      reposition_if_needed
      @window.clear

      draw_border('Navigate (Enter:cd ESC:close)')

      # Filter input line (row 1)
      @window.setpos(1, 1)
      @window.attron(Curses::A_BOLD) do
        prompt = "> #{@filter_text}_"
        @window.addstr(prompt[0, max_width].ljust(max_width))
      end

      # Tree starts at row 2
      visible_nodes.each_with_index do |node, i|
        actual_index = @scroll + i
        @window.setpos(2 + i, 1)

        # Build display line
        indent = '  ' * node.depth
        icon = if node.name == '.' || node.name == '..'
                 ''
               elsif node.has_subdirs?
                 node.expanded ? '▾ ' : '▸ '
               else
                 '  '
               end
        text = "#{indent}#{icon}#{node.name}"

        # Highlight current selection
        if actual_index == @cursor
          @window.attron(Curses::A_REVERSE) do
            @window.addstr(text[0, max_width].ljust(max_width))
          end
        else
          @window.addstr(text[0, max_width].ljust(max_width))
        end
      end

      @window.refresh
    end

    def handle_input(c)
      case c
      when 27  # ESC - close window
        controller.close_sub_window
        true
      when 10, 13  # Enter - select current node
        select_node
        true
      when 127, Curses::KEY_BACKSPACE, Curses::KEY_DC  # Backspace/Delete
        if @filter_text.length > 0
          @filter_text = @filter_text[0..-2]
          apply_filter
          render
        end
        true
      when Curses::KEY_DOWN, 14  # Down or Ctrl-N
        move_cursor_down
        true
      when Curses::KEY_UP, 16  # Up or Ctrl-P
        move_cursor_up
        true
      when String
        # Printable character
        @filter_text += c
        apply_filter
        render
        true
      when Integer
        if c >= 32 && c <= 126  # Printable ASCII
          @filter_text += c.chr
          apply_filter
          render
          true
        else
          false
        end
      else
        false
      end
    end

    private

    def apply_filter
      if @filter_text.empty?
        @filtered_nodes = nil
      else
        @filtered_nodes = @nodes.select { |node| fuzzy_match?(node.name, @filter_text) }
      end
      @cursor = 0
      @scroll = 0
    end

    def fuzzy_match?(text, pattern)
      return true if pattern.empty?
      pattern_chars = pattern.downcase.chars
      text_lower = text.downcase
      pattern_index = 0

      text_lower.each_char do |char|
        if char == pattern_chars[pattern_index]
          pattern_index += 1
          return true if pattern_index >= pattern_chars.length
        end
      end
      false
    end

    def move_cursor_down
      return if @cursor >= display_nodes.size - 1
      @cursor += 1
      adjust_scroll
      render
    end

    def move_cursor_up
      return if @cursor <= 0
      @cursor -= 1
      adjust_scroll
      render
    end

    def adjust_scroll
      available_height = max_height - 1  # Reserve one line for filter input
      if @cursor < @scroll
        @scroll = @cursor
      elsif @cursor >= @scroll + available_height
        @scroll = @cursor - available_height + 1
      end
    end

    def expand_node
      node = current_node
      return unless node
      return if node.name == '.' || node.name == '..'
      return unless node.has_subdirs?
      return if node.expanded

      node.expanded = true

      # Find insertion point (after current node)
      insert_index = @cursor + 1

      # Load children if not already loaded
      if node.children.nil?
        children = []
        begin
          entries = Dir.children(node.path)
            .select { |name| File.directory?(File.join(node.path, name)) }
            .reject { |name| name.start_with?('.') }
            .sort

          entries.each do |name|
            path = File.join(node.path, name)
            child = TreeNode.new(
              path: path,
              name: name,
              depth: node.depth + 1,
              expanded: false,
              children: nil,
              parent: node
            )
            children << child
          end
        rescue Errno::EACCES, Errno::ENOENT
          # Permission denied or not found
        end
        node.children = children
      end

      # Insert children into flat list
      node.children.reverse_each do |child|
        @nodes.insert(insert_index, child)
      end
      render
    end

    def collapse_node
      node = current_node
      return unless node

      if node.expanded && node.children && node.children.any?
        # Collapse this node: remove all descendants
        node.expanded = false
        remove_descendants(node)
        render
      elsif node.parent
        # Move to parent
        parent_index = @nodes.index(node.parent)
        if parent_index
          @cursor = parent_index
          adjust_scroll
          render
        end
      elsif node.depth > 0
        # Find parent by path
        parent_path = File.dirname(node.path)
        parent_index = @nodes.index { |n| n.path == parent_path }
        if parent_index
          @cursor = parent_index
          adjust_scroll
          render
        end
      end
    end

    def remove_descendants(node)
      return unless node.children
      node.children.each do |child|
        remove_descendants(child) if child.expanded
        @nodes.delete(child)
      end
    end

    def select_node
      node = current_node
      return unless node
      controller.cd(node.path)
      controller.close_sub_window
    end
  end
end
