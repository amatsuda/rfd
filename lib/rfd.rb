# frozen_string_literal: true
require 'curses'
require 'fileutils'
require 'time'
require 'tmpdir'
require 'rubygems/package'
require 'zip'
require 'zip/filesystem'
require 'reline'
require 'rouge'
require_relative 'rfd/commands'
require_relative 'rfd/item'
require_relative 'rfd/windows'
require_relative 'rfd/logging'
require_relative 'rfd/reline_ext'
require_relative 'rfd/file_ops'
require_relative 'rfd/viewer'
require_relative 'rfd/sub_window'
require_relative 'rfd/preview_window'
require_relative 'rfd/navigation_window'
require_relative 'rfd/preview/server'
require_relative 'rfd/preview/client'
require_relative 'rfd/help_generator'
require_relative 'rfd/bookmark'
require_relative 'rfd/filter_input'
require_relative 'rfd/bookmark_window'
require_relative 'rfd/controller'

module Rfd
  VERSION = Gem.loaded_specs['rfd'] ? Gem.loaded_specs['rfd'].version.to_s : '0'

  # :nodoc:
  def self.init_curses
    # Set locale for proper wide character support
    ENV['LC_ALL'] ||= 'en_US.UTF-8'

    Curses.init_screen
    Curses.raw
    Curses.noecho
    Curses.curs_set 0
    Curses.stdscr.keypad = true
    print "\e[?25l"  # Hide cursor via ANSI escape sequence
    Curses.start_color

    [Curses::COLOR_WHITE, Curses::COLOR_CYAN, Curses::COLOR_MAGENTA, Curses::COLOR_GREEN, Curses::COLOR_RED].each do |c|
      Curses.init_pair c, c, Curses::COLOR_BLACK
    end

    Curses.mousemask Curses::BUTTON1_CLICKED | Curses::BUTTON1_DOUBLE_CLICKED

    # Enable extended key codes for better Unicode support
    Curses.stdscr.keypad = true
  end

  # Start the app here!
  #
  # ==== Parameters
  # * +dir+ - The initial directory.
  def self.start(dir = '.', log: nil)
    Rfd.log_to log if log

    Bookmark.load
    init_curses
    Rfd::Window.draw_borders
    Curses.stdscr.noutrefresh
    rfd = Rfd::Controller.new
    rfd.cd dir
    rfd.preview  # Show preview by default
    Curses.doupdate
    rfd
  end
end
