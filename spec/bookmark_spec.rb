# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd::Bookmark do
  before do
    Rfd::Bookmark.bookmarks.clear
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
  end

  describe '.remove' do
    before do
      Rfd::Bookmark.add('/tmp/test')
    end

    it 'removes a path from bookmarks' do
      Rfd::Bookmark.remove('/tmp/test')
      expect(Rfd::Bookmark.bookmarks).not_to include('/tmp/test')
    end
  end

  describe '.include?' do
    it 'returns true if path is bookmarked' do
      Rfd::Bookmark.add('/tmp/test')
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
        Rfd::Bookmark.add('/tmp/test')
      end

      it 'removes the path' do
        Rfd::Bookmark.toggle('/tmp/test')
        expect(Rfd::Bookmark.include?('/tmp/test')).to be false
      end
    end
  end
end
