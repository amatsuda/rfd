# frozen_string_literal: true

require 'spec_helper'
require 'rfd/preview_window'

describe Rfd::PreviewWindow do
  describe Rfd::PreviewWindow::RougeSupport do
    let(:test_class) do
      Class.new { include Rfd::PreviewWindow::RougeSupport }
    end
    let(:instance) { test_class.new }

    describe '#rouge_token_color' do
      it 'returns green for Comment tokens' do
        token = double(qualname: 'Comment.Single')
        expect(instance.rouge_token_color(token)).to eq(Curses.color_pair(Curses::COLOR_GREEN))
      end

      it 'returns cyan for Keyword tokens' do
        token = double(qualname: 'Keyword.Reserved')
        expect(instance.rouge_token_color(token)).to eq(Curses.color_pair(Curses::COLOR_CYAN))
      end

      it 'returns magenta for Name.Function tokens' do
        token = double(qualname: 'Name.Function')
        expect(instance.rouge_token_color(token)).to eq(Curses.color_pair(Curses::COLOR_MAGENTA))
      end

      it 'returns magenta for Name.Class tokens' do
        token = double(qualname: 'Name.Class')
        expect(instance.rouge_token_color(token)).to eq(Curses.color_pair(Curses::COLOR_MAGENTA))
      end

      it 'returns red for Literal.String tokens' do
        token = double(qualname: 'Literal.String.Double')
        expect(instance.rouge_token_color(token)).to eq(Curses.color_pair(Curses::COLOR_RED))
      end

      it 'returns red for Literal.Number tokens' do
        token = double(qualname: 'Literal.Number.Integer')
        expect(instance.rouge_token_color(token)).to eq(Curses.color_pair(Curses::COLOR_RED))
      end

      it 'returns cyan for Operator tokens' do
        token = double(qualname: 'Operator')
        expect(instance.rouge_token_color(token)).to eq(Curses.color_pair(Curses::COLOR_CYAN))
      end

      it 'returns A_NORMAL for unrecognized tokens' do
        token = double(qualname: 'Generic.Unknown')
        expect(instance.rouge_token_color(token)).to eq(Curses::A_NORMAL)
      end
    end
  end

  describe 'archive tree building' do
    # Create a minimal mock to test the private methods
    let(:controller) do
      double(
        current_item: double(name: 'test'),
        main: double(maxy: 10, width: 40, begy: 5, current_index: 0, number_of_panes: 2, display: nil),
        current_page: 0
      )
    end

    let(:preview_window) do
      # Stub Curses::Window.new to avoid actual curses calls
      allow(Curses::Window).to receive(:new).and_return(
        double(
          maxy: 20,
          maxx: 40,
          begx: 0,
          clear: nil,
          refresh: nil,
          setpos: nil,
          addstr: nil,
          bkgdset: nil,
          close: nil
        )
      )
      Rfd::PreviewWindow.new(controller)
    end

    describe '#build_archive_tree' do
      it 'builds a tree from flat paths' do
        entries = ['lib/rfd.rb', 'lib/rfd/item.rb', 'spec/spec_helper.rb']
        lines = preview_window.send(:build_archive_tree, entries)

        expect(lines).to include('lib/')
        expect(lines).to include('spec/')
      end

      it 'handles nested directories' do
        entries = ['a/b/c/file.txt']
        lines = preview_window.send(:build_archive_tree, entries)

        expect(lines.join("\n")).to include('a/')
        expect(lines.join("\n")).to include('b/')
        expect(lines.join("\n")).to include('c/')
        expect(lines.join("\n")).to include('file.txt')
      end

      it 'handles empty entries' do
        entries = []
        lines = preview_window.send(:build_archive_tree, entries)
        expect(lines).to eq([])
      end

      it 'sorts directories before files' do
        entries = ['file.txt', 'dir/nested.txt']
        lines = preview_window.send(:build_archive_tree, entries)

        dir_index = lines.index { |l| l.include?('dir/') }
        file_index = lines.index { |l| l.include?('file.txt') }
        expect(dir_index).to be < file_index
      end

      it 'handles paths with leading slashes' do
        entries = ['/root/file.txt']
        lines = preview_window.send(:build_archive_tree, entries)
        expect(lines.join("\n")).to include('root/')
        expect(lines.join("\n")).to include('file.txt')
      end
    end

    describe '#render_tree_node' do
      it 'renders root level without connectors' do
        tree = { 'file.txt' => {} }
        lines = []
        preview_window.send(:render_tree_node, tree, '', lines, true)

        expect(lines.first).to eq('file.txt')
      end

      it 'renders nested items with connectors' do
        tree = { 'dir' => { 'file.txt' => {} } }
        lines = []
        preview_window.send(:render_tree_node, tree, '', lines, true)

        expect(lines).to include('dir/')
        expect(lines.any? { |l| l.include?('└── file.txt') }).to be true
      end

      it 'uses different connectors for last vs non-last items' do
        tree = { 'dir' => { 'a.txt' => {}, 'b.txt' => {} } }
        lines = []
        preview_window.send(:render_tree_node, tree, '', lines, true)

        expect(lines.any? { |l| l.include?('├── a.txt') }).to be true
        expect(lines.any? { |l| l.include?('└── b.txt') }).to be true
      end

      it 'appends / to directory names' do
        tree = { 'subdir' => { 'file.txt' => {} } }
        lines = []
        preview_window.send(:render_tree_node, tree, '', lines, true)

        expect(lines.first).to eq('subdir/')
      end
    end
  end
end
