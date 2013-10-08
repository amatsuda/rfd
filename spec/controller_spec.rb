require 'spec_helper'
require 'rfd'

describe Rfd::Controller do
  include CaptureHelper

  around do |example|
    @stdout = capture(:stdout) do
      FileUtils.cp_r File.join(__dir__, 'testdir'), tmpdir
      @rfd = Rfd.start tmpdir
      def (@rfd.main).maxy
        3
      end

      example.run

      FileUtils.rm_r tmpdir
      Dir.chdir __dir__
    end
  end

  after :all do
    Curses.endwin
  end

  let(:tmpdir) { File.join __dir__, 'tmpdir' }
  let!(:controller) { @rfd }
  subject { controller }
  let(:items) { controller.items }

  describe '#spawn_panes' do
    before { controller.spawn_panes 3 }

    subject { controller.main.instance_variable_get :@panes }
    it { should have(3).panes }
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
      its(:current_row) { should == 0 }
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
        subject { controller.main.instance_variable_get :@panes }
        its(:current_index) { should == 1 }
      end

      context 'When moving to the second page' do
        before do
          controller.move_cursor 7
        end
        its(:current_page) { should == 1 }
      end
    end
  end

  describe '#cd' do
    before do
      controller.cd 'dir1'
    end
    its(:current_dir) { should == File.join(tmpdir, 'dir1') }

    describe '#popd' do
      before do
        controller.popd
      end
      its(:current_dir) { should == tmpdir }
    end
  end

  describe '#ls' do
    before do
      controller.instance_variable_set :@items, []
      controller.ls
    end
    its(:items) { should_not be_empty }
  end

  describe '#sort' do
    let(:item) do
      Dir.mkdir File.join tmpdir, '.a'
      Rfd::Item.new dir: tmpdir, name: '.a', window_width: 100
    end
    before do
      controller.items << item
      controller.sort
    end
    subject { item }
    its(:index) { should == 2 }  # . .. then next
  end

  describe '#chmod' do
    let(:item) { controller.items.detect {|i| !i.directory?} }
    subject { item }

    context 'With an octet string' do
      before do
        item.toggle_mark
        controller.chmod '666'
        item.instance_variable_set :@lstat, nil  # clear cached value
        item.instance_variable_set :@mode, nil  # clear cached value
      end
      its(:mode) { should == '-rw-rw-rw-' }
    end

    context 'With a decimal string' do
      before do
        item.toggle_mark
        controller.chmod '0666'
        item.instance_variable_set :@lstat, nil  # clear cached value
        item.instance_variable_set :@mode, nil  # clear cached value
      end
      its(:mode) { should == '-rw-rw-rw-' }
    end

    context 'With a non-numeric string' do
      before do
        item.toggle_mark
        controller.chmod 'a+w'
        item.instance_variable_set :@lstat, nil  # clear cached value
        item.instance_variable_set :@mode, nil  # clear cached value
      end
      its(:mode) { should == '-rw-rw-rw-' }
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

  describe '#grep' do
    before do
      controller.grep 'dir'
    end
    subject { controller.items[2..-1] }
    its(:size) { should be > 2 }
    it "all items' name should include 'dir'" do
      subject.all? {|i| i.name.should include('dir')}
    end
  end

  describe '#cp' do
    before do
      controller.find 'file1'
      controller.cp 'file4'
    end
    it 'should be the same file as the copy source file' do
      File.read(File.join(tmpdir, 'file1')).should == File.read(File.join(tmpdir, 'file4'))
    end
  end

  describe '#mv' do
    before do
      controller.find 'file3'
      controller.mv 'dir2'
    end
    it 'should move current file to the specified directory' do
      File.exist?(File.join(tmpdir, 'dir2/file3')).should == true
    end
  end

  describe '#rename' do
    before do
      controller.find '.file2'
      controller.toggle_mark
      controller.find 'file3'
      controller.toggle_mark
      controller.rename 'fi/faaai'
    end
    it 'should rename selected files' do
      File.exist?(File.join(tmpdir, '.faaaile2')).should == true
      File.exist?(File.join(tmpdir, 'faaaile3')).should == true
    end
  end

  describe '#trash' do
    before do
      controller.find 'file3'
      controller.toggle_mark
      controller.trash
    end
    it 'should be properly deleted from the current directory' do
      controller.items.none? {|i| i.name == 'file3'}.should == true
    end
  end

  describe '#mkdir' do
    before do
      controller.mkdir 'aho'
    end
    it 'should create a new directory' do
      Dir.exist?(File.join(tmpdir, 'aho')).should == true
    end
  end

  describe '#touch' do
    before do
      controller.touch 'fuga'
    end
    it 'should create a new file' do
      File.exist?(File.join(tmpdir, 'fuga')).should == true
    end
  end

  describe '#first_page? and #last_page?' do
    context 'When on the first page' do
      it { should be_first_page }
      it { should_not be_last_page }
    end
    context 'When on the first page' do
      before do
        controller.k
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
