# frozen_string_literal: true

# Ensure commands are loaded to register groups
require_relative 'commands' unless defined?(Rfd::Commands)

module Rfd
  module HelpGenerator
    class << self
      def generate
        comments, lines = parse_comments, []

        Rfd::Commands.categories.each do |category|
          entries = build_entries_for(category, comments)
          next if entries.empty?

          display_name = category.name.split('::').last.gsub(/([a-z])([A-Z])/, '\1 \2')
          lines << display_name
          entries.each do |entry|
            lines << format("  %-14s %s", entry[:key], entry[:description])
          end
          lines << ''
        end

        lines << 'Environment: RFD_NO_ICONS=1 to disable file icons (icons require Nerd Font)'
        lines.join("\n")
      end

      private

      def build_entries_for(category, comments)
        entries, seen_methods  = [], Set.new

        # Get groups for this module
        groups = Rfd::Commands.command_groups.select {|g| g[:category] == category }
        groups.each do |group|
          description = group[:description].sub(/\.\s*$/, '')
          entries << {key: group[:label], description: description}
          seen_methods.merge(group[:methods])
        end

        # Get standalone methods from the module
        category.instance_methods(false).each do |method_name|
          next if seen_methods.include?(method_name)
          next if Rfd::Commands.no_help_methods.include?(method_name)

          comment = comments[method_name] || {}
          key = comment[:key] || method_name.to_s
          description = comment[:description] || 'No description'
          entries << {key: key, description: description}
        end

        entries
      end

      def parse_comments
        source = File.read(File.join(__dir__, 'commands.rb'))
        comments = {}

        # Parse comments for standalone methods
        # Supports "Key: Description" or just "Description"
        source.scan(/^\s*#\s*(.+?)\n\s*(?:def\s+(\S+)|define_method\(:'?([^')\s]+)'?\))/) do |comment, def_name, define_name|
          method_name = (def_name || define_name).to_sym
          text = comment.sub(/\.\s*$/, '').strip
          if text =~ /^(\S+):\s*(.+)$/
            comments[method_name] = {key: $1, description: $2}
          else
            comments[method_name] = {description: text}
          end
        end

        comments
      end
    end
  end
end
