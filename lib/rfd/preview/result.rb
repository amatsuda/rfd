# frozen_string_literal: true

module Rfd
  module Preview
    # Value object representing a preview generation result
    class Result
      attr_reader :request_id, :status, :file_type, :lines, :thumbnail_path, :metadata, :error

      def initialize(request_id:, status:, file_type: nil, lines: nil, thumbnail_path: nil, metadata: nil, error: nil)
        @request_id = request_id
        @status = status.to_sym
        @file_type = file_type && file_type.to_sym
        @lines = lines
        @thumbnail_path = thumbnail_path
        @metadata = metadata
        @error = error
      end

      def success?
        @status == :success
      end

      def error?
        @status == :error
      end

      def cancelled?
        @status == :cancelled
      end

      def to_h
        hash = {
          type: 'result',
          id: @request_id,
          status: @status.to_s
        }
        hash[:file_type] = @file_type.to_s if @file_type
        hash[:lines] = @lines if @lines
        hash[:thumbnail_path] = @thumbnail_path if @thumbnail_path
        hash[:metadata] = @metadata if @metadata
        hash[:error] = @error if @error
        hash
      end

      def self.from_hash(hash)
        new(
          request_id: hash['id'],
          status: hash['status'],
          file_type: hash['file_type'],
          lines: hash['lines'],
          thumbnail_path: hash['thumbnail_path'],
          metadata: hash['metadata'],
          error: hash['error']
        )
      end

      def self.success(request_id:, file_type:, lines: nil, thumbnail_path: nil, metadata: nil)
        new(request_id: request_id, status: :success, file_type: file_type, lines: lines, thumbnail_path: thumbnail_path, metadata: metadata)
      end

      def self.error(request_id:, error:)
        new(request_id: request_id, status: :error, error: error)
      end

      def self.cancelled(request_id:)
        new(request_id: request_id, status: :cancelled)
      end
    end
  end
end
