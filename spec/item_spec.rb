# frozen_string_literal: true
require 'spec_helper'
require 'rfd'
require 'tempfile'
require 'fileutils'

describe Rfd::Item do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rm_rf tmpdir }

  describe 'basic attributes' do
    let(:file_path) { File.join(tmpdir, 'test.txt') }
    before { FileUtils.touch file_path }
    let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

    it 'returns path' do
      expect(item.path).to eq(file_path)
    end

    it 'returns name' do
      expect(item.name).to eq('test.txt')
    end

    it 'returns dir' do
      expect(item.dir).to eq(tmpdir)
    end

    it 'returns basename' do
      expect(item.basename).to eq('test')
    end

    it 'returns extname' do
      expect(item.extname).to eq('.txt')
    end

    describe '#join' do
      let(:dir_path) { File.join(tmpdir, 'mydir') }
      before { FileUtils.mkdir dir_path }
      let(:item) { Rfd::Item.new(path: dir_path, window_width: 80) }

      it 'joins path segments' do
        expect(item.join('sub', 'file.txt')).to eq(File.join(dir_path, 'sub', 'file.txt'))
      end
    end
  end

  describe '#display_name' do
    context 'with short filename' do
      let(:file_path) { File.join(tmpdir, 'short.txt') }
      before { FileUtils.touch file_path }
      let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

      it 'returns the full name' do
        expect(item.display_name).to eq('short.txt')
      end
    end

    context 'with long filename' do
      let(:long_name) { 'a' * 60 + '.txt' }
      let(:file_path) { File.join(tmpdir, long_name) }
      before { FileUtils.touch file_path }
      let(:item) { Rfd::Item.new(path: file_path, window_width: 40) }

      it 'truncates the name with ellipsis' do
        expect(item.display_name).to include('…')
        expect(item.display_name).to end_with('.txt')
      end
    end
  end

  describe '#color' do
    context 'for symlink' do
      let(:target) { File.join(tmpdir, 'target.txt') }
      let(:link) { File.join(tmpdir, 'link') }
      before do
        FileUtils.touch target
        FileUtils.ln_s target, link
      end
      let(:item) { Rfd::Item.new(path: link, window_width: 80) }

      it 'returns magenta' do
        expect(item.color).to eq(Curses::COLOR_MAGENTA)
      end
    end

    context 'for hidden file' do
      let(:file_path) { File.join(tmpdir, '.hidden') }
      before { FileUtils.touch file_path }
      let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

      it 'returns green' do
        expect(item.color).to eq(Curses::COLOR_GREEN)
      end
    end

    context 'for directory' do
      let(:dir_path) { File.join(tmpdir, 'subdir') }
      before { FileUtils.mkdir dir_path }
      let(:item) { Rfd::Item.new(path: dir_path, window_width: 80) }

      it 'returns cyan' do
        expect(item.color).to eq(Curses::COLOR_CYAN)
      end
    end

    context 'for executable' do
      let(:file_path) { File.join(tmpdir, 'script.sh') }
      before do
        FileUtils.touch file_path
        FileUtils.chmod 0755, file_path
      end
      let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

      it 'returns red' do
        expect(item.color).to eq(Curses::COLOR_RED)
      end
    end

    context 'for regular file' do
      let(:file_path) { File.join(tmpdir, 'regular.txt') }
      before { FileUtils.touch file_path }
      let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

      it 'returns white' do
        expect(item.color).to eq(Curses::COLOR_WHITE)
      end
    end
  end

  describe '#size and #size_or_dir' do
    context 'for file' do
      let(:file_path) { File.join(tmpdir, 'sized.txt') }
      before { File.write(file_path, 'hello') }
      let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

      it 'returns file size' do
        expect(item.size).to eq(5)
      end

      it 'returns size as string' do
        expect(item.size_or_dir).to eq('5')
      end
    end

    context 'for directory' do
      let(:dir_path) { File.join(tmpdir, 'sizedir') }
      before { FileUtils.mkdir dir_path }
      let(:item) { Rfd::Item.new(path: dir_path, window_width: 80) }

      it 'returns 0 for size' do
        expect(item.size).to eq(0)
      end

      it 'returns <DIR>' do
        expect(item.size_or_dir).to eq('<DIR>')
      end
    end
  end

  describe 'time accessors' do
    let(:file_path) { File.join(tmpdir, 'timed.txt') }
    before { FileUtils.touch file_path }
    let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

    it 'returns formatted atime' do
      expect(item.atime).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end

    it 'returns formatted ctime' do
      expect(item.ctime).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end

    it 'returns formatted mtime' do
      expect(item.mtime).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end
  end

  describe '#mode' do
    context 'for regular file with 644' do
      let(:file_path) { File.join(tmpdir, 'mode644.txt') }
      before do
        FileUtils.touch file_path
        FileUtils.chmod 0644, file_path
      end
      let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

      it 'returns -rw-r--r--' do
        expect(item.mode).to eq('-rw-r--r--')
      end
    end

    context 'for executable with 755' do
      let(:file_path) { File.join(tmpdir, 'mode755.sh') }
      before do
        FileUtils.touch file_path
        FileUtils.chmod 0755, file_path
      end
      let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

      it 'returns -rwxr-xr-x' do
        expect(item.mode).to eq('-rwxr-xr-x')
      end
    end

    context 'for directory' do
      let(:dir_path) { File.join(tmpdir, 'modedir') }
      before do
        FileUtils.mkdir dir_path
        FileUtils.chmod 0755, dir_path
      end
      let(:item) { Rfd::Item.new(path: dir_path, window_width: 80) }

      it 'returns drwxr-xr-x' do
        expect(item.mode).to eq('drwxr-xr-x')
      end
    end

    context 'for symlink' do
      let(:target) { File.join(tmpdir, 'linktarget.txt') }
      let(:link) { File.join(tmpdir, 'modelink') }
      before do
        FileUtils.touch target
        FileUtils.ln_s target, link
      end
      let(:item) { Rfd::Item.new(path: link, window_width: 80) }

      it 'starts with l' do
        expect(item.mode).to start_with('l')
      end
    end
  end

  describe 'file type predicates' do
    describe '#directory?' do
      let(:dir_path) { File.join(tmpdir, 'testdir') }
      before { FileUtils.mkdir dir_path }
      let(:item) { Rfd::Item.new(path: dir_path, window_width: 80) }

      it 'returns true for directory' do
        expect(item.directory?).to be true
      end

      context 'for symlink to directory' do
        let(:link) { File.join(tmpdir, 'dirlink') }
        before { FileUtils.ln_s dir_path, link }
        let(:link_item) { Rfd::Item.new(path: link, window_width: 80) }

        it 'returns true' do
          expect(link_item.directory?).to be true
        end
      end

      context 'for broken symlink' do
        let(:link) { File.join(tmpdir, 'brokenlink') }
        before { FileUtils.ln_s '/nonexistent/path', link }
        let(:link_item) { Rfd::Item.new(path: link, window_width: 80) }

        it 'returns false' do
          expect(link_item.directory?).to be false
        end
      end
    end

    describe '#hidden?' do
      it 'returns true for dotfiles' do
        file_path = File.join(tmpdir, '.hidden')
        FileUtils.touch file_path
        item = Rfd::Item.new(path: file_path, window_width: 80)
        expect(item.hidden?).to be true
      end

      it 'returns false for . directory' do
        item = Rfd::Item.new(dir: tmpdir, name: '.', window_width: 80)
        expect(item.hidden?).to be false
      end

      it 'returns false for .. directory' do
        item = Rfd::Item.new(dir: tmpdir, name: '..', window_width: 80)
        expect(item.hidden?).to be false
      end
    end
  end

  describe 'archive detection' do
    describe '#zip?' do
      it 'returns true for valid zip file' do
        zip_path = File.join(tmpdir, 'test.zip')
        Zip::File.open(zip_path, create: true) { |z| z.get_output_stream('dummy.txt') { |f| f.write 'test' } }
        item = Rfd::Item.new(path: zip_path, window_width: 80)
        expect(item.zip?).to be true
      end

      it 'returns false for non-zip file' do
        file_path = File.join(tmpdir, 'notzip.txt')
        File.write(file_path, 'not a zip')
        item = Rfd::Item.new(path: file_path, window_width: 80)
        expect(item.zip?).to be false
      end

      it 'returns false for directory' do
        dir_path = File.join(tmpdir, 'zipdir')
        FileUtils.mkdir dir_path
        item = Rfd::Item.new(path: dir_path, window_width: 80)
        expect(item.zip?).to be false
      end
    end

    describe '#gz?' do
      it 'returns true for gzip file' do
        gz_path = File.join(tmpdir, 'test.gz')
        Zlib::GzipWriter.open(gz_path) { |gz| gz.write 'test' }
        item = Rfd::Item.new(path: gz_path, window_width: 80)
        expect(item.gz?).to be true
      end

      it 'returns false for non-gzip file' do
        file_path = File.join(tmpdir, 'notgz.txt')
        File.write(file_path, 'not gzip')
        item = Rfd::Item.new(path: file_path, window_width: 80)
        expect(item.gz?).to be false
      end
    end
  end

  describe 'media type detection' do
    describe '#markdown?' do
      it 'returns true for .md files' do
        file_path = File.join(tmpdir, 'readme.md')
        FileUtils.touch file_path
        item = Rfd::Item.new(path: file_path, window_width: 80)
        expect(item.markdown?).to be true
      end

      it 'returns true for .markdown files' do
        file_path = File.join(tmpdir, 'readme.markdown')
        FileUtils.touch file_path
        item = Rfd::Item.new(path: file_path, window_width: 80)
        expect(item.markdown?).to be true
      end

      it 'returns false for other files' do
        file_path = File.join(tmpdir, 'readme.txt')
        FileUtils.touch file_path
        item = Rfd::Item.new(path: file_path, window_width: 80)
        expect(item.markdown?).to be false
      end
    end

    describe '#audio?' do
      %w[.mp3 .wav .flac .ogg .m4a .aac].each do |ext|
        it "returns true for #{ext} files" do
          file_path = File.join(tmpdir, "audio#{ext}")
          FileUtils.touch file_path
          item = Rfd::Item.new(path: file_path, window_width: 80)
          expect(item.audio?).to be true
        end
      end
    end

    describe '#video?' do
      %w[.mp4 .avi .mov .mkv .webm].each do |ext|
        it "returns true for #{ext} files" do
          file_path = File.join(tmpdir, "video#{ext}")
          FileUtils.touch file_path
          item = Rfd::Item.new(path: file_path, window_width: 80)
          expect(item.video?).to be true
        end
      end
    end
  end

  describe '#preview_type' do
    it 'returns :directory for directories' do
      dir_path = File.join(tmpdir, 'previewdir')
      FileUtils.mkdir dir_path
      item = Rfd::Item.new(path: dir_path, window_width: 80)
      expect(item.preview_type).to eq(:directory)
    end

    it 'returns :video for video files' do
      file_path = File.join(tmpdir, 'video.mp4')
      FileUtils.touch file_path
      item = Rfd::Item.new(path: file_path, window_width: 80)
      expect(item.preview_type).to eq(:video)
    end

    it 'returns :markdown for markdown files' do
      file_path = File.join(tmpdir, 'doc.md')
      FileUtils.touch file_path
      item = Rfd::Item.new(path: file_path, window_width: 80)
      expect(item.preview_type).to eq(:markdown)
    end

    it 'returns :text for regular files' do
      file_path = File.join(tmpdir, 'plain.txt')
      FileUtils.touch file_path
      item = Rfd::Item.new(path: file_path, window_width: 80)
      expect(item.preview_type).to eq(:text)
    end
  end

  describe '#target' do
    let(:target_path) { File.join(tmpdir, 'target.txt') }
    let(:link_path) { File.join(tmpdir, 'link') }
    before do
      FileUtils.touch target_path
      FileUtils.ln_s target_path, link_path
    end

    it 'returns the symlink target' do
      item = Rfd::Item.new(path: link_path, window_width: 80)
      expect(item.target).to eq(target_path)
    end

    it 'returns nil for non-symlinks' do
      item = Rfd::Item.new(path: target_path, window_width: 80)
      expect(item.target).to be_nil
    end
  end

  describe 'marking' do
    let(:file_path) { File.join(tmpdir, 'markable.txt') }
    before { FileUtils.touch file_path }
    let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

    it 'starts unmarked' do
      expect(item.marked?).to be false
    end

    it 'can be toggled' do
      item.toggle_mark
      expect(item.marked?).to be true
    end

    it 'can be toggled off' do
      item.toggle_mark
      item.toggle_mark
      expect(item.marked?).to be false
    end

    describe '#current_mark' do
      it 'returns space when unmarked' do
        expect(item.current_mark).to eq(' ')
      end

      it 'returns * when marked' do
        item.toggle_mark
        expect(item.current_mark).to eq('*')
      end
    end

    context 'for . and ..' do
      it 'cannot toggle . directory' do
        dot_item = Rfd::Item.new(dir: tmpdir, name: '.', window_width: 80)
        expect(dot_item.toggle_mark).to be_nil
        expect(dot_item.marked?).to be false
      end

      it 'cannot toggle .. directory' do
        dotdot_item = Rfd::Item.new(dir: tmpdir, name: '..', window_width: 80)
        expect(dotdot_item.toggle_mark).to be_nil
        expect(dotdot_item.marked?).to be false
      end
    end
  end

  describe '#icon' do
    let(:file_path) { File.join(tmpdir, 'icontest.rb') }
    before { FileUtils.touch file_path }

    it 'returns ruby icon for .rb files' do
      item = Rfd::Item.new(path: file_path, window_width: 80)
      expect(item.icon).to eq(Rfd::Item::ICON_RUBY)
    end

    it 'returns directory icon for directories' do
      dir_path = File.join(tmpdir, 'icondir')
      FileUtils.mkdir dir_path
      item = Rfd::Item.new(path: dir_path, window_width: 80)
      expect(item.icon).to eq(Rfd::Item::ICON_DIRECTORY)
    end

    it 'returns symlink icon for symlinks' do
      target = File.join(tmpdir, 'icontarget')
      link = File.join(tmpdir, 'iconlink')
      FileUtils.touch target
      FileUtils.ln_s target, link
      item = Rfd::Item.new(path: link, window_width: 80)
      expect(item.icon).to eq(Rfd::Item::ICON_SYMLINK)
    end

    it 'returns generic file icon for unknown extensions' do
      unknown = File.join(tmpdir, 'unknown.xyz')
      FileUtils.touch unknown
      item = Rfd::Item.new(path: unknown, window_width: 80)
      expect(item.icon).to eq(Rfd::Item::ICON_FILE)
    end

    context 'with RFD_NO_ICONS' do
      around do |example|
        ENV['RFD_NO_ICONS'] = '1'
        example.run
        ENV.delete('RFD_NO_ICONS')
      end

      it 'returns empty string' do
        item = Rfd::Item.new(path: file_path, window_width: 80)
        expect(item.icon).to eq('')
      end
    end
  end

  describe 'multi-byte string methods' do
    let(:file_path) { File.join(tmpdir, 'mb.txt') }
    before { FileUtils.touch file_path }
    let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

    describe '#mb_char_size' do
      it 'returns 1 for ASCII' do
        expect(item.mb_char_size('a')).to eq(1)
      end

      it 'returns 2 for wide characters' do
        expect(item.mb_char_size('日')).to eq(2)
      end

      it 'returns 1 for ellipsis' do
        expect(item.mb_char_size('…')).to eq(1)
      end
    end

    describe '#mb_size' do
      it 'calculates mixed string size' do
        expect(item.mb_size('abc')).to eq(3)
        expect(item.mb_size('日本語')).to eq(6)
        expect(item.mb_size('a日b')).to eq(4)
      end
    end

    describe '#mb_ljust' do
      it 'pads with spaces' do
        expect(item.mb_ljust('abc', 6)).to eq('abc   ')
      end

      it 'handles wide characters' do
        expect(item.mb_ljust('日本', 6)).to eq('日本  ')
      end
    end

    describe '#mb_left' do
      it 'truncates to fit width' do
        expect(item.mb_left('abcdef', 3)).to eq('abc')
      end

      it 'handles wide characters correctly' do
        expect(item.mb_left('日本語abc', 4)).to eq('日本')
      end
    end
  end

  describe '#to_s' do
    let(:file_path) { File.join(tmpdir, 'tostring.txt') }
    before { File.write(file_path, 'x' * 100) }
    let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

    it 'includes the mark, icon, name, and size' do
      str = item.to_s
      expect(str).to include('tostring.txt')
      expect(str).to include('100')
    end
  end

  describe '#to_str' do
    let(:file_path) { File.join(tmpdir, 'path.txt') }
    before { FileUtils.touch file_path }
    let(:item) { Rfd::Item.new(path: file_path, window_width: 80) }

    it 'returns the path' do
      expect(item.to_str).to eq(file_path)
    end
  end

  describe 'Comparable' do
    let(:dir_path) { File.join(tmpdir, 'adir') }
    let(:file1_path) { File.join(tmpdir, 'afile.txt') }
    let(:file2_path) { File.join(tmpdir, 'bfile.txt') }
    before do
      FileUtils.mkdir dir_path
      FileUtils.touch file1_path
      FileUtils.touch file2_path
    end

    it 'sorts directories after files with same starting letter' do
      dir = Rfd::Item.new(path: dir_path, window_width: 80)
      file = Rfd::Item.new(path: file1_path, window_width: 80)
      expect(dir <=> file).to eq(1)
      expect(file <=> dir).to eq(-1)
    end

    it 'sorts files by name' do
      file1 = Rfd::Item.new(path: file1_path, window_width: 80)
      file2 = Rfd::Item.new(path: file2_path, window_width: 80)
      expect(file1 <=> file2).to eq(-1)
    end
  end
end
