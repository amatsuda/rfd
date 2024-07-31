# frozen_string_literal: true

class Reline::LineEditor
  # override render_finished to suppress printing line break
  def render_finished; end
end
