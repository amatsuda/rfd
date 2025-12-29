# frozen_string_literal: true
module Rfd
  class Item
    include Comparable
    attr_reader :name, :dir, :stat
    attr_accessor :index

    def initialize(path: nil, dir: nil, name: nil, stat: nil, window_width: nil)
      @path, @dir, @name, @stat, @window_width, @marked = path, dir || File.dirname(path), name || File.basename(path), stat, window_width, false
      @stat = File.lstat self.path unless stat
    end

    def path
      @path ||= File.join @dir, @name
    end

    def basename
      @basename ||= File.basename name, extname
    end

    def extname
      @extname ||= File.extname name
    end

    def join(*ary)
      File.join path, ary
    end

    def full_display_name
      n = @name.dup
      n << " -> #{target}" if symlink?
      n
    end

    def display_name
      @display_name ||= begin
        n = full_display_name
        if mb_size(n) <= @window_width - 15
          n
        elsif symlink?
          mb_left n, @window_width - 16
        else
          "#{mb_left(basename, @window_width - 16 - extname.size)}…#{extname}"
        end
      end
    end

    def color
      if symlink?
        Curses::COLOR_MAGENTA
      elsif hidden?
        Curses::COLOR_GREEN
      elsif directory?
        Curses::COLOR_CYAN
      elsif executable?
        Curses::COLOR_RED
      else
        Curses::COLOR_WHITE
      end
    end

    def size
      directory? ? 0 : stat.size
    end

    def size_or_dir
      directory? ? '<DIR>' : size.to_s
    end

    def atime
      stat.atime.strftime('%Y-%m-%d %H:%M:%S')
    end

    def ctime
      stat.ctime.strftime('%Y-%m-%d %H:%M:%S')
    end

    def mtime
      stat.mtime.strftime('%Y-%m-%d %H:%M:%S')
    end

    def mode
      @mode ||= begin
        m = stat.mode
        ft = directory? ? 'd' : symlink? ? 'l' : '-'
        owner = (m >> 6) & 07
        group = (m >> 3) & 07
        other = m & 07
        ret = [owner, group, other].inject(ft) do |str, perms|
          str + "#{perms & 4 != 0 ? 'r' : '-'}#{perms & 2 != 0 ? 'w' : '-'}#{perms & 1 != 0 ? 'x' : '-'}"
        end
        # setuid: 's' if execute set, 'S' if not
        ret[3] = (owner & 1 != 0 ? 's' : 'S') if m & 04000 != 0
        # setgid: 's' if execute set, 'S' if not
        ret[6] = (group & 1 != 0 ? 's' : 'S') if m & 02000 != 0
        # sticky: 't' if execute set, 'T' if not
        ret[9] = (other & 1 != 0 ? 't' : 'T') if m & 01000 != 0
        ret
      end
    end

    def directory?
      @directory ||= if symlink?
        begin
          File.stat(path).directory?
        rescue Errno::ENOENT
          false
        end
      else
        stat.directory?
      end
    end

    def symlink?
      stat.symlink?
    end

    def hidden?
      name.start_with?('.') && (name != '.') && (name != '..')
    end

    def executable?
      stat.executable?
    end

    def zip?
      @zip_ ||= begin
        if directory?
          false
        else
          File.binread(realpath, 4).unpack('V').first == 0x04034b50
        end
      rescue
        false
      end
    end

    def gz?
      @gz_ ||= begin
        if directory?
          false
        else
          File.binread(realpath, 2).unpack('n').first == 0x1f8b
        end
      rescue
        false
      end
    end

    def image?
      @image ||= begin
        return false if directory?
        return true if svg?
        magic = File.binread(realpath, 12).bytes
        (magic[0..3] == [0x89, 0x50, 0x4E, 0x47]) ||  # PNG
          (magic[0..2] == [0xFF, 0xD8, 0xFF]) ||      # JPEG
          (magic[0..2] == [0x47, 0x49, 0x46]) ||      # GIF
          (magic[0..3] == [0x52, 0x49, 0x46, 0x46] && magic[8..11] == [0x57, 0x45, 0x42, 0x50])  # WebP (RIFF....WEBP)
      rescue
        false
      end
    end

    def svg?
      @svg ||= begin
        return false if directory?
        return true if extname.downcase == '.svg'
        # Check content for <svg tag
        content = File.binread(realpath, 256)
        content.include?('<svg')
      rescue
        false
      end
    end

    def target
      File.readlink path if symlink?
    end

    def realpath
      @realpath ||= File.realpath path
    end

    def toggle_mark
      unless %w(. ..).include? name
        @marked = !@marked
        true
      end
    end

    def marked?
      @marked
    end

    def current_mark
      marked? ? '*' : ' '
    end

    def mb_left(str, size)
      len = 0
      index = str.each_char.with_index do |c, i|
        break i if len + mb_char_size(c) > size
        len += mb_size c
      end
      str[0, index]
    end

    def mb_char_size(c)
      c == '…' ? 1 : c.bytesize == 1 ? 1 : 2
    end

    def mb_size(str)
      str.each_char.inject(0) {|l, c| l += mb_char_size(c)}
    end

    def mb_ljust(str, size)
      "#{str}#{' ' * [0, size - mb_size(str)].max}"
    end

    def to_s
      "#{current_mark}#{mb_ljust(display_name, @window_width - 15)}#{size_or_dir.rjust(13)}"
    end

    def to_str
      path
    end

    def <=>(o)
      if directory? && !o.directory?
        1
      elsif !directory? && o.directory?
        -1
      else
        name <=> o.name
      end
    end
  end
end
