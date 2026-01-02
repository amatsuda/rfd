# frozen_string_literal: true

module Rfd
  module Bookmark
    CONFIG_DIR = File.join(ENV.fetch('XDG_CONFIG_HOME') { File.expand_path('~/.config') }, 'rfd')
    BOOKMARK_FILE = File.join(CONFIG_DIR, 'bookmarks')

    @bookmarks = []

    class << self
      attr_accessor :bookmarks

      def add(path)
        path = File.expand_path(path)
        return if @bookmarks.include?(path)

        @bookmarks << path
        save
      end

      def remove(path)
        path = File.expand_path(path)
        @bookmarks.delete(path)
        save
      end

      def include?(path)
        @bookmarks.include?(File.expand_path(path))
      end

      def toggle(path)
        if include?(path)
          remove(path)
        else
          add(path)
        end
      end

      def load
        return unless File.exist?(BOOKMARK_FILE)

        @bookmarks = File.readlines(BOOKMARK_FILE, chomp: true)
          .map { |line| File.expand_path(line) }
          .select { |path| File.directory?(path) }
      rescue Errno::EACCES, Errno::ENOENT
        @bookmarks = []
      end

      def save
        dir = File.dirname(BOOKMARK_FILE)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(BOOKMARK_FILE, @bookmarks.join("\n") + "\n")
      rescue Errno::EACCES, Errno::ENOENT
        # Silently fail if we can't write
      end
    end
  end
end
