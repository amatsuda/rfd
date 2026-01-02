# frozen_string_literal: true

RSpec.shared_context 'rfd setup' do
  include CaptureHelper

  SPEC_DIR = File.expand_path('..', __dir__) unless defined?(SPEC_DIR)

  let(:spec_dir) { SPEC_DIR }
  let(:tmpdir) { File.join SPEC_DIR, 'tmpdir' }

  around do |example|
    @stdout = capture(:stdout) do
      FileUtils.cp_r File.join(SPEC_DIR, 'testdir'), File.join(SPEC_DIR, 'tmpdir')
      @rfd = Rfd.start File.join(SPEC_DIR, 'tmpdir')
      def (@rfd.main).maxy
        3
      end
      @rfd.ls  # Refresh with stubbed maxy

      example.run

      FileUtils.rm_r File.join(SPEC_DIR, 'tmpdir')
      Dir.chdir SPEC_DIR
    end
  end

  after :all do
    Curses.close_screen
  end

  let!(:controller) { @rfd }
  subject { controller }
  let(:items) { controller.items }
end
