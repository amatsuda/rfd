# frozen_string_literal: true

require 'spec_helper'
require 'rfd/filter_input'

describe Rfd::FilterInput do
  describe '#initialize' do
    it 'starts with empty text' do
      filter = Rfd::FilterInput.new
      expect(filter.text).to eq('')
    end

    it 'accepts an on_change callback' do
      called = false
      filter = Rfd::FilterInput.new { called = true }
      filter.append('a')
      expect(called).to be true
    end
  end

  describe '#append' do
    it 'appends characters to text' do
      filter = Rfd::FilterInput.new
      filter.append('a')
      filter.append('b')
      expect(filter.text).to eq('ab')
    end

    it 'calls the on_change callback' do
      call_count = 0
      filter = Rfd::FilterInput.new { call_count += 1 }
      filter.append('a')
      filter.append('b')
      expect(call_count).to eq(2)
    end
  end

  describe '#backspace' do
    it 'removes the last character' do
      filter = Rfd::FilterInput.new
      filter.append('abc')
      filter.backspace
      expect(filter.text).to eq('ab')
    end

    it 'does nothing when text is empty' do
      called = false
      filter = Rfd::FilterInput.new { called = true }
      filter.backspace
      expect(filter.text).to eq('')
      expect(called).to be false
    end

    it 'calls the on_change callback' do
      call_count = 0
      filter = Rfd::FilterInput.new { call_count += 1 }
      filter.append('ab')
      call_count = 0
      filter.backspace
      expect(call_count).to eq(1)
    end
  end

  describe '#clear' do
    it 'clears all text' do
      filter = Rfd::FilterInput.new
      filter.append('abc')
      filter.clear
      expect(filter.text).to eq('')
    end

    it 'does nothing when text is already empty' do
      called = false
      filter = Rfd::FilterInput.new { called = true }
      filter.clear
      expect(called).to be false
    end

    it 'calls the on_change callback' do
      call_count = 0
      filter = Rfd::FilterInput.new { call_count += 1 }
      filter.append('abc')
      call_count = 0
      filter.clear
      expect(call_count).to eq(1)
    end
  end

  describe '#empty?' do
    it 'returns true when text is empty' do
      filter = Rfd::FilterInput.new
      expect(filter.empty?).to be true
    end

    it 'returns false when text is not empty' do
      filter = Rfd::FilterInput.new
      filter.append('a')
      expect(filter.empty?).to be false
    end
  end

  describe '#handle_input' do
    let(:filter) { Rfd::FilterInput.new }

    context 'with backspace/delete keys' do
      before { filter.append('abc') }

      it 'handles ASCII backspace (8)' do
        expect(filter.handle_input(8)).to be true
        expect(filter.text).to eq('ab')
      end

      it 'handles DEL (127)' do
        expect(filter.handle_input(127)).to be true
        expect(filter.text).to eq('ab')
      end

      it 'handles Curses::KEY_BACKSPACE' do
        expect(filter.handle_input(Curses::KEY_BACKSPACE)).to be true
        expect(filter.text).to eq('ab')
      end

      it 'handles Curses::KEY_DC' do
        expect(filter.handle_input(Curses::KEY_DC)).to be true
        expect(filter.text).to eq('ab')
      end
    end

    context 'with Ctrl-U' do
      before { filter.append('abc') }

      it 'clears all text' do
        expect(filter.handle_input(21)).to be true
        expect(filter.text).to eq('')
      end
    end

    context 'with string input' do
      it 'appends the string' do
        expect(filter.handle_input('a')).to be true
        expect(filter.handle_input('bc')).to be true
        expect(filter.text).to eq('abc')
      end
    end

    context 'with printable ASCII integers' do
      it 'appends the character' do
        expect(filter.handle_input(65)).to be true  # 'A'
        expect(filter.handle_input(66)).to be true  # 'B'
        expect(filter.text).to eq('AB')
      end
    end

    context 'with non-printable integers' do
      it 'returns false and does not modify text' do
        expect(filter.handle_input(1)).to be false  # Ctrl-A
        expect(filter.handle_input(200)).to be false  # Extended ASCII
        expect(filter.text).to eq('')
      end
    end

    context 'with other types' do
      it 'returns false' do
        expect(filter.handle_input(nil)).to be false
        expect(filter.handle_input([])).to be false
      end
    end
  end

  describe '#fuzzy_match?' do
    let(:filter) { Rfd::FilterInput.new }

    it 'returns true for empty pattern' do
      expect(filter.fuzzy_match?('anything')).to be true
    end

    it 'matches exact substrings' do
      filter.append('abc')
      expect(filter.fuzzy_match?('abcdef')).to be true
    end

    it 'matches fuzzy patterns' do
      filter.append('ace')
      expect(filter.fuzzy_match?('abcdef')).to be true
    end

    it 'is case insensitive' do
      filter.append('ABC')
      expect(filter.fuzzy_match?('abcdef')).to be true
    end

    it 'returns false when pattern does not match' do
      filter.append('xyz')
      expect(filter.fuzzy_match?('abcdef')).to be false
    end

    it 'returns false when pattern chars are in wrong order' do
      filter.append('cba')
      expect(filter.fuzzy_match?('abcdef')).to be false
    end

    it 'accepts custom pattern parameter' do
      expect(filter.fuzzy_match?('abcdef', 'ace')).to be true
      expect(filter.fuzzy_match?('abcdef', 'xyz')).to be false
    end
  end
end
