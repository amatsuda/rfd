# frozen_string_literal: true

require 'socket'
require 'json'
require 'tmpdir'
require 'timeout'
require 'rouge'
require_relative 'request'
require_relative 'result'

module Rfd
  module Preview
    # Forked process that handles preview generation asynchronously
    class Server
      TIMEOUT = (ENV['RFD_PREVIEW_TIMEOUT'] || 10).to_i
      WORKERS = (ENV['RFD_PREVIEW_WORKERS'] || 2).to_i

      def initialize(socket_path)
        @socket_path = socket_path
        @cancelled = {}
        @cancelled_mutex = Mutex.new
        @queue = Queue.new
        @running = true
      end

      def run
        cleanup_socket
        server = UNIXServer.new(@socket_path)
        @client_socket = nil
        @client_mutex = Mutex.new

        # Start worker threads
        workers = WORKERS.times.map { Thread.new { worker_loop } }

        # Main loop: accept connection and read requests
        while @running
          begin
            readable, = IO.select([server], nil, nil, 0.5)
            next unless readable && readable.include?(server)

            client = server.accept
            @client_mutex.synchronize { @client_socket = client }

            Thread.new(client) do |c|
              handle_client(c)
            end
          rescue IOError, Errno::EBADF
            break
          end
        end
      rescue => e
        STDERR.puts "Preview::Server error: #{e.message}"
      ensure
        @running = false
        WORKERS.times { @queue << :shutdown }
        workers.each(&:join) if workers
        server.close if server
        cleanup_socket
      end

      private

      def cleanup_socket
        File.unlink(@socket_path) if File.exist?(@socket_path)
      end

      def handle_client(client)
        buffer = +''
        while @running && (data = client.gets)
          buffer << data
          while (idx = buffer.index("\n"))
            line = buffer.slice!(0, idx + 1).strip
            next if line.empty?
            process_message(line, client)
          end
        end
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        # Client disconnected
      ensure
        @client_mutex.synchronize { @client_socket = nil if @client_socket == client }
        client.close rescue nil
      end

      def process_message(line, client)
        message = JSON.parse(line)
        case message['type']
        when 'request'
          request = Request.from_hash(message)
          @queue << [request, client]
        when 'cancel'
          @cancelled_mutex.synchronize { @cancelled[message['id']] = true }
        when 'shutdown'
          @running = false
        end
      rescue JSON::ParserError => e
        STDERR.puts "Preview::Server JSON error: #{e.message}"
      end

      def worker_loop
        while (item = @queue.pop)
          break if item == :shutdown
          request, client = item
          next if cancelled?(request.id)

          result = generate_preview(request)
          send_result(result, client) unless cancelled?(request.id)
          cleanup_cancelled(request.id)
        end
      end

      def cancelled?(request_id)
        @cancelled_mutex.synchronize { @cancelled[request_id] }
      end

      def cleanup_cancelled(request_id)
        @cancelled_mutex.synchronize { @cancelled.delete(request_id) }
      end

      def send_result(result, client)
        @client_mutex.synchronize do
          return unless @client_socket
          @client_socket.puts(result.to_h.to_json)
        end
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        # Client gone
      end

      def generate_preview(request)
        case request.file_type
        when :directory
          generate_directory_preview(request)
        when :text, :code
          generate_text_preview(request)
        when :markdown
          generate_markdown_preview(request)
        when :video
          generate_video_preview(request)
        when :pdf
          generate_pdf_preview(request)
        when :heic
          generate_heic_preview(request)
        when :image
          # Images are displayed directly by main process
          Result.success(request_id: request.id, file_type: :image)
        else
          generate_text_preview(request)
        end
      rescue => e
        Result.error(request_id: request.id, error: e.message)
      end

      def generate_directory_preview(request)
        entries = Dir.children(request.file_path).sort.first(request.height - 2) rescue []
        lines = entries.map { |name| {text: name[0, request.width], attrs: []} }
        Result.success(request_id: request.id, file_type: :directory, lines: lines)
      end

      def generate_text_preview(request)
        content = File.read(request.file_path, encoding: 'UTF-8', invalid: :replace, undef: :replace) rescue nil
        if content.nil? || content.include?("\x00")
          return Result.success(
            request_id: request.id,
            file_type: :binary,
            lines: [{text: '[Binary file]', attrs: [], center: true}]
          )
        end

        # Try syntax highlighting
        lexer = Rouge::Lexer.guess(filename: File.basename(request.file_path), source: content) rescue nil
        if lexer && !lexer.is_a?(Rouge::Lexers::PlainText)
          lines = generate_highlighted_lines(content, lexer, request.width, request.height - 2)
          Result.success(request_id: request.id, file_type: :code, lines: lines)
        else
          lines = content.lines.first(request.height - 2).map do |line|
            {text: line.chomp[0, request.width], attrs: []}
          end
          Result.success(request_id: request.id, file_type: :text, lines: lines)
        end
      end

      def generate_highlighted_lines(content, lexer, max_width, max_lines)
        tokens = lexer.lex(content)
        lines = []
        current_line = []
        col = 0

        tokens.each do |token_type, token_text|
          break if lines.size >= max_lines
          color = rouge_token_color(token_type)

          token_text.each_char do |c|
            break if lines.size >= max_lines
            if c == "\n"
              lines << {segments: current_line}
              current_line = []
              col = 0
            else
              next if col >= max_width
              current_line << {char: c, color: color}
              col += 1
            end
          end
        end
        lines << {segments: current_line} if current_line.any? && lines.size < max_lines
        lines
      end

      ROUGE_COLORS = {
        'Comment' => 'green',
        'Keyword' => 'cyan',
        'Name.Function' => 'magenta',
        'Name.Class' => 'magenta',
        'Literal.String' => 'red',
        'Literal.Number' => 'red',
        'Operator' => 'cyan',
      }.freeze

      def rouge_token_color(token_type)
        token_str = token_type.qualname
        ROUGE_COLORS.each do |prefix, color|
          return color if token_str.start_with?(prefix)
        end
        nil
      end

      def generate_markdown_preview(request)
        content = File.read(request.file_path, encoding: 'UTF-8', invalid: :replace, undef: :replace) rescue ''
        lines = content.lines.first(request.height - 2).map do |line|
          text = line.chomp
          attr = if text.start_with?('#')
            'bold'
          elsif text =~ /^```/ || text.start_with?('    ')
            'green'
          elsif text =~ /^[-*+] /
            'cyan'
          else
            nil
          end
          {text: text[0, request.width], attrs: [attr].compact}
        end
        Result.success(request_id: request.id, file_type: :markdown, lines: lines)
      end

      def generate_video_preview(request)
        return Result.error(request_id: request.id, error: 'File not found') unless File.exist?(request.file_path)

        metadata = extract_video_metadata(request.file_path)
        thumbnail = extract_video_thumbnail(request.file_path, request.id)

        Result.success(
          request_id: request.id,
          file_type: :video,
          thumbnail_path: thumbnail,
          metadata: metadata
        )
      end

      def extract_video_metadata(path)
        output = Timeout.timeout(TIMEOUT) do
          IO.popen(['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', path], err: '/dev/null') { |io| io.read }
        end
        data = JSON.parse(output)
        result = {}

        if (format = data['format'])
          if (duration = format['duration'])
            secs = duration.to_f
            result[:duration] = sprintf('%d:%02d:%02d', secs / 3600, (secs % 3600) / 60, secs % 60)
          end
          result[:size] = "#{(format['size'].to_i / 1024.0 / 1024).round(1)} MB" if format['size']
        end

        if (streams = data['streams'])
          if (video = streams.find { |s| s['codec_type'] == 'video' })
            result[:resolution] = "#{video['width']}x#{video['height']}"
            result[:codec] = video['codec_name'] && video['codec_name'].upcase
            if video['r_frame_rate']
              n, d = video['r_frame_rate'].split('/')
              result[:fps] = (n.to_f / d.to_f).round(1) if d.to_f > 0
            end
          end
          if (audio = streams.find { |s| s['codec_type'] == 'audio' })
            result[:audio] = "#{audio['codec_name'] && audio['codec_name'].upcase} #{audio['channels']}ch"
          end
        end
        result
      rescue
        {}
      end

      def extract_video_thumbnail(path, request_id)
        tmpfile = File.join(Dir.tmpdir, "rfd_video_thumb_#{request_id}.png")
        # Use timeout to prevent hanging on problematic files
        pid = spawn('ffmpeg', '-y', '-i', path, '-ss', '00:00:01', '-vframes', '1', '-q:v', '2', tmpfile,
                    out: '/dev/null', err: '/dev/null')
        begin
          Timeout.timeout(TIMEOUT) { Process.wait(pid) }
          $?.success? ? tmpfile : nil
        rescue Timeout::Error
          Process.kill('TERM', pid) rescue nil
          Process.wait(pid) rescue nil
          nil
        end
      end

      def generate_pdf_preview(request)
        return Result.error(request_id: request.id, error: 'File not found') unless File.exist?(request.file_path)

        thumbnail = extract_pdf_thumbnail(request.file_path, request.id, request.height)
        if thumbnail
          Result.success(request_id: request.id, file_type: :pdf, thumbnail_path: thumbnail)
        else
          # Fallback to text extraction
          lines = extract_pdf_text(request.file_path, request.height - 2, request.width)
          if lines && lines.any?
            Result.success(request_id: request.id, file_type: :pdf_text, lines: lines)
          else
            Result.success(
              request_id: request.id,
              file_type: :pdf,
              lines: [{text: '[PDF file]', attrs: [], center: true}]
            )
          end
        end
      end

      def extract_pdf_thumbnail(path, request_id, height)
        tmpfile = File.join(Dir.tmpdir, "rfd_pdf_thumb_#{request_id}")
        if system('pdftoppm', '-png', '-f', '1', '-l', '1', '-singlefile', '-scale-to', (height * 15).to_s, path, tmpfile, out: '/dev/null', err: '/dev/null')
          "#{tmpfile}.png"
        elsif system('convert', '-density', '100', "#{path}[0]", '-resize', "x#{height * 15}", "#{tmpfile}.png", out: '/dev/null', err: '/dev/null')
          "#{tmpfile}.png"
        else
          nil
        end
      end

      def extract_pdf_text(path, max_lines, max_width)
        IO.popen(['pdftotext', '-l', '1', '-layout', path, '-'], err: '/dev/null') do |io|
          io.read.lines.first(max_lines).map do |line|
            {text: line.chomp[0, max_width], attrs: []}
          end
        end
      rescue
        nil
      end

      def generate_heic_preview(request)
        return Result.error(request_id: request.id, error: 'File not found') unless File.exist?(request.file_path)

        thumbnail = convert_heic_to_png(request.file_path, request.id)
        if thumbnail
          Result.success(request_id: request.id, file_type: :heic, thumbnail_path: thumbnail)
        else
          Result.success(
            request_id: request.id,
            file_type: :heic,
            lines: [{text: '[HEIC file]', attrs: [], center: true}]
          )
        end
      end

      def convert_heic_to_png(path, request_id)
        tmpfile = File.join(Dir.tmpdir, "rfd_heic_thumb_#{request_id}.png")
        # Try sips (macOS), heif-convert (libheif), or ImageMagick
        pid = nil
        begin
          if osx?
            pid = spawn('sips', '-s', 'format', 'png', path, '--out', tmpfile, out: '/dev/null', err: '/dev/null')
          else
            pid = spawn('heif-convert', path, tmpfile, out: '/dev/null', err: '/dev/null')
          end
          Timeout.timeout(TIMEOUT) { Process.wait(pid) }
          return tmpfile if $?.success? && File.exist?(tmpfile)

          # Try fallback converters
          pid = spawn('convert', path, tmpfile, out: '/dev/null', err: '/dev/null')
          Timeout.timeout(TIMEOUT) { Process.wait(pid) }
          return tmpfile if $?.success? && File.exist?(tmpfile)

          nil
        rescue Timeout::Error
          Process.kill('TERM', pid) rescue nil
          Process.wait(pid) rescue nil
          nil
        end
      end

      def osx?
        RUBY_PLATFORM.include?('darwin')
      end
    end
  end
end
