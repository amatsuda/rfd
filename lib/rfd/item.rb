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
        offset = ENV['RFD_NO_ICONS'] ? 15 : 18
        if mb_size(n) <= @window_width - offset
          n
        elsif symlink?
          mb_left n, @window_width - offset - 1
        else
          "#{mb_left(basename, @window_width - offset - 1 - extname.size)}…#{extname}"
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

    def archive?
      zip? || gz?
    end

    def image?
      @image ||= begin
        return false if directory?
        return true if svg?
        return true if heic?
        magic = File.binread(realpath, 12).bytes
        (magic[0..3] == [0x89, 0x50, 0x4E, 0x47]) ||  # PNG
          (magic[0..2] == [0xFF, 0xD8, 0xFF]) ||      # JPEG
          (magic[0..2] == [0x47, 0x49, 0x46]) ||      # GIF
          (magic[0..3] == [0x52, 0x49, 0x46, 0x46] && magic[8..11] == [0x57, 0x45, 0x42, 0x50])  # WebP (RIFF....WEBP)
      rescue
        false
      end
    end

    def heic?
      @heic ||= begin
        return false if directory?
        return true if %w[.heic .heif].include?(extname.downcase)
        magic = File.binread(realpath, 12).bytes
        magic[4..7] == [0x66, 0x74, 0x79, 0x70]  # "ftyp" at offset 4
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

    def pdf?
      @pdf ||= begin
        return false if directory?
        magic = File.binread(realpath, 4).bytes
        magic == [0x25, 0x50, 0x44, 0x46]  # %PDF
      rescue
        false
      end
    end

    def markdown?
      !directory? && %w[.md .markdown].include?(extname.downcase)
    end

    def audio?
      !directory? && %w[.mp3 .wav .flac .ogg .m4a .aac .aiff .wma].include?(extname.downcase)
    end

    def video?
      !directory? && %w[.mp4 .avi .mov .mkv .webm .flv .wmv .m4v .mpeg .mpg].include?(extname.downcase)
    end

    # Returns the preview type symbol for the preview server
    #
    # Order matters here:
    # - video? must come before heic? because MOV/MP4 files share the same
    #   "ftyp" magic bytes at offset 4 that heic? checks for
    # - heic? must come before image? because HEIC conversion is slow and
    #   needs async handling, while other image formats can be displayed directly
    def preview_type
      return :directory if directory?
      return :video if video?
      return :heic if heic?
      return :image if image?
      return :pdf if pdf?
      return :markdown if markdown?
      :text
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

    # Nerd Font icons (requires Nerd Font installed)
    ICON_DIRECTORY = "\uf07c"  #
    ICON_SYMLINK   = "\uf0c1"  #
    ICON_EXEC      = "\uf013"  #
    ICON_FILE      = "\uf15b"  #
    ICON_RUBY      = "\ue791"  #
    ICON_PYTHON    = "\ue73c"  #
    ICON_JS        = "\ue74e"  #
    ICON_TS        = "\ue628"  #
    ICON_HTML      = "\ue736"  #
    ICON_CSS       = "\ue749"  #
    ICON_JSON      = "\ue60b"  #
    ICON_MARKDOWN  = "\ue73e"  #
    ICON_SHELL     = "\uf489"  #
    ICON_C         = "\ue61e"  #
    ICON_CPP       = "\ue61d"  #
    ICON_GO        = "\ue626"  #
    ICON_RUST      = "\ue7a8"  #
    ICON_JAVA      = "\ue738"  #
    ICON_PHP       = "\ue73d"  #
    ICON_SWIFT     = "\ue755"  #
    ICON_VIM       = "\ue62b"  #
    ICON_LUA       = "\ue620"  #
    ICON_SQL       = "\uf1c0"  #
    ICON_PDF       = "\uf1c1"  #
    ICON_ARCHIVE   = "\uf1c6"  #
    ICON_IMAGE     = "\uf1c5"  #
    ICON_AUDIO     = "\uf1c7"  #
    ICON_VIDEO     = "\uf1c8"  #
    ICON_FONT      = "\uf031"  #
    ICON_LOCK      = "\uf023"  #
    ICON_CONFIG    = "\ue615"  #
    ICON_LOG       = "\uf18d"  #

    FILE_ICONS = {
      '.rb' => ICON_RUBY, '.rake' => ICON_RUBY, '.gemspec' => ICON_RUBY,
      '.py' => ICON_PYTHON, '.pyc' => ICON_PYTHON,
      '.js' => ICON_JS, '.mjs' => ICON_JS, '.cjs' => ICON_JS, '.jsx' => ICON_JS,
      '.ts' => ICON_TS, '.tsx' => ICON_TS,
      '.html' => ICON_HTML, '.htm' => ICON_HTML,
      '.css' => ICON_CSS, '.scss' => ICON_CSS, '.sass' => ICON_CSS,
      '.json' => ICON_JSON, '.yaml' => ICON_CONFIG, '.yml' => ICON_CONFIG,
      '.md' => ICON_MARKDOWN, '.markdown' => ICON_MARKDOWN,
      '.sh' => ICON_SHELL, '.bash' => ICON_SHELL, '.zsh' => ICON_SHELL,
      '.c' => ICON_C, '.h' => ICON_C,
      '.cpp' => ICON_CPP, '.hpp' => ICON_CPP, '.cc' => ICON_CPP,
      '.go' => ICON_GO,
      '.rs' => ICON_RUST,
      '.java' => ICON_JAVA, '.jar' => ICON_JAVA,
      '.php' => ICON_PHP,
      '.swift' => ICON_SWIFT,
      '.vim' => ICON_VIM,
      '.lua' => ICON_LUA,
      '.sql' => ICON_SQL,
      '.pdf' => ICON_PDF,
      '.zip' => ICON_ARCHIVE, '.tar' => ICON_ARCHIVE, '.gz' => ICON_ARCHIVE, '.rar' => ICON_ARCHIVE, '.7z' => ICON_ARCHIVE,
      '.png' => ICON_IMAGE, '.jpg' => ICON_IMAGE, '.jpeg' => ICON_IMAGE, '.gif' => ICON_IMAGE, '.svg' => ICON_IMAGE, '.webp' => ICON_IMAGE, '.ico' => ICON_IMAGE, '.heic' => ICON_IMAGE, '.heif' => ICON_IMAGE,
      '.mp3' => ICON_AUDIO, '.wav' => ICON_AUDIO, '.flac' => ICON_AUDIO, '.ogg' => ICON_AUDIO,
      '.mp4' => ICON_VIDEO, '.avi' => ICON_VIDEO, '.mov' => ICON_VIDEO, '.mkv' => ICON_VIDEO, '.webm' => ICON_VIDEO,
      '.ttf' => ICON_FONT, '.otf' => ICON_FONT, '.woff' => ICON_FONT,
      '.lock' => ICON_LOCK,
      '.env' => ICON_CONFIG,
      '.log' => ICON_LOG,
    }.freeze

    def icon
      return '' if ENV['RFD_NO_ICONS']
      return ICON_DIRECTORY if directory?
      return ICON_SYMLINK if symlink?
      return ICON_EXEC if executable?
      FILE_ICONS[extname.downcase] || ICON_FILE
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
      if ENV['RFD_NO_ICONS']
        "#{current_mark}#{mb_ljust(display_name, @window_width - 15)}#{size_or_dir.rjust(13)}"
      else
        "#{current_mark}#{icon} #{mb_ljust(display_name, @window_width - 18)}#{size_or_dir.rjust(13)}"
      end
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
