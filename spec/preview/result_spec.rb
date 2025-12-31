# frozen_string_literal: true
require 'spec_helper'
require 'rfd/preview/result'

describe Rfd::Preview::Result do
  describe '#initialize' do
    context 'with minimal attributes' do
      let(:result) { described_class.new(request_id: 'req-1', status: 'success') }

      it 'sets required attributes' do
        expect(result.request_id).to eq('req-1')
        expect(result.status).to eq(:success)
      end

      it 'leaves optional attributes nil' do
        expect(result.file_type).to be_nil
        expect(result.lines).to be_nil
        expect(result.thumbnail_path).to be_nil
        expect(result.metadata).to be_nil
        expect(result.error).to be_nil
      end
    end

    context 'with all attributes' do
      let(:result) do
        described_class.new(
          request_id: 'req-2',
          status: :success,
          file_type: :text,
          lines: [{text: 'hello', attrs: []}],
          thumbnail_path: '/tmp/thumb.png',
          metadata: {duration: '1:30'},
          error: nil
        )
      end

      it 'sets all attributes' do
        expect(result.request_id).to eq('req-2')
        expect(result.status).to eq(:success)
        expect(result.file_type).to eq(:text)
        expect(result.lines).to eq([{text: 'hello', attrs: []}])
        expect(result.thumbnail_path).to eq('/tmp/thumb.png')
        expect(result.metadata).to eq({duration: '1:30'})
      end
    end
  end

  describe 'status predicates' do
    describe '#success?' do
      it 'returns true when status is :success' do
        result = described_class.new(request_id: 'x', status: :success)
        expect(result.success?).to be true
        expect(result.error?).to be false
        expect(result.cancelled?).to be false
      end
    end

    describe '#error?' do
      it 'returns true when status is :error' do
        result = described_class.new(request_id: 'x', status: :error)
        expect(result.error?).to be true
        expect(result.success?).to be false
        expect(result.cancelled?).to be false
      end
    end

    describe '#cancelled?' do
      it 'returns true when status is :cancelled' do
        result = described_class.new(request_id: 'x', status: :cancelled)
        expect(result.cancelled?).to be true
        expect(result.success?).to be false
        expect(result.error?).to be false
      end
    end
  end

  describe '#to_h' do
    context 'with minimal result' do
      let(:result) { described_class.new(request_id: 'min', status: :success) }

      it 'includes only required fields' do
        hash = result.to_h
        expect(hash[:type]).to eq('result')
        expect(hash[:id]).to eq('min')
        expect(hash[:status]).to eq('success')
        expect(hash).not_to have_key(:file_type)
        expect(hash).not_to have_key(:lines)
        expect(hash).not_to have_key(:thumbnail_path)
        expect(hash).not_to have_key(:metadata)
        expect(hash).not_to have_key(:error)
      end
    end

    context 'with all fields' do
      let(:result) do
        described_class.new(
          request_id: 'full',
          status: :success,
          file_type: :video,
          lines: [{text: 'line1', attrs: []}],
          thumbnail_path: '/tmp/thumb.png',
          metadata: {resolution: '1920x1080'},
          error: nil
        )
      end

      it 'includes all non-nil fields' do
        hash = result.to_h
        expect(hash[:file_type]).to eq('video')
        expect(hash[:lines]).to eq([{text: 'line1', attrs: []}])
        expect(hash[:thumbnail_path]).to eq('/tmp/thumb.png')
        expect(hash[:metadata]).to eq({resolution: '1920x1080'})
      end
    end

    context 'with error' do
      let(:result) do
        described_class.new(request_id: 'err', status: :error, error: 'Something failed')
      end

      it 'includes error field' do
        hash = result.to_h
        expect(hash[:error]).to eq('Something failed')
      end
    end
  end

  describe '.from_hash' do
    let(:hash) do
      {
        'id' => 'from-hash',
        'status' => 'success',
        'file_type' => 'markdown',
        'lines' => [{'text' => 'test', 'attrs' => []}],
        'thumbnail_path' => '/tmp/img.png',
        'metadata' => {'key' => 'value'},
        'error' => nil
      }
    end

    it 'creates a Result from hash' do
      result = described_class.from_hash(hash)
      expect(result.request_id).to eq('from-hash')
      expect(result.status).to eq(:success)
      expect(result.file_type).to eq(:markdown)
      expect(result.lines).to eq([{'text' => 'test', 'attrs' => []}])
      expect(result.thumbnail_path).to eq('/tmp/img.png')
      expect(result.metadata).to eq({'key' => 'value'})
    end
  end

  describe 'factory methods' do
    describe '.success' do
      it 'creates a success result' do
        result = described_class.success(
          request_id: 'succ',
          file_type: :text,
          lines: [{text: 'hello', attrs: []}]
        )
        expect(result.success?).to be true
        expect(result.request_id).to eq('succ')
        expect(result.file_type).to eq(:text)
        expect(result.lines).to eq([{text: 'hello', attrs: []}])
      end

      it 'accepts optional thumbnail_path and metadata' do
        result = described_class.success(
          request_id: 'vid',
          file_type: :video,
          thumbnail_path: '/tmp/thumb.png',
          metadata: {duration: '2:00'}
        )
        expect(result.thumbnail_path).to eq('/tmp/thumb.png')
        expect(result.metadata).to eq({duration: '2:00'})
      end
    end

    describe '.error' do
      it 'creates an error result' do
        result = described_class.error(request_id: 'fail', error: 'File not found')
        expect(result.error?).to be true
        expect(result.request_id).to eq('fail')
        expect(result.error).to eq('File not found')
      end
    end

    describe '.cancelled' do
      it 'creates a cancelled result' do
        result = described_class.cancelled(request_id: 'canc')
        expect(result.cancelled?).to be true
        expect(result.request_id).to eq('canc')
      end
    end
  end

  describe 'round-trip serialization' do
    let(:original) do
      described_class.success(
        request_id: 'round-trip',
        file_type: :code,
        lines: [{text: 'def foo', attrs: ['cyan']}],
        metadata: {lang: 'ruby'}
      )
    end

    it 'preserves data through to_h and from_hash' do
      hash = original.to_h
      json_hash = JSON.parse(hash.to_json)
      restored = described_class.from_hash(json_hash)

      expect(restored.request_id).to eq(original.request_id)
      expect(restored.status).to eq(original.status)
      expect(restored.file_type).to eq(original.file_type)
    end
  end
end
