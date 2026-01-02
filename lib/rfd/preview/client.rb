# frozen_string_literal: true

require 'socket'
require 'json'
require 'securerandom'
require_relative 'request'
require_relative 'result'

module Rfd
  module Preview
    # Client interface for communicating with the preview server from the main process
    class Client
      attr_reader :socket_io

      def initialize(socket_path)
        @socket_path = socket_path
        @socket = nil
        @buffer = +''
        @results = Queue.new
        @current_request_id = nil
        @connected = false
      end

      def connect
        return if @connected
        @socket = UNIXSocket.new(@socket_path)
        @socket.sync = true
        @connected = true
        start_reader_thread
      rescue Errno::ENOENT, Errno::ECONNREFUSED
        @connected = false
      end

      def connected?
        @connected
      end

      def socket_io
        @socket
      end

      # Submit a preview request for the given item
      # Returns the request ID
      def request(item:, width:, height:)
        return nil unless @connected

        # Cancel previous request if any
        cancel(@current_request_id) if @current_request_id

        @current_request_id = SecureRandom.uuid
        req = Request.new(
          id: @current_request_id,
          file_path: item.path,
          file_type: item.preview_type,
          width: width,
          height: height
        )
        send_message(req.to_h)
        @current_request_id
      end

      # Cancel an in-flight request
      def cancel(request_id)
        return unless request_id && @connected
        send_message({type: 'cancel', id: request_id})
      end

      # Non-blocking check for available result
      def poll_result
        return nil if @results.empty?
        @results.pop(true)
      rescue ThreadError
        nil
      end

      # Check if there are results ready
      def ready?
        !@results.empty?
      end

      # Blocking wait for result with timeout
      def wait_result(timeout: 5)
        deadline = Time.now + timeout
        while Time.now < deadline
          result = poll_result
          return result if result
          sleep 0.01
        end
        nil
      end

      def shutdown
        return unless @connected
        send_message({type: 'shutdown'})
        @connected = false
        @reader_thread.kill if @reader_thread
        @socket.close rescue nil if @socket
      end

      def close
        @connected = false
        @reader_thread.kill if @reader_thread
        @socket.close rescue nil if @socket
      end

      private

      def send_message(hash)
        return unless @socket && @connected
        # Use non-blocking write to avoid stalling if server is busy
        data = hash.to_json + "\n"
        @socket.write_nonblock(data)
      rescue IO::WaitWritable
        # Socket buffer full, skip this message
        nil
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        @connected = false
      end

      def start_reader_thread
        @reader_thread = Thread.new do
          while @connected
            begin
              readable, = IO.select([@socket], nil, nil, 0.1)
              next unless readable && readable.include?(@socket)

              data = @socket.read_nonblock(4096) rescue nil
              break unless data && !data.empty?

              @buffer << data
              while (idx = @buffer.index("\n"))
                line = @buffer.slice!(0, idx + 1).strip
                next if line.empty?
                process_message(line)
              end
            rescue IOError, Errno::ECONNRESET, EOFError
              break
            end
          end
          @connected = false
        end
      end

      def process_message(line)
        hash = JSON.parse(line)
        if hash['type'] == 'result'
          result = Result.from_hash(hash)
          @results << result
        end
      rescue JSON::ParserError
        # Ignore malformed messages
      end
    end
  end
end
