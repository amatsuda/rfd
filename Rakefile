# frozen_string_literal: true
require 'bundler'
Bundler::GemHelper.install_tasks
require "bundler/gem_tasks"

require 'rspec/core'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

task :default => :spec

namespace :build do
  desc 'Generate help text cache'
  task :help do
    require_relative 'lib/rfd/help_generator'
    Rfd::HelpGenerator.write_cache
    puts "Generated #{Rfd::HelpGenerator::CACHE_FILE}"
  end
end

# Generate help before building the gem
Rake::Task[:build].enhance(['build:help'])
