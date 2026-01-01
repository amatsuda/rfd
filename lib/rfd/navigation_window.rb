# frozen_string_literal: true

module Rfd
  # Tree node for directory tree browser
  TreeNode = Struct.new(:path, :name, :relative_path, :depth, :expanded, :children, :parent, keyword_init: true) do
    def has_subdirs?
      return false unless File.directory?(path)
      @has_subdirs = Dir.children(path).any? { |c| File.directory?(File.join(path, c)) } if @has_subdirs.nil?
      @has_subdirs
    rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
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
      @root = controller.current_dir.path

      # Add ..
      @nodes << TreeNode.new(path: File.dirname(@root), name: '..', relative_path: '..', depth: 0, expanded: false, children: nil, parent: nil)

      # Add first-level directories (expanded by default)
      add_children_for(@root, 0, nil, expanded: true)

      @cursor = 1 if @nodes.size > 1  # Start on first real directory
    end

    def add_children_for(dir_path, depth, parent_node, expanded: false)
      entries = Dir.children(dir_path)
        .select { |name| File.directory?(File.join(dir_path, name)) }
        .reject { |name| name.start_with?('.') }
        .sort

      children = []
      entries.each do |name|
        path = File.join(dir_path, name)
        relative_path = path.delete_prefix(@root).delete_prefix('/')
        node = TreeNode.new(
          path: path,
          name: name,
          relative_path: relative_path,
          depth: depth + 1,
          expanded: expanded,
          children: nil,
          parent: parent_node
        )
        children << node
        @nodes << node

        # Recursively add children if expanded
        if expanded && node.has_subdirs?
          add_children_for(path, depth + 1, node, expanded: false)
        end
      end

      # Set children on parent so collapse works
      parent_node.children = children if parent_node
    rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
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

      draw_border('Navigate (^O:fold Enter:cd ESC:close)')

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
        icon = if node.name == '..'
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
      when 8, 127, Curses::KEY_BACKSPACE, Curses::KEY_DC  # Ctrl-H/Backspace/Delete
        if @filter_text.length > 0
          @filter_text = @filter_text[0..-2]
          apply_filter
          render
        end
        true
      when 21  # Ctrl-U - clear filter
        @filter_text = ''
        apply_filter
        render
        true
      when 14  # Ctrl-N
        move_cursor_down
        true
      when 16  # Ctrl-P
        move_cursor_up
        true
      when 15  # Ctrl-O - toggle expand/collapse
        toggle_node
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
        @cursor = 0
      else
        @filtered_nodes = []
        @filtered_paths = {}  # Track added paths to avoid duplicates
        @first_match_index = nil

        # Special case: ~ means scan from home directory (first level only for performance)
        if @filter_text.start_with?('~')
          home = File.expand_path('~')
          pattern = @filter_text[1..-1].sub(/^\//, '')  # Remove leading ~/ or ~
          scan_home_directories(home, pattern)
        else
          scan_directories_for_filter(@root, '', nil, 0, @filter_text)
        end

        @cursor = @first_match_index || 0
        @filtered_paths = nil
        @first_match_index = nil
      end
      @scroll = 0
      adjust_scroll
    end

    # Fast scan for ~ paths - only first level, no recursion
    def scan_home_directories(home, pattern)
      entries = Dir.children(home)
        .select { |name| File.directory?(File.join(home, name)) }
        .reject { |name| name.start_with?('.') }
        .sort

      entries.each do |name|
        path = File.join(home, name)
        relative_path = "~/#{name}"

        next unless fuzzy_match?(name, pattern)

        node = TreeNode.new(
          path: path,
          name: name,
          relative_path: relative_path,
          depth: 0,
          expanded: false,
          children: nil,
          parent: nil
        )
        @first_match_index ||= @filtered_nodes.size
        @filtered_nodes << node
      end
    rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
      # Permission denied or not found, skip
    end

    def scan_directories_for_filter(dir_path, relative_prefix, parent_node, depth, pattern)
      entries = Dir.children(dir_path)
        .select { |name| File.directory?(File.join(dir_path, name)) }
        .reject { |name| name.start_with?('.') }
        .sort

      entries.each do |name|
        path = File.join(dir_path, name)
        relative_path = relative_prefix.empty? ? name : "#{relative_prefix}/#{name}"

        # Create node (may be added if this or descendant matches)
        node = TreeNode.new(
          path: path,
          name: name,
          relative_path: relative_path,
          depth: depth,
          expanded: true,
          children: nil,
          parent: parent_node
        )

        # For ~ paths, match against path after ~/
        match_path = relative_prefix == '~' || relative_prefix.start_with?('~/') ? relative_path[2..-1] : relative_path
        if fuzzy_match?(match_path || '', pattern)
          # Add all ancestors first
          add_ancestors_to_filter(node)
          # Add this node if not already added
          unless @filtered_paths[path]
            @filtered_paths[path] = true
            @first_match_index ||= @filtered_nodes.size  # First actual match
            @filtered_nodes << node
          end
        end

        # Recursively scan subdirectories
        scan_directories_for_filter(path, relative_path, node, depth + 1, pattern)
      end
    rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
      # Permission denied or not found, skip
    end

    def add_ancestors_to_filter(node)
      ancestors = []
      current = node.parent
      while current
        break if @filtered_paths[current.path]
        ancestors.unshift(current)
        current = current.parent
      end
      ancestors.each do |ancestor|
        @filtered_paths[ancestor.path] = true
        @filtered_nodes << ancestor
      end
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

    def toggle_node
      node = current_node
      return unless node
      return if node.name == '..'
      return unless node.has_subdirs?

      if node.expanded
        collapse_node
      else
        expand_node
      end
    end

    def expand_node
      node = current_node
      return unless node
      return if node.name == '..'
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
            relative_path = path.delete_prefix(@root).delete_prefix('/')
            child = TreeNode.new(
              path: path,
              name: name,
              relative_path: relative_path,
              depth: node.depth + 1,
              expanded: false,
              children: nil,
              parent: node
            )
            children << child
          end
        rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
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
