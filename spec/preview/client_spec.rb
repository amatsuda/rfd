# frozen_string_literal: true
require 'spec_helper'
require 'rfd/preview/client'

describe Rfd::Preview::Client do
  let(:socket_path) { '/tmp/rfd_test_socket' }
  let(:client) { described_class.new(socket_path) }

  after { client.close rescue nil }

  describe '#initialize' do
    it 'sets socket path' do
      expect(client.instance_variable_get(:@socket_path)).to eq(socket_path)
    end

    it 'starts not connected' do
      expect(client.connected?).to be false
    end

    it 'has empty buffer' do
      expect(client.instance_variable_get(:@buffer)).to eq('')
    end
  end

  describe '#connected?' do
    it 'returns false when not connected' do
      expect(client.connected?).to be false
    end
  end

  describe '#connect' do
    context 'when socket does not exist' do
      it 'remains not connected' do
        client.connect
        expect(client.connected?).to be false
      end
    end
  end

  describe '#ready?' do
    it 'returns false when no results' do
      expect(client.ready?).to be false
    end
  end

  describe '#poll_result' do
    it 'returns nil when no results' do
      expect(client.poll_result).to be_nil
    end
  end

  describe '#cancel' do
    it 'does not raise when not connected' do
      expect { client.cancel('some-id') }.not_to raise_error
    end

    it 'does not raise with nil request_id' do
      expect { client.cancel(nil) }.not_to raise_error
    end
  end

  describe '#shutdown' do
    it 'does not raise when not connected' do
      expect { client.shutdown }.not_to raise_error
    end
  end

  describe '#close' do
    it 'does not raise when not connected' do
      expect { client.close }.not_to raise_error
    end

    it 'sets connected to false' do
      client.close
      expect(client.connected?).to be false
    end
  end

  describe '#request' do
    it 'returns nil when not connected' do
      item = double('Item', path: '/test', preview_type: :text)
      expect(client.request(item: item, width: 80, height: 24)).to be_nil
    end
  end

  describe '#wait_result' do
    it 'returns nil after timeout when no results' do
      result = client.wait_result(timeout: 0.1)
      expect(result).to be_nil
    end
  end
end
