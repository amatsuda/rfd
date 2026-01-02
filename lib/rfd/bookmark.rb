# frozen_string_literal: true

module Rfd
  module Bookmark
    @bookmarks = []

    class << self
      attr_accessor :bookmarks

      def add(path)
        path = File.expand_path(path)
        @bookmarks << path unless @bookmarks.include?(path)
      end

      def remove(path)
        path = File.expand_path(path)
        @bookmarks.delete(path)
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
    end
  end
end
