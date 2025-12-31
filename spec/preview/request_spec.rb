# frozen_string_literal: true
require 'spec_helper'
require 'rfd/preview/request'

describe Rfd::Preview::Request do
  describe '#initialize' do
    let(:request) do
      described_class.new(
        id: 'test-123',
        file_path: '/path/to/file.txt',
        file_type: :text,
        width: 80,
        height: 24
      )
    end

    it 'sets all attributes' do
      expect(request.id).to eq('test-123')
      expect(request.file_path).to eq('/path/to/file.txt')
      expect(request.file_type).to eq(:text)
      expect(request.width).to eq(80)
      expect(request.height).to eq(24)
    end

    it 'sets timestamp' do
      expect(request.timestamp).to be_within(1).of(Time.now.to_f)
    end
  end

  describe '#to_h' do
    let(:request) do
      described_class.new(
        id: 'abc-456',
        file_path: '/some/path.rb',
        file_type: :code,
        width: 100,
        height: 30
      )
    end

    it 'returns a hash representation' do
      hash = request.to_h
      expect(hash[:type]).to eq('request')
      expect(hash[:id]).to eq('abc-456')
      expect(hash[:path]).to eq('/some/path.rb')
      expect(hash[:file_type]).to eq(:code)
      expect(hash[:width]).to eq(100)
      expect(hash[:height]).to eq(30)
    end
  end

  describe '.from_hash' do
    let(:hash) do
      {
        'id' => 'xyz-789',
        'path' => '/dir/file.md',
        'file_type' => 'markdown',
        'width' => 120,
        'height' => 40
      }
    end

    it 'creates a Request from hash' do
      request = described_class.from_hash(hash)
      expect(request.id).to eq('xyz-789')
      expect(request.file_path).to eq('/dir/file.md')
      expect(request.file_type).to eq(:markdown)
      expect(request.width).to eq(120)
      expect(request.height).to eq(40)
    end

    context 'with nil file_type' do
      let(:hash) do
        {
          'id' => 'test',
          'path' => '/file',
          'file_type' => nil,
          'width' => 80,
          'height' => 24
        }
      end

      it 'handles nil file_type' do
        request = described_class.from_hash(hash)
        expect(request.file_type).to be_nil
      end
    end
  end

  describe 'round-trip serialization' do
    let(:original) do
      described_class.new(
        id: 'round-trip-test',
        file_path: '/test/path.txt',
        file_type: :directory,
        width: 80,
        height: 24
      )
    end

    it 'preserves data through to_h and from_hash' do
      hash = original.to_h
      # Simulate JSON serialization (keys become strings)
      json_hash = JSON.parse(hash.to_json)
      restored = described_class.from_hash(json_hash)

      expect(restored.id).to eq(original.id)
      expect(restored.file_path).to eq(original.file_path)
      expect(restored.file_type).to eq(original.file_type)
      expect(restored.width).to eq(original.width)
      expect(restored.height).to eq(original.height)
    end
  end
end
