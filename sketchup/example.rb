# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
# Loading this example draws text in the active model.
require_relative 'sketchup_stroke_text'
model = Sketchup.active_model
model.start_operation('Stroke text example', true)
begin
  group = model.active_entities.add_group # The caller owns the container.
  result = group.entities.add_stroke_text('建筑平面', height: 100.mm)
  p result[:missing]
  model.commit_operation
rescue Exception
  model.abort_operation
  raise
end
