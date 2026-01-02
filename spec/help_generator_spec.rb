# frozen_string_literal: true

require 'spec_helper'
require 'rfd/help_generator'

describe Rfd::HelpGenerator do
  describe '.generate' do
    context 'when cache file exists' do
      it 'returns cached content' do
        expect(File).to receive(:exist?).with(Rfd::HelpGenerator::CACHE_FILE).and_return(true)
        expect(File).to receive(:read).with(Rfd::HelpGenerator::CACHE_FILE).and_return('cached help')
        expect(Rfd::HelpGenerator.generate).to eq('cached help')
      end
    end

    context 'when cache file does not exist' do
      it 'calls build' do
        expect(File).to receive(:exist?).with(Rfd::HelpGenerator::CACHE_FILE).and_return(false)
        expect(Rfd::HelpGenerator).to receive(:build).and_return('built help')
        expect(Rfd::HelpGenerator.generate).to eq('built help')
      end
    end
  end

  describe '.build' do
    let(:help_text) { Rfd::HelpGenerator.build }

    it 'returns a string' do
      expect(help_text).to be_a(String)
    end

    it 'includes navigation commands' do
      expect(help_text).to include('Navigation')
    end

    it 'includes file operation commands' do
      expect(help_text).to include('File Operations')
    end

    it 'includes environment variable info' do
      expect(help_text).to include('RFD_NO_ICONS')
    end

    it 'formats entries with key and description' do
      # Should have format like "  key          description"
      expect(help_text).to match(/^\s{2}\S+\s+\S+/m)
    end
  end

  describe '.write_cache' do
    it 'writes build output to cache file' do
      built_content = 'test help content'
      expect(Rfd::HelpGenerator).to receive(:build).and_return(built_content)
      expect(File).to receive(:write).with(Rfd::HelpGenerator::CACHE_FILE, built_content)
      Rfd::HelpGenerator.write_cache
    end
  end

  describe '.parse_comments (private)' do
    let(:comments) { Rfd::HelpGenerator.send(:parse_comments) }

    it 'returns a hash' do
      expect(comments).to be_a(Hash)
    end

    it 'parses method comments with key: description format' do
      # The commands.rb has comments like "# Key: Description"
      # Check that at least some are parsed
      expect(comments).not_to be_empty
    end

    it 'uses method name as key when no explicit key provided' do
      # Find a comment that has just a description (no key:)
      desc_only = comments.values.find { |v| v[:key].nil? && v[:description] }
      if desc_only
        expect(desc_only[:description]).to be_a(String)
      end
    end
  end

  describe '.build_entries_for (private)' do
    let(:comments) { Rfd::HelpGenerator.send(:parse_comments) }

    it 'returns an array of entries' do
      category = Rfd::Commands.categories.first
      entries = Rfd::HelpGenerator.send(:build_entries_for, category, comments)
      expect(entries).to be_an(Array)
    end

    it 'each entry has key and description' do
      category = Rfd::Commands.categories.first
      entries = Rfd::HelpGenerator.send(:build_entries_for, category, comments)
      entries.each do |entry|
        expect(entry).to have_key(:key)
        expect(entry).to have_key(:description)
      end
    end

    it 'includes command groups' do
      # Find a category that has command groups
      category = Rfd::Commands.categories.find do |cat|
        Rfd::Commands.command_groups.any? { |g| g[:category] == cat }
      end

      if category
        entries = Rfd::HelpGenerator.send(:build_entries_for, category, comments)
        group = Rfd::Commands.command_groups.find { |g| g[:category] == category }
        expect(entries.map { |e| e[:key] }).to include(group[:label])
      end
    end

    it 'excludes no_help_methods' do
      Rfd::Commands.categories.each do |category|
        entries = Rfd::HelpGenerator.send(:build_entries_for, category, comments)
        entry_keys = entries.map { |e| e[:key].to_sym }
        Rfd::Commands.no_help_methods.each do |no_help|
          expect(entry_keys).not_to include(no_help)
        end
      end
    end
  end

  describe 'CACHE_FILE' do
    it 'points to help.txt in the same directory' do
      expect(Rfd::HelpGenerator::CACHE_FILE).to end_with('help.txt')
      expect(Rfd::HelpGenerator::CACHE_FILE).to include('lib/rfd')
    end
  end
end
