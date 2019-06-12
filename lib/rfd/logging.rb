# frozen_string_literal: true

require 'logger'

module Rfd
  @logger = nil

  class << self
    def log_to(file)
      @logger = Logger.new file
      @logger.debug 'hello'

      Rfd::Controller.include Logging
    end

    attr_reader :logger
  end

  module Logging
    def self.included(m)
      mod = Module.new do
        (m.instance_methods - Object.instance_methods).each do |meth|
          Rfd.logger.info meth
          define_method(meth) {|*args, &block| Rfd.logger.debug "calling #{meth}(#{args.inspect})"; super(*args, &block) }
        end
      end
      m.prepend mod
    end
  end
end
