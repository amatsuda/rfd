# frozen_string_literal: true

module Rfd
  module Preview
    # Value object representing a preview generation request
    class Request
      attr_reader :id, :file_path, :file_type, :width, :height, :timestamp

      def initialize(id:, file_path:, file_type:, width:, height:)
        @id = id
        @file_path = file_path
        @file_type = file_type
        @width = width
        @height = height
        @timestamp = Time.now.to_f
      end

      def to_h
        {
          type: 'request',
          id: @id,
          path: @file_path,
          file_type: @file_type,
          width: @width,
          height: @height
        }
      end

      def self.from_hash(hash)
        new(
          id: hash['id'],
          file_path: hash['path'],
          file_type: hash['file_type'] && hash['file_type'].to_sym,
          width: hash['width'],
          height: hash['height']
        )
      end
    end
  end
end
