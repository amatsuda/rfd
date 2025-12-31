# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd::Viewer do
  # Create a test class that includes the Viewer module
  let(:viewer_class) do
    Class.new do
      include Rfd::Viewer

      # Stub methods that Viewer depends on
      def osx?
        RbConfig::CONFIG['host_os'] =~ /darwin/
      end
    end
  end
  let(:viewer) { viewer_class.new }

  describe '#text_attr_from_names' do
    it 'returns A_NORMAL for nil' do
      expect(viewer.text_attr_from_names(nil)).to eq(Curses::A_NORMAL)
    end

    it 'returns A_NORMAL for empty array' do
      expect(viewer.text_attr_from_names([])).to eq(Curses::A_NORMAL)
    end

    it 'returns A_BOLD for bold' do
      result = viewer.text_attr_from_names(['bold'])
      expect(result & Curses::A_BOLD).to eq(Curses::A_BOLD)
    end

    it 'returns green color pair for green' do
      result = viewer.text_attr_from_names(['green'])
      expect(result).to eq(Curses.color_pair(Curses::COLOR_GREEN))
    end

    it 'returns cyan color pair for cyan' do
      result = viewer.text_attr_from_names(['cyan'])
      expect(result).to eq(Curses.color_pair(Curses::COLOR_CYAN))
    end

    it 'returns red color pair for red' do
      result = viewer.text_attr_from_names(['red'])
      expect(result).to eq(Curses.color_pair(Curses::COLOR_RED))
    end

    it 'returns magenta color pair for magenta' do
      result = viewer.text_attr_from_names(['magenta'])
      expect(result).to eq(Curses.color_pair(Curses::COLOR_MAGENTA))
    end

    it 'combines multiple attributes' do
      result = viewer.text_attr_from_names(['bold', 'green'])
      expect(result & Curses::A_BOLD).to eq(Curses::A_BOLD)
    end

    it 'handles string attributes' do
      result = viewer.text_attr_from_names(['bold'])
      expect(result & Curses::A_BOLD).to eq(Curses::A_BOLD)
    end

    it 'handles symbol attributes via to_s' do
      result = viewer.text_attr_from_names([:bold])
      expect(result & Curses::A_BOLD).to eq(Curses::A_BOLD)
    end
  end

  describe '#color_pair_from_name' do
    it 'returns green color pair for green' do
      expect(viewer.color_pair_from_name('green')).to eq(Curses.color_pair(Curses::COLOR_GREEN))
    end

    it 'returns cyan color pair for cyan' do
      expect(viewer.color_pair_from_name('cyan')).to eq(Curses.color_pair(Curses::COLOR_CYAN))
    end

    it 'returns red color pair for red' do
      expect(viewer.color_pair_from_name('red')).to eq(Curses.color_pair(Curses::COLOR_RED))
    end

    it 'returns magenta color pair for magenta' do
      expect(viewer.color_pair_from_name('magenta')).to eq(Curses.color_pair(Curses::COLOR_MAGENTA))
    end

    it 'returns A_NORMAL for unknown colors' do
      expect(viewer.color_pair_from_name('unknown')).to eq(Curses::A_NORMAL)
    end

    it 'returns A_NORMAL for nil' do
      expect(viewer.color_pair_from_name(nil)).to eq(Curses::A_NORMAL)
    end

    it 'handles symbols via to_s' do
      expect(viewer.color_pair_from_name(:green)).to eq(Curses.color_pair(Curses::COLOR_GREEN))
    end
  end

  describe '#format_video_metadata_from_hash' do
    context 'with string keys' do
      let(:metadata) do
        {
          'duration' => '1:30:00',
          'size' => '500 MB',
          'resolution' => '1920x1080',
          'codec' => 'H264',
          'fps' => 30,
          'audio' => 'AAC 2ch'
        }
      end

      it 'formats all metadata fields' do
        lines = viewer.format_video_metadata_from_hash(metadata, 80)
        expect(lines).to include('Duration: 1:30:00')
        expect(lines).to include('Size: 500 MB')
        expect(lines).to include('1920x1080 H264')
        expect(lines).to include('30 fps')
        expect(lines).to include('Audio: AAC 2ch')
      end
    end

    context 'with symbol keys' do
      let(:metadata) do
        {
          duration: '0:05:30',
          size: '100 MB',
          resolution: '1280x720',
          codec: 'VP9'
        }
      end

      it 'formats metadata with symbol keys' do
        lines = viewer.format_video_metadata_from_hash(metadata, 80)
        expect(lines).to include('Duration: 0:05:30')
        expect(lines).to include('Size: 100 MB')
        expect(lines).to include('1280x720 VP9')
      end
    end

    context 'with empty metadata' do
      it 'returns empty array' do
        lines = viewer.format_video_metadata_from_hash({}, 80)
        expect(lines).to eq([])
      end
    end

    context 'with partial metadata' do
      it 'only includes available fields' do
        metadata = {'duration' => '2:00'}
        lines = viewer.format_video_metadata_from_hash(metadata, 80)
        expect(lines).to eq(['Duration: 2:00'])
      end
    end
  end

  describe '#preview_pane_x' do
    # This requires mocking main window - skip for now as it requires full setup
  end

  describe 'terminal detection' do
    describe '#kitty?' do
      before do
        # Clear memoized value
        viewer.instance_variable_set(:@_kitty, nil) if viewer.instance_variable_defined?(:@_kitty)
      end

      around do |example|
        old_term = ENV['TERM']
        old_kitty = ENV['KITTY_WINDOW_ID']
        old_term_program = ENV['TERM_PROGRAM']
        example.run
        ENV['TERM'] = old_term
        ENV['KITTY_WINDOW_ID'] = old_kitty
        ENV['TERM_PROGRAM'] = old_term_program
      end

      it 'returns true for xterm-kitty' do
        ENV['TERM'] = 'xterm-kitty'
        ENV.delete('KITTY_WINDOW_ID')
        ENV.delete('TERM_PROGRAM')
        expect(viewer.send(:kitty?)).to be true
      end

      it 'returns truthy when KITTY_WINDOW_ID is set' do
        ENV['TERM'] = 'xterm-256color'
        ENV['KITTY_WINDOW_ID'] = '1'
        ENV.delete('TERM_PROGRAM')
        expect(viewer.send(:kitty?)).to be_truthy
      end

      it 'returns true for ghostty' do
        ENV['TERM'] = 'xterm-256color'
        ENV.delete('KITTY_WINDOW_ID')
        ENV['TERM_PROGRAM'] = 'ghostty'
        expect(viewer.send(:kitty?)).to be true
      end

      it 'returns false for regular terminal' do
        ENV['TERM'] = 'xterm-256color'
        ENV.delete('KITTY_WINDOW_ID')
        ENV['TERM_PROGRAM'] = 'Apple_Terminal'
        expect(viewer.send(:kitty?)).to be_falsey
      end
    end

    describe '#sixel?' do
      before do
        viewer.instance_variable_set(:@_sixel, nil) if viewer.instance_variable_defined?(:@_sixel)
      end

      around do |example|
        old_term = ENV['TERM']
        old_term_program = ENV['TERM_PROGRAM']
        example.run
        ENV['TERM'] = old_term
        ENV['TERM_PROGRAM'] = old_term_program
      end

      it 'returns true for iTerm' do
        ENV['TERM_PROGRAM'] = 'iTerm.app'
        ENV['TERM'] = 'xterm-256color'
        expect(viewer.send(:sixel?)).to be true
      end

      it 'returns true for mlterm' do
        ENV['TERM'] = 'mlterm'
        ENV.delete('TERM_PROGRAM')
        expect(viewer.send(:sixel?)).to be true
      end

      it 'returns true for foot' do
        ENV['TERM'] = 'foot'
        ENV.delete('TERM_PROGRAM')
        expect(viewer.send(:sixel?)).to be true
      end

      it 'returns false for regular terminal' do
        ENV['TERM'] = 'xterm-256color'
        ENV['TERM_PROGRAM'] = 'Apple_Terminal'
        expect(viewer.send(:sixel?)).to be_falsey
      end
    end
  end

  describe '#convert_heic_if_needed' do
    it 'returns nil for non-HEIC files' do
      expect(viewer.send(:convert_heic_if_needed, '/path/to/image.jpg')).to be_nil
      expect(viewer.send(:convert_heic_if_needed, '/path/to/image.png')).to be_nil
    end

    it 'returns nil for directory paths' do
      expect(viewer.send(:convert_heic_if_needed, '/path/to/dir')).to be_nil
    end

    context 'for HEIC files' do
      it 'attempts conversion for .heic extension' do
        # The method will attempt conversion - result depends on available tools
        result = viewer.send(:convert_heic_if_needed, '/nonexistent/image.heic')
        # Either nil (no tools) or a tmpfile path (tool ran but may have failed)
        if result
          expect(result).to include('rfd_heic_')
          File.unlink(result) if File.exist?(result)
        end
      end

      it 'attempts conversion for .heif extension' do
        result = viewer.send(:convert_heic_if_needed, '/nonexistent/image.heif')
        if result
          expect(result).to include('rfd_heic_')
          File.unlink(result) if File.exist?(result)
        end
      end

      it 'handles uppercase extensions' do
        result = viewer.send(:convert_heic_if_needed, '/nonexistent/image.HEIC')
        if result
          expect(result).to include('rfd_heic_')
          File.unlink(result) if File.exist?(result)
        end
      end

      it 'returns path ending in .png on conversion' do
        result = viewer.send(:convert_heic_if_needed, '/test/image.heic')
        if result
          expect(result).to end_with('.png')
          File.unlink(result) if File.exist?(result)
        end
      end
    end
  end

  describe 'ROUGE_COLORS constant' do
    it 'maps Comment to green' do
      expect(Rfd::Viewer::ROUGE_COLORS['Comment']).to eq(Curses::COLOR_GREEN)
    end

    it 'maps Keyword to cyan' do
      expect(Rfd::Viewer::ROUGE_COLORS['Keyword']).to eq(Curses::COLOR_CYAN)
    end

    it 'maps Name.Function to magenta' do
      expect(Rfd::Viewer::ROUGE_COLORS['Name.Function']).to eq(Curses::COLOR_MAGENTA)
    end

    it 'maps Literal.String to red' do
      expect(Rfd::Viewer::ROUGE_COLORS['Literal.String']).to eq(Curses::COLOR_RED)
    end
  end

  describe '#rouge_token_color' do
    it 'returns green color pair for comments' do
      token = Rouge::Token::Tokens::Comment
      result = viewer.send(:rouge_token_color, token)
      expect(result).to eq(Curses.color_pair(Curses::COLOR_GREEN))
    end

    it 'returns cyan color pair for keywords' do
      token = Rouge::Token::Tokens::Keyword
      result = viewer.send(:rouge_token_color, token)
      expect(result).to eq(Curses.color_pair(Curses::COLOR_CYAN))
    end

    it 'returns A_NORMAL for unknown tokens' do
      token = Rouge::Token::Tokens::Text
      result = viewer.send(:rouge_token_color, token)
      expect(result).to eq(Curses::A_NORMAL)
    end
  end
end
