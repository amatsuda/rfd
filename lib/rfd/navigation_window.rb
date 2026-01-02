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
    def initialize(controller, title: nil, include_files: false, &on_select)
      super(controller)
      @nodes = []
      @cursor = 0
      @scroll = 0
      @filter = FilterInput.new { apply_filter }
      @filtered_nodes = nil
      @title = title
      @include_files = include_files
      @on_select = on_select
      build_tree
    end

    def build_tree
      @nodes = []
      @root = controller.current_dir.path

      # Cache all directories with a single glob call
      cache_all_directories

      # Add ..
      @nodes << TreeNode.new(path: File.dirname(@root), name: '..', relative_path: '..', depth: 0, expanded: false, children: nil, parent: nil)

      # Add first-level directories (expanded by default)
      add_children_for(@root, 0, nil, expanded: true)

      @cursor = 1 if @nodes.size > 1  # Start on first real directory
    end

    def cache_all_directories
      glob_pattern = @include_files ? "#{@root}/**/*" : "#{@root}/**/*/"
      @dir_cache = Dir.glob(glob_pattern)
        .map { |path| path.chomp('/') }  # Remove trailing slash
        .reject { |path| path.split('/').any? { |part| part.start_with?('.') } }
        .map { |path| path.delete_prefix(@root).delete_prefix('/') }
        .reject(&:empty?)
        .sort
    rescue Errno::EACCES, Errno::ENOENT, Errno::EPERM
      @dir_cache = []
    end

    def add_children_for(dir_path, depth, parent_node, expanded: false)
      all_entries = Dir.children(dir_path).reject { |name| name.start_with?('.') }

      # Separate directories and files, sort each group
      dirs = all_entries.select { |name| File.directory?(File.join(dir_path, name)) }.sort
      files = @include_files ? all_entries.reject { |name| File.directory?(File.join(dir_path, name)) }.sort : []

      children = []
      (dirs + files).each do |name|
        path = File.join(dir_path, name)
        is_dir = File.directory?(path)
        relative_path = path.delete_prefix(@root).delete_prefix('/')
        node = TreeNode.new(
          path: path,
          name: name,
          relative_path: relative_path,
          depth: depth + 1,
          expanded: is_dir ? expanded : false,
          children: nil,
          parent: parent_node
        )
        children << node
        @nodes << node

        # Recursively add children if expanded (only for directories)
        if is_dir && expanded && node.has_subdirs?
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

      draw_border(@title || 'Navigate (^O:fold Enter:cd ESC:close)')

      # Filter input line (row 1)
      @filter.render(@window, 1, max_width)

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
      when 14  # Ctrl-N
        move_cursor_down
        true
      when 16  # Ctrl-P
        move_cursor_up
        true
      when 15  # Ctrl-O - toggle expand/collapse
        toggle_node
        true
      else
        if @filter.handle_input(c)
          render
          true
        else
          false
        end
      end
    end

    private

    def apply_filter
      if @filter.empty?
        @filtered_nodes = nil
        @cursor = 0
      else
        @filtered_nodes = []
        @filtered_paths = {}  # Track added paths to avoid duplicates
        @first_match_index = nil

        # Special case: ~ means scan from home directory (first level only for performance)
        # Special case: / means scan from root directory (first level only for performance)
        if @filter.text.start_with?('~')
          home = File.expand_path('~')
          pattern = @filter.text[1..-1].sub(/^\//, '')  # Remove leading ~/ or ~
          scan_absolute_path_directories(home, '~', pattern)
        elsif @filter.text.start_with?('/')
          pattern = @filter.text[1..-1]  # Remove leading /
          scan_absolute_path_directories('/', '/', pattern)
        else
          scan_directories_for_filter(@filter.text)
        end

        @cursor = @first_match_index || 0
        @filtered_paths = nil
        @first_match_index = nil
      end
      @scroll = 0
      adjust_scroll
    end

    # Fast scan for absolute paths (~ or /) - only first level, no recursion
    def scan_absolute_path_directories(base_path, prefix, pattern)
      entries = Dir.children(base_path)
        .select { |name| File.directory?(File.join(base_path, name)) }
        .reject { |name| name.start_with?('.') }
        .sort

      entries.each do |name|
        path = File.join(base_path, name)
        relative_path = prefix == '/' ? "/#{name}" : "#{prefix}/#{name}"

        next unless @filter.fuzzy_match?(name, pattern)

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

    def scan_directories_for_filter(pattern)
      # Filter from cache - no system calls!
      @dir_cache.each do |relative_path|
        next unless @filter.fuzzy_match?(relative_path, pattern)

        path = File.join(@root, relative_path)
        depth = relative_path.count('/')
        name = File.basename(relative_path)
        add_match_with_ancestors(path, name, relative_path, depth)
      end
    end

    def add_match_with_ancestors(path, name, relative_path, depth)
      return if @filtered_paths[path]

      # Build ancestors from path components
      parts = relative_path.split('/')
      current_path = @root
      parts[0..-2].each_with_index do |part, i|
        current_path = File.join(current_path, part)
        next if @filtered_paths[current_path]

        @filtered_paths[current_path] = true
        @filtered_nodes << TreeNode.new(
          path: current_path,
          name: part,
          relative_path: parts[0..i].join('/'),
          depth: i,
          expanded: true,
          children: nil,
          parent: nil
        )
      end

      # Add the matched node
      @filtered_paths[path] = true
      @first_match_index ||= @filtered_nodes.size
      @filtered_nodes << TreeNode.new(
        path: path,
        name: name,
        relative_path: relative_path,
        depth: depth,
        expanded: true,
        children: nil,
        parent: nil
      )
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

      # If no matches but filter text exists, use filter text as literal path
      if node.nil? && !@filter.empty?
        controller.close_sub_window
        if @on_select
          @on_select.call(@filter.text)
        end
        return
      end

      return unless node

      if @on_select
        # Copy selected path to input for editing, don't execute yet
        @filter.text = node.relative_path
        @filtered_nodes = []  # Clear matches so next Enter executes
        @cursor = 0
        render
      else
        controller.close_sub_window
        controller.cd(node.path)
      end
    end
  end
end
