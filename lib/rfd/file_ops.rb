# frozen_string_literal: true

module Rfd
  module FileOps
    # Change the current directory.
    def cd(dir = '~', pushd: true)
      dir = load_item path: expand_path(dir) unless dir.is_a? Item
      unless dir.zip?
        Dir.chdir dir
        @current_zip = nil
      else
        @current_zip = dir
      end
      if current_dir && pushd
        @dir_history << current_dir
        @dir_history.shift if @dir_history.size > 100
      end
      @current_dir, @current_page, @current_row = dir, 0, nil
      main.activate_pane 0
      ls
      @current_dir
    rescue Errno::EACCES, Errno::ENOENT => e
      command_line.show_error e.message
      nil
    end

    # cd to the previous directory.
    def popd
      cd @dir_history.pop, pushd: false if @dir_history.any?
    end

    # Fetch files from current directory.
    # Then update each windows reflecting the newest information.
    def ls
      fetch_items_from_filesystem_or_zip
      sort_items_according_to_current_direction

      @current_page ||= 0
      draw_items
      move_cursor (current_row ? [current_row, items.size - 1].min : nil)

      draw_marked_items
      draw_total_items
      true
    end

    # Sort the whole files and directories in the current directory, then refresh the screen.
    #
    # ==== Parameters
    # * +direction+ - Sort order in a String.
    #                 nil   : order by name
    #                 r     : reverse order by name
    #                 s, S  : order by file size
    #                 sr, Sr: reverse order by file size
    #                 t     : order by mtime
    #                 tr    : reverse order by mtime
    #                 c     : order by ctime
    #                 cr    : reverse order by ctime
    #                 u     : order by atime
    #                 ur    : reverse order by atime
    #                 e     : order by extname
    #                 er    : reverse order by extname
    def sort(direction = nil)
      @direction, @current_page = direction, 0
      sort_items_according_to_current_direction
      draw_items
      switch_page 0
      move_cursor
    end

    # Change the file permission of the selected files and directories.
    #
    # ==== Parameters
    # * +mode+ - Unix chmod string (e.g. +w, g-r, 755, 0644)
    def chmod(mode = nil)
      return unless mode
      begin
        Integer mode
        mode = Integer mode.size == 3 ? "0#{mode}" : mode
      rescue ArgumentError
      end
      FileUtils.chmod mode, selected_items.map(&:path)
      ls
    end

    # Change the file owner of the selected files and directories.
    #
    # ==== Parameters
    # * +user_and_group+ - user name and group name separated by : (e.g. alice, nobody:nobody, :admin)
    def chown(user_and_group)
      return unless user_and_group
      user, group = user_and_group.split(':').map {|s| s == '' ? nil : s}
      FileUtils.chown user, group, selected_items.map(&:path)
      ls
    end

    # Fetch files from current directory or current .zip file.
    def fetch_items_from_filesystem_or_zip
      unless in_zip?
        @items = Dir.foreach(current_dir).map {|fn|
          load_item dir: current_dir, name: fn
        }.to_a.partition {|i| %w(. ..).include? i.name}.flatten
      else
        @items = [load_item(dir: current_dir, name: '.', stat: File.stat(current_dir)),
          load_item(dir: current_dir, name: '..', stat: File.stat(File.dirname(current_dir)))]
        Zip::File.open(current_dir) do |zf|
          zf.each do |entry|
            next if entry.name_is_directory?
            stat = zf.file.stat entry.name
            @items << load_item(dir: current_dir, name: entry.name, stat: stat)
          end
        end
      end
    rescue Errno::EACCES => e
      command_line.show_error e.message
      @items ||= []
    rescue Zip::Error => e
      command_line.show_error "ZIP error: #{e.message}"
    end

    SORT_KEYS = {
      's' => :size, 'S' => :size,
      't' => :mtime, 'c' => :ctime, 'u' => :atime, 'e' => :extname
    }.freeze

    # Sort the loaded files and directories in already given sort order.
    def sort_items_according_to_current_direction
      dots = items.shift(2)
      reverse = @direction&.end_with?('r')
      key = SORT_KEYS[@direction&.sub(/r$/, '')]

      sorted = items.partition(&:directory?).flat_map do |arr|
        if key
          sorted_arr = arr.sort_by(&key)
          reverse ? sorted_arr : sorted_arr.reverse
        else
          reverse ? arr.sort.reverse : arr.sort
        end
      end

      @items = dots + sorted
      items.each.with_index {|item, index| item.index = index}
    end

    # Search files and directories from the current directory, and update the screen.
    #
    # * +pattern+ - Search pattern against file names in Ruby Regexp string.
    #
    # === Example
    #
    # a        : Search files that contains the letter "a" in their file name
    # .*\.pdf$ : Search PDF files
    def grep(pattern = '.*')
      regexp = Regexp.new(pattern)
      fetch_items_from_filesystem_or_zip
      @items = items.shift(2) + items.select {|i| i.name =~ regexp}
      sort_items_according_to_current_direction
      draw_items
      draw_total_items
      move_cursor
    rescue RegexpError => e
      command_line.show_error "Invalid regex: #{e.message}"
      switch_page 0
      move_cursor
    end

    # Copy selected files and directories to the destination.
    def cp(dest)
      unless in_zip?
        src = (m = marked_items).any? ? m.map(&:path) : current_item
        FileUtils.cp_r src, expand_path(dest)
      else
        raise 'cping multiple items in .zip is not supported.' if selected_items.size > 1
        Zip::File.open(current_zip) do |zip|
          entry = zip.find_entry(selected_items.first.name).dup
          entry.name, entry.name_length = dest, dest.size
          zip.instance_variable_get(:@entry_set) << entry
        end
      end
      ls
    end

    # Move selected files and directories to the destination.
    def mv(dest)
      unless in_zip?
        src = (m = marked_items).any? ? m.map(&:path) : current_item
        FileUtils.mv src, expand_path(dest)
      else
        raise 'mving multiple items in .zip is not supported.' if selected_items.size > 1
        rename "#{selected_items.first.name}/#{dest}"
      end
      ls
    end

    # Rename selected files and directories.
    #
    # ==== Parameters
    # * +pattern+ - new filename, or a shash separated Regexp like string
    def rename(pattern)
      from, to = pattern.sub(/^\//, '').sub(/\/$/, '').split '/'
      if to.nil?
        from, to = current_item.name, from
      else
        from = Regexp.new from
      end
      unless in_zip?
        selected_items.each do |item|
          name = item.name.gsub from, to
          FileUtils.mv item, current_dir.join(name) if item.name != name
        end
      else
        Zip::File.open(current_zip) do |zip|
          selected_items.each do |item|
            name = item.name.gsub from, to
            zip.rename item.name, name
          end
        end
      end
      ls
    rescue RegexpError => e
      command_line.show_error "Invalid regex: #{e.message}"
    end

    # Soft delete selected files and directories.
    #
    # If the OS is not OSX, performs the same as `delete` command.
    def trash
      unless in_zip?
        if osx?
          FileUtils.mv selected_items.map(&:path), File.expand_path('~/.Trash/')
        else
          #TODO support other OS
          FileUtils.rm_rf selected_items.map(&:path)
        end
      else
        return unless ask %Q[Trashing zip entries is not supported. Actually the files will be deleted. Are you sure want to proceed? (y/n)]
        delete
      end
      @current_row -= selected_items.count {|i| i.index <= current_row}
      ls
    end

    # Delete selected files and directories.
    def delete
      unless in_zip?
        FileUtils.rm_rf selected_items.map(&:path)
      else
        Zip::File.open(current_zip) do |zip|
          zip.select {|e| selected_items.map(&:name).include? e.to_s}.each do |entry|
            if entry.name_is_directory?
              zip.dir.delete entry.to_s
            else
              zip.file.delete entry.to_s
            end
          end
        end
      end
      @current_row -= selected_items.count {|i| i.index <= current_row}
      ls
    end

    # Create a new directory.
    def mkdir(dir)
      unless in_zip?
        FileUtils.mkdir_p current_dir.join(dir)
      else
        Zip::File.open(current_zip) do |zip|
          zip.dir.mkdir dir
        end
      end
      ls
    end

    # Create a new empty file.
    def touch(filename)
      unless in_zip?
        FileUtils.touch current_dir.join(filename)
      else
        Zip::File.open(current_zip) do |zip|
          # zip.file.open(filename, 'w') {|_f| }  #HAXX this code creates an unneeded temporary file
          zip.instance_variable_get(:@entry_set) << Zip::Entry.new(current_zip, filename)
        end
      end

      ls
      move_cursor items.index {|i| i.name == filename}
    end

    # Create a symlink to the current file or directory.
    def symlink(name)
      FileUtils.ln_s current_item, name
      ls
    end

    # Change the timestamp of the selected files and directories.
    #
    # ==== Parameters
    # * +timestamp+ - A string that can be parsed with `Time.parse`. Note that this parameter is not compatible with UNIX `touch -t`.
    def touch_t(timestamp)
      FileUtils.touch selected_items, mtime: Time.parse(timestamp)
      ls
    end

    # Yank selected file / directory names.
    def yank
      @yanked_items = selected_items
    end

    # Paste yanked files / directories here.
    def paste
      if @yanked_items
        if current_item.directory?
          FileUtils.cp_r @yanked_items.map(&:path), current_item
        else
          @yanked_items.each do |item|
            if items.include? item
              i = 0
              while i += 1
                new_path = current_dir.join("#{item.basename}_#{i}#{item.extname}")
                break unless File.exist? new_path
              end
              new_item = new_path
              FileUtils.cp_r item, new_item
            else
              FileUtils.cp_r item, current_dir
            end
          end
        end
        ls
      end
    end

    # Copy selected files and directories' path into clipboard on OSX.
    def clipboard
      IO.popen('pbcopy', 'w') {|f| f << selected_items.map(&:path).join(' ')} if osx?
    end

    # Archive selected files and directories into a .zip file.
    def zip(zipfile_name)
      return unless zipfile_name
      zipfile_name += '.zip' unless zipfile_name.end_with? '.zip'

      Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
        selected_items.each do |item|
          next if item.symlink?
          if item.directory?
            Dir[item.join('**/**')].each do |file|
              zipfile.add file.sub("#{current_dir}/", ''), file
            end
          else
            zipfile.add item.name, item
          end
        end
      end
      ls
    end

    # Unarchive .zip and .tar.gz files within selected files and directories into current_directory.
    def unarchive
      unless in_zip?
        zips, gzs = selected_items.partition(&:zip?).tap {|z, others| break [z, *others.partition(&:gz?)]}
        zips.each do |item|
          dest_dir = current_dir.join(item.basename)
          FileUtils.mkdir_p dest_dir
          Zip::File.open(item) do |zip|
            zip.each do |entry|
              dest_path = safe_extract_path(dest_dir, entry.to_s)
              FileUtils.mkdir_p File.dirname(dest_path)
              zip.extract(entry, dest_path) { true }
            end
          end
        end
        gzs.each do |item|
          Zlib::GzipReader.open(item) do |gz|
            Gem::Package::TarReader.new(gz) do |tar|
              dest_dir = current_dir.join (gz.orig_name || item.basename).sub(/\.tar$/, '')
              tar.each do |entry|
                dest = nil
                if entry.full_name == '././@LongLink'
                  dest = safe_extract_path(dest_dir, entry.read.strip)
                  next
                end
                dest ||= safe_extract_path(dest_dir, entry.full_name)
                if entry.directory?
                  FileUtils.mkdir_p dest, mode: entry.header.mode
                elsif entry.file?
                  FileUtils.mkdir_p File.dirname(dest)
                  File.open(dest, 'wb') {|f| f.print entry.read}
                  FileUtils.chmod entry.header.mode, dest
                elsif entry.header.typeflag == '2'  # symlink
                  File.symlink entry.header.linkname, dest
                end
                unless Dir.exist? dest_dir
                  FileUtils.mkdir_p dest_dir
                  File.open(File.join(dest_dir, gz.orig_name || item.basename), 'wb') {|f| f.print gz.read}
                end
              end
            end
          end
        end
      else
        dest_dir = File.join(current_zip.dir, current_zip.basename)
        Zip::File.open(current_zip) do |zip|
          zip.select {|e| selected_items.map(&:name).include? e.to_s}.each do |entry|
            dest_path = safe_extract_path(dest_dir, entry.to_s)
            FileUtils.mkdir_p File.dirname(dest_path)
            zip.extract(entry, dest_path) { true }
          end
        end
      end
      ls
    end

    private

    def expand_path(path)
      File.expand_path path.start_with?('/', '~') ? path : current_dir ? current_dir.join(path) : path
    end

    # Safely resolve an archive entry path within a destination directory.
    # Prevents path traversal attacks (e.g., ../../etc/passwd).
    def safe_extract_path(dest_dir, entry_name)
      dest_dir = File.expand_path(dest_dir)
      dest_path = File.expand_path(File.join(dest_dir, entry_name))
      raise "Path traversal detected: #{entry_name}" unless dest_path.start_with?(dest_dir + '/')
      dest_path
    end

    def load_item(path: nil, dir: nil, name: nil, stat: nil)
      Item.new dir: dir || File.dirname(path), name: name || File.basename(path), stat: stat, window_width: main.width
    end

    def osx?
      @_osx ||= RbConfig::CONFIG['host_os'] =~ /darwin/
    end

    def in_zip?
      @current_zip
    end
  end
end
