# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd::Commands do
  include_context 'rfd setup'

  describe 'times (0-9)' do
    subject { controller.times }

    context 'before accepting 0-9' do
      it { should == 1 }
    end

    context 'when 0-9 were typed' do
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

  describe 'navigation commands' do
    describe '#j (move down)' do
      before do
        controller.move_cursor 2
        controller.j
      end
      its(:current_row) { should == 3 }

      context 'with times' do
        before do
          controller.move_cursor 2
          controller.public_send '3'
          controller.j
        end
        its(:current_row) { should == 5 }
      end

      context 'wraps around' do
        before do
          controller.move_cursor items.size - 1
          controller.j
        end
        its(:current_row) { should == 0 }
      end
    end

    describe '#k (move up)' do
      before do
        controller.move_cursor 5
        controller.k
      end
      its(:current_row) { should == 4 }

      context 'with times' do
        before do
          controller.move_cursor 5
          controller.public_send '2'
          controller.k
        end
        its(:current_row) { should == 3 }
      end

      context 'wraps around' do
        before do
          controller.move_cursor 0
          controller.k
        end
        its(:current_row) { should == items.size - 1 }
      end
    end

    describe '#g (move to top)' do
      before do
        controller.move_cursor 5
        controller.g
      end
      its(:current_row) { should == 0 }
    end

    describe '#G (move to bottom)' do
      before do
        controller.G
      end
      its(:current_row) { should == items.size - 1 }
    end

    describe '#H (move to top of screen)' do
      before do
        controller.move_cursor 5
        controller.H
      end
      its(:current_row) { should == controller.current_page * controller.max_items }
    end

    describe '#L (move to bottom of screen)' do
      before do
        controller.move_cursor 2
        controller.L
      end
      it 'moves to the last item on the current page' do
        controller.current_row.should == controller.current_page * controller.max_items + controller.displayed_items.size - 1
      end
    end

    describe '#M (move to middle of screen)' do
      before do
        controller.move_cursor 2
        controller.M
      end
      it 'moves to the middle item on the current page' do
        controller.current_row.should == controller.current_page * controller.max_items + controller.displayed_items.size / 2
      end
    end

    describe '#h (move left pane)' do
      context 'when on second pane' do
        before do
          controller.move_cursor 5
          controller.h
        end
        its(:current_row) { should == 2 }
      end

      context 'when on first pane' do
        before do
          controller.move_cursor 2
          @prev_row = controller.current_row
          controller.h
        end
        it 'does not move' do
          controller.current_row.should == @prev_row
        end
      end
    end

    describe '#l (move right pane)' do
      context 'when items exist in right pane' do
        before do
          controller.move_cursor 2
          controller.l
        end
        its(:current_row) { should == 5 }
      end

      context 'when no items in right pane' do
        before do
          controller.move_cursor items.size - 1
          @prev_row = controller.current_row
          controller.l
        end
        it 'does not move' do
          controller.current_row.should == @prev_row
        end
      end
    end
  end

  describe 'page navigation commands' do
    describe '#^n (next page)' do
      before { controller.public_send :'^n' }
      its(:current_page) { should == 1 }
    end

    describe '#^p (previous page)' do
      before do
        controller.public_send :'^n'
        controller.public_send :'^p'
      end
      its(:current_page) { should == 0 }
    end

    describe '#^b (alias for ^p)' do
      before do
        controller.public_send :'^n'
        controller.public_send :'^b'
      end
      its(:current_page) { should == 0 }
    end

    describe '#^f (alias for ^n)' do
      before { controller.public_send :'^f' }
      its(:current_page) { should == 1 }
    end
  end

  describe 'find commands' do
    describe '#f (find forward)' do
      before do
        allow(controller).to receive(:get_char).and_return('f')
        controller.f
      end
      its('current_item.name') { should start_with('f') }
    end

    describe '#F (find backward)' do
      before do
        allow(controller).to receive(:get_char).and_return('f')
        controller.F
      end
      its('current_item.name') { should == 'file3' }
    end

    describe '#n (repeat last find)' do
      before do
        allow(controller).to receive(:get_char).and_return('d')
        controller.f
        @first_match = controller.current_item.name
        controller.n
      end
      it 'finds the next match' do
        controller.current_item.name.should start_with('d')
        controller.current_item.name.should_not == @first_match
      end
    end

    describe '#N (repeat last find in reverse)' do
      before do
        allow(controller).to receive(:get_char).and_return('f')
        controller.f
        controller.n
        controller.N
      end
      it 'finds in reverse direction' do
        controller.current_item.name.should start_with('f')
      end
    end

    describe '#n without previous find' do
      it 'does nothing' do
        expect { controller.n }.not_to raise_error
      end
    end

    describe '#N without previous find' do
      it 'does nothing' do
        expect { controller.N }.not_to raise_error
      end
    end
  end

  describe 'mark commands' do
    describe '#space (toggle mark and move down)' do
      before do
        controller.move_cursor 3
        controller.space
      end

      it 'marks the item' do
        items[3].should be_marked
      end

      it 'moves cursor down' do
        controller.current_row.should == 4
      end

    end

    describe '#space with times' do
      before do
        controller.move_cursor 2
        controller.public_send '3'
        controller.space
      end

      it 'marks 3 items' do
        items[2].should be_marked
        items[3].should be_marked
        items[4].should be_marked
      end

      its(:current_row) { should == 5 }
    end

    describe '#^a (mark/unmark all)' do
      context 'when no items are marked' do
        before { controller.public_send :'^a' }

        it 'marks all items except . and ..' do
          items[2..-1].all?(&:marked?).should be true
          items[0].should_not be_marked
          items[1].should_not be_marked
        end
      end

      context 'when all items are marked' do
        before do
          controller.public_send :'^a'
          controller.public_send :'^a'
        end

        it 'unmarks all items' do
          items.none?(&:marked?).should be true
        end
      end
    end
  end

  describe 'delete commands' do
    describe '#d (soft delete/trash)' do
      context 'when confirmed' do
        before do
          controller.find 'file3'
          controller.toggle_mark
          allow(controller).to receive(:ask).and_return(true)
          allow(controller).to receive(:system).with('trash', anything) do |cmd, *paths|
            FileUtils.rm_rf(paths)
            true
          end
          controller.d
        end

        it 'deletes the file' do
          controller.items.should be_none { |i| i.name == 'file3' }
        end
      end

      context 'when not confirmed' do
        before do
          controller.find 'file3'
          controller.toggle_mark
          allow(controller).to receive(:ask).and_return(false)
          controller.d
        end

        it 'does not delete the file' do
          controller.items.should be_any { |i| i.name == 'file3' }
        end
      end

      context 'when no items selected' do
        before do
          controller.move_cursor 0  # on .
          controller.d
        end

        it 'does nothing' do
          # Should not raise and items unchanged
          controller.items.size.should be > 2
        end
      end
    end

    describe '#D (hard delete)' do
      context 'when confirmed' do
        before do
          controller.find 'file3'
          controller.toggle_mark
          allow(controller).to receive(:ask).and_return(true)
          controller.D
        end

        it 'deletes the file' do
          controller.items.should be_none { |i| i.name == 'file3' }
        end
      end

      context 'when not confirmed' do
        before do
          controller.find 'file3'
          controller.toggle_mark
          allow(controller).to receive(:ask).and_return(false)
          controller.D
        end

        it 'does not delete the file' do
          controller.items.should be_any { |i| i.name == 'file3' }
        end
      end
    end
  end

  describe 'quit commands' do
    describe '#q (quit with confirmation)' do
      context 'when confirmed' do
        it 'raises StopIteration' do
          allow(controller).to receive(:ask).and_return(true)
          expect { controller.q }.to raise_error(StopIteration)
        end
      end

      context 'when not confirmed' do
        it 'does not raise' do
          allow(controller).to receive(:ask).and_return(false)
          expect { controller.q }.not_to raise_error
        end
      end
    end

    describe '#q! (force quit)' do
      it 'raises StopIteration without confirmation' do
        expect { controller.public_send('q!') }.to raise_error(StopIteration)
      end
    end
  end

  describe 'directory commands' do
    describe '#enter' do
      context 'when on a directory' do
        before do
          controller.find 'dir1'
          controller.enter
        end
        its('current_dir.path') { should == File.join(tmpdir, 'dir1') }
      end

      context 'when on ..' do
        before do
          controller.cd 'dir1'
          controller.move_cursor 1
          controller.enter
        end
        its('current_dir.path') { should == tmpdir }
      end

      context 'when on .' do
        before do
          @original_dir = controller.current_dir.path
          controller.move_cursor 0
          controller.enter
        end
        it 'does nothing' do
          controller.current_dir.path.should == @original_dir
        end
      end

    end

    describe '#backspace (go to parent directory)' do
      before do
        controller.cd 'dir1'
        controller.backspace
      end

      its('current_dir.path') { should == tmpdir }

      it 'positions cursor on the directory we came from' do
        controller.current_item.name.should == 'dir1'
      end
    end


    describe '#- (popd)' do
      before do
        controller.cd 'dir1'
        controller.public_send('-')
      end
      its('current_dir.path') { should == tmpdir }
    end

    describe '#~ (go to home)' do
      before { controller.public_send('~') }
      its('current_dir.path') { should == File.expand_path('~') }
    end
  end

  describe 'direct wrapper commands' do
    describe '#u (unarchive)' do
      before do
        controller.find 'zip1.zip'
        controller.toggle_mark
        controller.u
      end
      it 'extracts the archive' do
        File.should be_exist File.join(tmpdir, 'zip1', 'zip_content1')
      end
    end

    describe '#y (yank)' do
      before do
        controller.find 'file1'
        controller.toggle_mark
        controller.y
      end
      it 'yanks the selected items' do
        controller.instance_variable_get(:@yanked_items).map(&:name).should include('file1')
      end
    end

    describe '#p (paste)' do
      before do
        controller.find 'file1'
        controller.toggle_mark
        controller.y
        controller.find 'dir1'
        controller.p
      end
      it 'pastes the yanked items' do
        File.should be_exist File.join(tmpdir, 'dir1', 'file1')
      end
    end

    describe '#C (clipboard)' do
      before do
        controller.find 'file1'
        controller.toggle_mark
        allow(controller).to receive(:clipboard_command).and_return('pbcopy')
        allow(IO).to receive(:popen).with('pbcopy', 'w').and_yield(StringIO.new)
      end

      it 'copies to clipboard' do
        controller.C
        expect(IO).to have_received(:popen).with('pbcopy', 'w')
      end
    end
  end

  describe 'screen commands' do
    describe '#^l (refresh)' do
      before do
        @original_items_count = items.size
        controller.public_send :'^l'
      end
      it 'refreshes the listing' do
        controller.items.size.should == @original_items_count
      end
    end

    describe '#^w (split panes)' do
      before do
        controller.public_send('2')
        controller.public_send :'^w'
      end
      it 'changes the number of panes' do
        controller.main.instance_variable_get(:@number_of_panes).should == 2
      end
    end

    describe '#^w without times' do
      before do
        @original_panes = controller.main.instance_variable_get(:@number_of_panes)
        controller.public_send :'^w'
      end
      it 'does nothing' do
        controller.main.instance_variable_get(:@number_of_panes).should == @original_panes
      end
    end
  end

  describe 'command line wrappers' do
    describe '#a (chmod)' do
      it 'calls process_command_line with chmod' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'chmod')
        controller.a
      end
    end

    describe '#c (cp)' do
      it 'opens NavigationWindow for destination selection' do
        controller.c
        expect(controller.instance_variable_get(:@sub_window)).to be_a(Rfd::NavigationWindow)
      end
    end

    describe '#m (mv)' do
      it 'opens NavigationWindow for destination selection' do
        controller.m
        expect(controller.instance_variable_get(:@sub_window)).to be_a(Rfd::NavigationWindow)
      end
    end

    describe '#r (rename)' do
      it 'calls process_command_line with rename' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'rename')
        controller.r
      end
    end

    describe '#s (sort)' do
      it 'calls process_command_line with sort' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'sort')
        controller.s
      end
    end

    describe '#t (touch)' do
      it 'calls process_command_line with touch' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'touch')
        controller.t
      end
    end

    describe '#w (chown)' do
      it 'calls process_command_line with chown' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'chown')
        controller.w
      end
    end

    describe '#z (zip)' do
      it 'calls process_command_line with zip' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'zip')
        controller.z
      end
    end

    describe '#K (mkdir)' do
      it 'calls process_command_line with mkdir' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'mkdir')
        controller.K
      end
    end

    describe '#S (symlink)' do
      it 'calls process_command_line with symlink' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'symlink')
        controller.S
      end
    end

    describe '#T (touch_t)' do
      it 'calls process_command_line with touch_t and default argument' do
        controller.find 'file1'
        expect(controller).to receive(:process_command_line).with(
          preset_command: 'touch_t',
          default_argument: controller.current_item.mtime.tr(': -', '')
        )
        controller.T
      end
    end

    describe '#/ (grep)' do
      it 'calls process_command_line with grep' do
        expect(controller).to receive(:process_command_line).with(preset_command: 'grep')
        controller.public_send('/')
      end
    end

    describe '#@ (navigation)' do
      it 'opens NavigationWindow' do
        controller.public_send('@')
        expect(controller.instance_variable_get(:@sub_window)).to be_a(Rfd::NavigationWindow)
      end
    end

    describe '#: (command line)' do
      it 'calls process_command_line without preset' do
        expect(controller).to receive(:process_command_line)
        controller.public_send(':')
      end
    end
  end

  describe 'external commands' do
    describe '#o (open)' do
      context 'when items are selected' do
        before do
          controller.find 'file1'
          controller.toggle_mark
          allow(controller).to receive(:system)
        end

        it 'calls system open' do
          controller.o
          expect(controller).to have_received(:system).with('open', anything)
        end
      end

      context 'when on . or ..' do
        before do
          controller.move_cursor 0
          allow(controller).to receive(:system)
        end

        it 'opens the current directory' do
          controller.o
          expect(controller).to have_received(:system).with('open', controller.current_item.path)
        end
      end
    end

    describe '#! (shell command)' do
      it 'calls process_shell_command' do
        expect(controller).to receive(:process_shell_command)
        controller.public_send('!')
      end
    end

    describe '#? (help)' do
      it 'calls help' do
        expect(controller).to receive(:help)
        controller.public_send('?')
      end
    end
  end

  describe 'view commands' do
    describe '#v (view)' do
      it 'calls view' do
        expect(controller).to receive(:view)
        controller.v
      end
    end

    describe '#e (edit)' do
      it 'calls edit' do
        expect(controller).to receive(:edit)
        controller.e
      end
    end

    describe '#P (preview)' do
      it 'calls preview' do
        expect(controller).to receive(:preview)
        controller.P
      end
    end
  end

  describe 'mouse commands' do
    describe '#click' do
      it 'calls move_cursor_by_click' do
        expect(controller).to receive(:move_cursor_by_click).with(y: 5, x: 10)
        controller.click(y: 5, x: 10)
      end
    end

    describe '#double_click' do
      context 'when click succeeds' do
        before do
          allow(controller).to receive(:move_cursor_by_click).and_return(true)
          allow(controller).to receive(:enter)
        end

        it 'calls enter after moving cursor' do
          controller.double_click(y: 5, x: 10)
          expect(controller).to have_received(:enter)
        end
      end

      context 'when click fails' do
        before do
          allow(controller).to receive(:move_cursor_by_click).and_return(false)
          allow(controller).to receive(:enter)
        end

        it 'does not call enter' do
          controller.double_click(y: 5, x: 10)
          expect(controller).not_to have_received(:enter)
        end
      end
    end
  end
end
