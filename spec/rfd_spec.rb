# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd do
  describe 'VERSION' do
    it 'is defined' do
      expect(Rfd::VERSION).not_to be_nil
    end

    it 'is a string' do
      expect(Rfd::VERSION).to be_a(String)
    end
  end
end

describe Rfd::Controller do
  include_context 'rfd setup'

  describe '#times' do
    context 'when @times is nil' do
      before { controller.instance_variable_set(:@times, nil) }

      it 'returns 1' do
        expect(controller.times).to eq(1)
      end
    end

    context 'when @times is set' do
      before { controller.instance_variable_set(:@times, '5') }

      it 'returns the integer value' do
        expect(controller.times).to eq(5)
      end
    end

    context 'when @times is a number' do
      before { controller.instance_variable_set(:@times, 3) }

      it 'returns the integer value' do
        expect(controller.times).to eq(3)
      end
    end
  end

  describe '#current_item' do
    before { controller.instance_variable_set(:@current_row, 3) }

    it 'returns the item at current_row' do
      expect(controller.current_item).to eq(items[3])
    end
  end

  describe '#marked_items' do
    context 'with no marked items' do
      it 'returns empty array' do
        expect(controller.marked_items).to be_empty
      end
    end

    context 'with marked items' do
      before do
        items[3].toggle_mark
        items[5].toggle_mark
      end

      it 'returns the marked items' do
        expect(controller.marked_items).to contain_exactly(items[3], items[5])
      end
    end
  end

  describe '#selected_items' do
    context 'when items are marked' do
      before do
        items[3].toggle_mark
        items[5].toggle_mark
      end

      it 'returns marked items' do
        expect(controller.selected_items).to contain_exactly(items[3], items[5])
      end
    end

    context 'when no items are marked' do
      context 'when cursor is on regular file' do
        before { controller.instance_variable_set(:@current_row, 4) }

        it 'returns array with current item' do
          expect(controller.selected_items).to eq([items[4]])
        end
      end

      context 'when cursor is on . directory' do
        before { controller.instance_variable_set(:@current_row, 0) }

        it 'returns empty array' do
          expect(controller.selected_items).to be_empty
        end
      end

      context 'when cursor is on .. directory' do
        before { controller.instance_variable_set(:@current_row, 1) }

        it 'returns empty array' do
          expect(controller.selected_items).to be_empty
        end
      end
    end
  end

  describe '#first_page?' do
    context 'on first page' do
      before { controller.instance_variable_set(:@current_page, 0) }

      it 'returns true' do
        expect(controller.first_page?).to be true
      end
    end

    context 'on other page' do
      before { controller.instance_variable_set(:@current_page, 1) }

      it 'returns false' do
        expect(controller.first_page?).to be false
      end
    end
  end

  describe '#last_page?' do
    context 'on last page' do
      before do
        last = controller.total_pages - 1
        controller.instance_variable_set(:@current_page, last)
      end

      it 'returns true' do
        expect(controller.last_page?).to be true
      end
    end

    context 'on first page with multiple pages' do
      before { controller.instance_variable_set(:@current_page, 0) }

      it 'returns false' do
        # Only if there are multiple pages
        if controller.total_pages > 1
          expect(controller.last_page?).to be false
        end
      end
    end
  end

  describe '#total_pages' do
    it 'calculates based on items and max_items' do
      # With 15 test items and maxy=3, max_items=6, total_pages should be 3
      expect(controller.total_pages).to eq(3)
    end
  end

  describe '#maxy' do
    it 'delegates to main window' do
      expect(controller.maxy).to eq(controller.main.maxy)
    end
  end

  describe '#max_items' do
    it 'delegates to main window' do
      expect(controller.max_items).to eq(controller.main.max_items)
    end
  end

  describe '#preview_client' do
    it 'returns the preview client (may be nil in test)' do
      # In test env, preview server is skipped
      expect(controller.preview_client).to be_nil
    end
  end

  describe '#spawn_panes' do
    before { controller.spawn_panes(4) }

    it 'sets number of panes' do
      expect(controller.main.instance_variable_get(:@number_of_panes)).to eq(4)
    end

    it 'resets current_row to 0' do
      expect(controller.current_row).to eq(0)
    end

    it 'resets current_page to 0' do
      expect(controller.current_page).to eq(0)
    end
  end

  describe '#get_char' do
    # This requires user input, skip in automated tests
  end

  describe '#ask' do
    # This requires user input, skip in automated tests
  end

  describe 'HelpGenerator' do
    let(:help_text) { Rfd::HelpGenerator.generate }

    it 'generates help text' do
      expect(help_text).not_to be_nil
    end

    it 'contains navigation section' do
      expect(help_text).to include('Navigation')
    end

    it 'contains file operations section' do
      expect(help_text).to include('File Operations')
    end

    it 'contains viewing section' do
      expect(help_text).to include('Viewing')
    end

    it 'contains quit instruction' do
      expect(help_text).to include('Quit')
    end
  end

  describe '#draw_marked_items' do
    before do
      items[3].toggle_mark
      items[5].toggle_mark
    end

    it 'does not raise' do
      expect { controller.draw_marked_items }.not_to raise_error
    end
  end

  describe '#draw_total_items' do
    it 'does not raise' do
      expect { controller.draw_total_items }.not_to raise_error
    end
  end

  describe '#clear_command_line' do
    it 'does not raise' do
      expect { controller.clear_command_line }.not_to raise_error
    end
  end

  describe '#move_cursor_by_click' do
    it 'does not raise with valid coordinates' do
      expect { controller.move_cursor_by_click(y: 5, x: 10) }.not_to raise_error
    end

    it 'handles coordinates outside main window' do
      expect { controller.move_cursor_by_click(y: 0, x: 0) }.not_to raise_error
    end
  end

  describe '#stop_preview_server' do
    it 'does not raise when no server running' do
      expect { controller.stop_preview_server }.not_to raise_error
    end
  end
end
