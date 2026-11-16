# encoding: UTF-8
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
require_relative 'lff_text'

module SketchupStrokeText
  remove_const(:VERSION) if const_defined?(:VERSION, false) && const_get(:VERSION, false) != '0.3.0'
  VERSION = '0.3.0' unless const_defined?(:VERSION, false)
  DEFAULT_FONT_PATH = File.expand_path('../fonts/hei-improved.lff', __dir__) unless const_defined?(:DEFAULT_FONT_PATH, false)

  def self.resolve_font(font)
    return font if font.is_a?(LFFText::Font)
    path = if font.nil?
             DEFAULT_FONT_PATH
           elsif font.is_a?(String) || font.respond_to?(:to_path)
             File.expand_path(font)
           else
             raise ArgumentError, 'font must be nil, a path, or an LFFText::Font'
           end
    @font_cache ||= {}
    @font_cache[path] ||= LFFText::Font.new(path)
  end

  module EntitiesMethods
    # letter_spacing is a SketchUp length (e.g. 2.mm), not a font unit, so the
    # extra gap stays the same regardless of height.
    def add_stroke_text(text, height: 10.mm, font: nil, origin: [0, 0, 0], width_factor: 1.0, letter_spacing: 0.0, line_spacing: nil, align: nil)
      resolved = SketchupStrokeText.resolve_font(font)
      LFFText.draw(entities: self, text: text, font: resolved, height: height,
                   origin: origin, width_factor: width_factor, letter_spacing: letter_spacing,
                   line_spacing: line_spacing, align: align)
    end
  end
end

# Loading outside SketchUp still exposes the font parser without touching a model.
# Preserve an existing method, including one supplied by another extension.
if defined?(Sketchup::Entities) && !Sketchup::Entities.method_defined?(:add_stroke_text) &&
   !Sketchup::Entities.private_method_defined?(:add_stroke_text)
  Sketchup::Entities.include(SketchupStrokeText::EntitiesMethods)
end
