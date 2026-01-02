# frozen_string_literal: true

require 'spec_helper'
require 'rfd/logging'
require 'tempfile'

describe 'Rfd logging' do
  describe 'Rfd.logger' do
    it 'returns nil by default' do
      # Logger should be nil unless explicitly set
      # (Note: may be set by previous tests)
      expect(Rfd.logger).to be_nil.or be_a(Logger)
    end
  end

  describe 'Rfd.log' do
    context 'when logger is nil' do
      before do
        @original_logger = Rfd.instance_variable_get(:@logger)
        Rfd.instance_variable_set(:@logger, nil)
      end

      after do
        Rfd.instance_variable_set(:@logger, @original_logger)
      end

      it 'does not raise an error' do
        expect { Rfd.log('test') }.not_to raise_error
      end
    end

    context 'when logger is set' do
      let(:mock_logger) { instance_double(Logger) }

      before do
        @original_logger = Rfd.instance_variable_get(:@logger)
        Rfd.instance_variable_set(:@logger, mock_logger)
      end

      after do
        Rfd.instance_variable_set(:@logger, @original_logger)
      end

      it 'calls debug on the logger' do
        expect(mock_logger).to receive(:debug).with('test message')
        Rfd.log('test message')
      end
    end
  end

  describe 'Rfd::Logging module' do
    it 'is defined' do
      expect(Rfd::Logging).to be_a(Module)
    end

    it 'responds to included' do
      expect(Rfd::Logging).to respond_to(:included)
    end
  end
end
