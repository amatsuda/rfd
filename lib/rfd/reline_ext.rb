# frozen_string_literal: true

class Reline::LineEditor
  # override render_finished to suppress printing line break
  def render_finished; end
end

class Rfd::CommandCancelled < StandardError; end

# ESC key (27) cancels command input
Reline::LineEditor.prepend(Module.new do
  def input_key(key)
    raise Rfd::CommandCancelled if key.char.ord == 27
    super
  end
end)
