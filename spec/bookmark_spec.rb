# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd::Bookmark do
  before do
    Rfd::Bookmark.bookmarks.clear
    allow(Rfd::Bookmark).to receive(:save)  # Stub save to avoid file writes
  end

  describe '.add' do
    it 'adds a path to bookmarks' do
      Rfd::Bookmark.add('/tmp/test')
      expect(Rfd::Bookmark.bookmarks).to include('/tmp/test')
    end

    it 'expands the path' do
      Rfd::Bookmark.add('~/test')
      expect(Rfd::Bookmark.bookmarks).to include(File.expand_path('~/test'))
    end

    it 'does not add duplicates' do
      Rfd::Bookmark.add('/tmp/test')
      Rfd::Bookmark.add('/tmp/test')
      expect(Rfd::Bookmark.bookmarks.count('/tmp/test')).to eq(1)
    end

    it 'saves after adding' do
      Rfd::Bookmark.add('/tmp/test')
      expect(Rfd::Bookmark).to have_received(:save)
    end
  end

  describe '.remove' do
    before do
      Rfd::Bookmark.bookmarks << '/tmp/test'
    end

    it 'removes a path from bookmarks' do
      Rfd::Bookmark.remove('/tmp/test')
      expect(Rfd::Bookmark.bookmarks).not_to include('/tmp/test')
    end

    it 'saves after removing' do
      Rfd::Bookmark.remove('/tmp/test')
      expect(Rfd::Bookmark).to have_received(:save)
    end
  end

  describe '.include?' do
    it 'returns true if path is bookmarked' do
      Rfd::Bookmark.bookmarks << '/tmp/test'
      expect(Rfd::Bookmark.include?('/tmp/test')).to be true
    end

    it 'returns false if path is not bookmarked' do
      expect(Rfd::Bookmark.include?('/tmp/nonexistent')).to be false
    end
  end

  describe '.toggle' do
    context 'when path is not bookmarked' do
      it 'adds the path' do
        Rfd::Bookmark.toggle('/tmp/test')
        expect(Rfd::Bookmark.include?('/tmp/test')).to be true
      end
    end

    context 'when path is already bookmarked' do
      before do
        Rfd::Bookmark.bookmarks << '/tmp/test'
      end

      it 'removes the path' do
        Rfd::Bookmark.toggle('/tmp/test')
        expect(Rfd::Bookmark.include?('/tmp/test')).to be false
      end
    end
  end

  describe '.load' do
    let(:bookmark_file) { Rfd::Bookmark::BOOKMARK_FILE }

    context 'when bookmark file exists' do
      before do
        allow(File).to receive(:exist?).with(bookmark_file).and_return(true)
        allow(File).to receive(:readlines).with(bookmark_file, chomp: true).and_return(['/tmp', '/var'])
        allow(File).to receive(:directory?).and_return(true)
      end

      it 'loads bookmarks from file' do
        Rfd::Bookmark.load
        expect(Rfd::Bookmark.bookmarks).to include('/tmp', '/var')
      end
    end

    context 'when bookmark file does not exist' do
      before do
        allow(File).to receive(:exist?).with(bookmark_file).and_return(false)
      end

      it 'does not raise error' do
        expect { Rfd::Bookmark.load }.not_to raise_error
      end
    end
  end

  describe '.save' do
    let(:bookmark_file) { Rfd::Bookmark::BOOKMARK_FILE }
    let(:bookmark_dir) { File.dirname(bookmark_file) }

    before do
      allow(Rfd::Bookmark).to receive(:save).and_call_original
      allow(File).to receive(:directory?).with(bookmark_dir).and_return(true)
      allow(File).to receive(:write)
    end

    it 'writes bookmarks to file' do
      Rfd::Bookmark.bookmarks << '/tmp/test'
      Rfd::Bookmark.save
      expect(File).to have_received(:write).with(bookmark_file, "/tmp/test\n")
    end
  end
end
