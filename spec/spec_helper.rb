# frozen_string_literal: true
$LOAD_PATH.unshift(File.join(__dir__, '..', 'lib'))
$LOAD_PATH.unshift(__dir__)

# Skip preview server in test environment (avoids fork/reopen conflicts)
ENV['RFD_SKIP_PREVIEW_SERVER'] = '1'

require 'rfd'

Dir[File.join __dir__, 'support/**/*.rb'].each {|f| require f}

require 'rspec/its'

RSpec.configure do |config|
  config.after(:suite) do
    Curses.close_screen rescue nil
  end
end
