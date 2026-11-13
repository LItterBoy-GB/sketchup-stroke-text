# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
module Sketchup
  class Entities
    def add_stroke_text(*); :existing; end
  end
end
load File.expand_path('sketchup_stroke_text.rb', __dir__)
raise 'method replaced' unless Sketchup::Entities.new.add_stroke_text == :existing
raise 'module included over existing method' if Sketchup::Entities.ancestors.include?(SketchupStrokeText::EntitiesMethods)
puts 'PASS: existing method retained'
