# frozen_string_literal: true
require 'spec_helper'
require 'rfd'

describe Rfd::FileOps do
  include_context 'rfd setup'

  describe '#cd' do
    before do
      controller.cd 'dir1'
    end
    its('current_dir.path') { should == File.join(tmpdir, 'dir1') }

    describe '#popd' do
      before do
        controller.popd
      end
      its('current_dir.path') { should == tmpdir }
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
      Dir.mkdir File.join(tmpdir, '.a')
      stat = File.lstat File.join(tmpdir, '.a')
      Rfd::Item.new dir: tmpdir, name: '.a', stat: stat, window_width: 100
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

    context 'With an octet string' do
      before do
        item.toggle_mark
        controller.chmod '666'
      end
      subject { controller.items.detect {|i| !i.directory?} }
      its(:mode) { should == '-rw-rw-rw-' }
    end

    context 'With a decimal string' do
      before do
        item.toggle_mark
        controller.chmod '0666'
      end
      subject { controller.items.detect {|i| !i.directory?} }
      its(:mode) { should == '-rw-rw-rw-' }
    end

    context 'With a non-numeric string' do
      before do
        item.toggle_mark
        controller.chmod 'a+w'
      end
      subject { controller.items.detect {|i| !i.directory?} }
      its(:mode) { should == '-rw-rw-rw-' }
    end
  end

  describe '#chown' do
    let(:item) { controller.items.detect {|i| !i.directory?} }
    subject { item }

    context 'With user name only' do
      before do
        expect(FileUtils).to receive(:chown).with('alice', nil, Array(item.path))
        item.toggle_mark
      end
      specify { controller.chown 'alice' }
    end

    context 'With group name only' do
      before do
        expect(FileUtils).to receive(:chown).with(nil, 'admin', Array(item.path))
        item.toggle_mark
      end
      specify { controller.chown ':admin' }
    end

    context 'With both user name and group name' do
      before do
        expect(FileUtils).to receive(:chown).with('nobody', 'nobody', Array(item.path))
        item.toggle_mark
      end
      specify { controller.chown 'nobody:nobody' }
    end
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
    subject { File }
    it { should be_exist File.join(tmpdir, 'dir2/file3') }
  end

  describe '#rename' do
    before do
      controller.find '.file2'
      controller.toggle_mark
      controller.find 'file3'
      controller.toggle_mark
      controller.rename 'fi/faaai'
    end
    subject { File }
    it { should be_exist File.join(tmpdir, '.faaaile2') }
    it { should be_exist File.join(tmpdir, 'faaaile3') }
  end

  describe '#trash' do
    before do
      controller.find 'file3'
      controller.toggle_mark
      # Stub the trash command to simulate successful trashing
      allow(controller).to receive(:system).with('trash', anything).and_return(true)
      allow(FileUtils).to receive(:rm_rf).and_call_original
      expect(FileUtils).to receive(:rm_rf).with([File.join(tmpdir, 'file3')]).once
      # Re-stub system to actually delete the file for test verification
      allow(controller).to receive(:system).with('trash', anything) do |cmd, *paths|
        FileUtils.rm_rf(paths)
        true
      end
      controller.trash
    end
    it 'should be properly deleted from the current directory' do
      controller.items.should be_none {|i| i.name == 'file3'}
    end
  end

  describe '#delete' do
    before do
      controller.find 'file3'
      controller.toggle_mark
      controller.find 'dir2'
      controller.toggle_mark
      controller.delete
    end
    it 'should be properly deleted from the current directory' do
      controller.items.should be_none {|i| i.name == 'file3'}
      controller.items.should be_none {|i| i.name == 'dir2'}
    end
  end

  describe '#mkdir' do
    before do
      controller.mkdir 'aho'
    end
    subject { Dir }
    it { should be_exist File.join(tmpdir, 'aho') }
  end

  describe '#touch' do
    before do
      controller.touch 'fuga'
    end
    subject { File }
    it { should be_exist File.join(tmpdir, 'fuga') }
  end

  describe '#symlink' do
    before do
      controller.find 'dir1'
      controller.symlink 'aaa'
    end
    subject { File }
    it { should be_symlink File.join(tmpdir, 'aaa') }
  end

  describe '#yank' do
    before do
      controller.find '.file1'
      controller.toggle_mark
      controller.find 'dir3'
      controller.toggle_mark
      controller.yank
    end
    it 'should be yanked' do
      controller.instance_variable_get(:@yanked_items).map(&:name).should =~ %w(.file1 dir3)
    end
  end

  describe '#paste' do
    before do
      controller.find '.file1'
      controller.toggle_mark
      controller.find 'dir3'
      controller.toggle_mark
      controller.yank
    end
    context 'when the cursor is on a directory' do
      before do
        controller.find 'dir1'
        controller.paste
      end
      subject { File }
      it { should be_exist File.join(tmpdir, 'dir1', '.file1') }
      it { should be_exist File.join(tmpdir, 'dir1', 'dir3') }
    end
    context 'when the cursor is on a file' do
      before do
        controller.find 'file2'
        controller.paste
      end
      subject { File }
      it { should be_exist File.join(tmpdir, '.file1_1') }
      it { should be_exist File.join(tmpdir, 'dir3_1') }
    end
  end

  if RbConfig::CONFIG['host_os'] =~ /darwin/
    describe '#clipboard' do
      before do
        controller.find '.file1'
        controller.toggle_mark
        controller.find 'dir3'
        controller.toggle_mark
        controller.clipboard
      end
      it 'copies the selected paths into clipboard' do
        `pbpaste`.should == "#{File.join(tmpdir, 'dir3')} #{File.join(tmpdir, '.file1')}"
      end
    end
  end

  describe '#zip' do
    before do
      controller.find 'dir1'
      controller.zip 'archive1'
    end
    subject { File }
    it { should be_exist File.join(tmpdir, 'archive1.zip') }
  end

  describe '#unarchive' do
    before do
      controller.find 'zip1'
      controller.toggle_mark
      controller.find 'gz1'
      controller.toggle_mark
      controller.unarchive
    end
    subject { File }
    it { should be_exist File.join(tmpdir, 'zip1/zip_content1') }
    it { should be_exist File.join(tmpdir, 'zip1/zip_content_dir1/zip_content1_1') }
    it { should be_exist File.join(tmpdir, 'gz1/gz_content1') }
    it { should be_exist File.join(tmpdir, 'gz1/gz_content_dir1/gz_content1_1') }
  end
end
