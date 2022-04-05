# frozen_string_literal: true
$LOAD_PATH.unshift(File.join(__dir__, '..', 'lib'))
$LOAD_PATH.unshift(__dir__)

require 'rfd'

Dir[File.join __dir__, 'support/**/*.rb'].each {|f| require f}

require 'rspec/its'
