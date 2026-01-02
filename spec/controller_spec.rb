# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd::Controller do
  include_context 'rfd setup'

  describe '#spawn_panes' do
    before { controller.spawn_panes 3 }

    subject { controller.main.instance_variable_get :@number_of_panes }
    it { should  == 3 }
  end

  describe '#current_item' do
    before do
      controller.instance_variable_set :@current_row, 3
    end
    its(:current_item) { should == items[3] }
  end

  describe '#marked_items' do
    before do
      items[2].toggle_mark
      items[3].toggle_mark
    end
    its(:marked_items) { should == [items[2], items[3]] }
  end

  describe '#selected_items' do
    context 'When no items were marked' do
      context 'When the cursor is on . or ..' do
        before do
          controller.instance_variable_set :@current_row, 0
        end
        its(:selected_items) { should be_empty }
      end

      context 'When the cursor is not on . nor ..' do
        before do
          controller.instance_variable_set :@current_row, 5
        end
        its(:selected_items) { should == [items[5]] }
      end
    end
    context 'When items were marked' do
      before do
        items[2].toggle_mark
        items[4].toggle_mark
      end
      its(:selected_items) { should == [items[2], items[4]] }
    end
  end

  describe '#move_cursor' do
    context 'When moving to nil' do
      before do
        controller.move_cursor nil
      end
      # Default position is now 2 (first file after . and ..)
      its(:current_row) { should == 2 }
    end
    context 'When moving to a certain row' do
      before do
        controller.move_cursor 2
      end
      its(:current_row) { should == 2 }

      context 'When moving to the second pane' do
        before do
          controller.move_cursor 5
        end
        subject { controller.main.instance_variable_get :@current_index }
        it { should == 1 }
      end

      context 'When moving to the second page' do
        before do
          controller.move_cursor 7
        end
        its(:current_page) { should == 1 }
      end
    end
  end

  describe '#find' do
    before do
      controller.find 'd'
    end
    its('current_item.name') { should start_with('d') }
  end

  describe '#find_reverse' do
    before do
      controller.find_reverse 'f'
    end
    its('current_item.name') { should == 'file3' }
  end

  describe '#first_page? and #last_page?' do
    context 'When on the first page' do
      it { should be_first_page }
      it { should_not be_last_page }
    end
    context 'When on the last page' do
      before do
        controller.public_send :'^p'  # Navigate to previous (last) page from first page
      end
      it { should_not be_first_page }
      it { should be_last_page }
    end
  end

  describe '#total_pages' do
    its(:total_pages) { should == 3 }  # 15 / (3 * 2) + 1
  end

  describe '#switch_page' do
    before do
      controller.switch_page 2
    end
    its(:current_page) { should == 2 }
  end

  describe '#toggle_mark' do
    before do
      controller.move_cursor 10
      controller.toggle_mark
    end
    subject { items[10] }
    it { should be_marked }
  end
end
