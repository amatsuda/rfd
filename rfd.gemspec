# coding: utf-8
# frozen_string_literal: true
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "rfd"
  spec.version       = '0.6.8'
  spec.authors       = ["Akira Matsuda"]
  spec.email         = ["ronnie@dio.jp"]
  spec.description   = 'Ruby on Files & Directories'
  spec.summary       = 'Ruby on Files & Directories'
  spec.homepage      = 'https://github.com/amatsuda/rfd'
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'curses', '>= 1.0.0'
  spec.add_dependency 'rubyzip', '>= 1.0.0'
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake", "< 11.0"
  spec.add_development_dependency 'rspec', "< 2.99"
end
