# coding: utf-8
# frozen_string_literal: true
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "rfd"
  spec.version       = '0.7.1'
  spec.authors       = ["Akira Matsuda"]
  spec.email         = ["ronnie@dio.jp"]
  spec.description   = 'A Ruby filer that runs on terminal'
  spec.summary       = 'Ruby on Files & Directories'
  spec.homepage      = 'https://github.com/amatsuda/rfd'
  spec.license       = "MIT"

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'curses', '>= 1.0.0'
  spec.add_dependency 'rubyzip', '>= 1.0.0'
  spec.add_dependency 'reline'
  spec.add_dependency 'logger'
  spec.add_dependency 'rouge'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency "rake"
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-its'
end
