# frozen_string_literal: true

module Rfd
  class FilterInput
    attr_accessor :text

    def initialize(&on_change)
      @text = ''
      @on_change = on_change
    end

    def clear
      return if @text.empty?
      @text = ''
      @on_change&.call
    end

    def backspace
      return if @text.empty?
      @text = @text[0..-2]
      @on_change&.call
    end

    def append(char)
      @text += char
      @on_change&.call
    end

    def empty?
      @text.empty?
    end

    # Handle input, return true if handled
    def handle_input(c)
      case c
      when 8, 127, Curses::KEY_BACKSPACE, Curses::KEY_DC  # Backspace/Delete
        backspace
        true
      when 21  # Ctrl-U - clear
        clear
        true
      when String
        append(c)
        true
      when Integer
        if c >= 32 && c <= 126  # Printable ASCII
          append(c.chr)
          true
        else
          false
        end
      else
        false
      end
    end

    def render(window, row, max_width)
      window.setpos(row, 1)
      window.attron(Curses::A_BOLD) do
        prompt = "> #{@text}_"
        window.addstr(prompt[0, max_width].ljust(max_width))
      end
    end

    def fuzzy_match?(text, pattern = @text)
      return true if pattern.empty?
      pattern_chars = pattern.downcase.chars
      text_lower = text.downcase
      pattern_index = 0

      text_lower.each_char do |char|
        if char == pattern_chars[pattern_index]
          pattern_index += 1
          return true if pattern_index >= pattern_chars.length
        end
      end
      false
    end
  end
end
