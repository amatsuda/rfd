# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_group 'Core', 'lib/rfd.rb'
  add_group 'Commands', 'lib/rfd/commands.rb'
  add_group 'File Operations', 'lib/rfd/file_ops.rb'
  add_group 'Item', 'lib/rfd/item.rb'
  add_group 'Windows', 'lib/rfd/windows.rb'
  add_group 'Preview', 'lib/rfd/preview'
  add_group 'Other' do |src|
    src.filename.include?('lib/rfd/') &&
      !src.filename.include?('lib/rfd/preview') &&
      !src.filename.end_with?('commands.rb') &&
      !src.filename.end_with?('file_ops.rb') &&
      !src.filename.end_with?('item.rb') &&
      !src.filename.end_with?('windows.rb')
  end
end

$LOAD_PATH.unshift(File.join(__dir__, '..', 'lib'))
$LOAD_PATH.unshift(__dir__)

# Skip preview server in test environment (avoids fork/reopen conflicts)
ENV['RFD_SKIP_PREVIEW_SERVER'] = '1'
ENV['TERM'] ||= 'xterm-256color'

require 'rfd'

Dir[File.join __dir__, 'support/**/*.rb'].each {|f| require f}

require 'rspec/its'

RSpec.configure do |config|
  config.after(:suite) do
    Curses.close_screen rescue nil
  end
end
