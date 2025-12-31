# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd::Commands do
  include_context 'rfd setup'

  describe 'times' do
    subject { controller.times }
    context 'before accepting 0-9' do
      it { should == 1 }
    end
    context 'When 0-9 were typed' do
      before do
        controller.public_send '3'
        controller.public_send '7'
      end
      after do
        controller.instance_variable_set :@times, nil
      end
      it { should == 37 }
    end
  end
end
