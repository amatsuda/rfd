# frozen_string_literal: true

module Rfd
  module HelpGenerator
    # Category mappings: [display_key, method_name]
    # Method name is used to look up the comment from commands.rb
    CATEGORIES = {
      'Navigation' => [
        ['j/k', :j, :k],
        ['h/l', :h, :l],
        ['g/G', :g, :G],
        ['H/M/L', :H, :M, :L],
        ['f{char}/F{char}', :f],
        ['n/N', :n, :N],
        ['Ctrl-n/p', :ctrl_n],
        ['Enter', :enter],
        ['Backspace', :del],
        ['-', :'-'],
        ['~', :'~'],
        ['@', :'@']
      ],
      'File Operations' => [
        ['Space', :space],
        ['Ctrl-a', :ctrl_a],
        ['c', :c],
        ['m', :m],
        ['r', :r],
        ['d/D', :d, :D],
        ['t/K', :t, :K],
        ['y/p', :y, :p],
        ['z/u', :z, :u],
        ['a', :a],
        ['w', :w],
        ['S', :S]
      ],
      'Viewing' => [
        ['v/e', :v, :e],
        ['o', :o],
        ['P', :P],
        ['/', :'/'],
        ['s', :s]
      ],
      'Other' => [
        ['C', :C],
        ['O', :O],
        ['Ctrl-w{n}', :ctrl_w],
        ['!', :'!'],
        [':', :':'],
        ['q', :q],
        ['?', :'?']
      ]
    }.freeze

    class << self
      def generate
        comments = parse_commands_file
        lines = []

        CATEGORIES.each do |category, entries|
          lines << category
          entries.each do |entry|
            key_display = entry[0]
            method_names = entry[1..]
            description = build_description(method_names, comments)
            lines << format("  %-14s %s", key_display, description)
          end
          lines << ""
        end

        lines << "Environment: RFD_NO_ICONS=1 to disable file icons (icons require Nerd Font)"
        lines.join("\n")
      end

      private

      def parse_commands_file
        commands_path = File.join(__dir__, 'commands.rb')
        source = File.read(commands_path)
        comments = {}

        # Match comments followed by method definitions
        # Handles: def name, def -, def /, define_method(:name), define_method(:'name')
        # Works with nested modules
        source.scan(/^\s*#\s*(.+?)\n\s*(?:def\s+(\S+)|define_method\(:'?([^')\s]+)'?\))/) do |comment, def_name, define_name|
          method_name = (def_name || define_name).to_sym
          comments[method_name] = clean_comment(comment)
        end

        comments
      end

      def clean_comment(comment)
        # Remove quoted key indicators like "c"opy -> copy
        # and clean up the description
        comment
          .gsub(/"(\w)"/, '\1')  # "c"opy -> copy
          .sub(/\.\s*$/, '')      # Remove trailing period
          .strip
      end

      def build_description(method_names, comments)
        # Use the first method's comment as the base description
        primary = method_names.first
        desc = comments[primary]
        return "No description" unless desc

        # Capitalize first letter
        desc = desc[0].upcase + desc[1..] if desc.length > 0
        desc
      end
    end
  end
end
