# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
# Lightweight host doubles exercise the real loader and drawing implementation.
loader = File.expand_path('sketchup_stroke_text.rb', __dir__)
require loader # Loading without SketchUp must be harmless.
raise 'parser was not loaded' unless defined?(LFFText::Font)

class Numeric
  def mm; self / 25.4; end
end
module Geom
  class Transformation
    def self.scaling(value); [:scale, value]; end
    def self.translation(value); [:translation, value]; end
  end
end
module Sketchup
  class Face; end
  class Entities < Array
    def add_group
      group = Group.new
      self << group
      group
    end
    def add_line(a, b)
      self << Face.new if !@injected_face
      @injected_face = true
      self << [a, b]
    end
    def erase_entities(faces); faces.each { |face| delete(face) }; end
  end
  class Group
    attr_accessor :name
    attr_reader :entities, :attributes, :transforms
    def initialize
      @entities = Entities.new; @attributes = {}; @transforms = []
    end
    def set_attribute(dict, key, value); @attributes[[dict, key]] = value; end
    def transform!(transform); @transforms << transform; end
  end
end

load loader
included = Sketchup::Entities.ancestors.count { |a| a == SketchupStrokeText::EntitiesMethods }
load loader
raise 'method included more than once' unless included == 1 && Sketchup::Entities.ancestors.count { |a| a == SketchupStrokeText::EntitiesMethods } == 1
font = SketchupStrokeText.resolve_font(nil)
raise 'default font not cached' unless font.equal?(SketchupStrokeText.resolve_font(nil))
raise 'font path not cached' unless font.equal?(SketchupStrokeText.resolve_font(SketchupStrokeText::DEFAULT_FONT_PATH))
emoji = 0x1f600.chr(Encoding::UTF_8)
space = 0x3000.chr(Encoding::UTF_8)
text = 'A' + space + emoji + emoji
host = Sketchup::Entities.new
group = host.add_stroke_text(text, height: 20.mm, font: font, origin: [1, 2, 3], width_factor: 1.5, letter_spacing: 0.25)
raise 'wrong return type' unless group.is_a?(Sketchup::Group) && host.first.equal?(group)
raise 'missing list incorrect' unless group.attributes[['LFFText', 'missing_chars']] == [emoji]
raise 'original text missing' unless group.attributes[['LFFText', 'text']] == text
raise 'parameters not propagated' unless group.attributes[['LFFText', 'width_factor']] == 1.5 && group.attributes[['LFFText', 'letter_spacing_length']] == 0.25
raise 'wrong transformation' unless group.transforms == [[:scale, 20.mm / 10.0], [:translation, [1, 2, 3]]]
raise 'face retained' unless group.entities.grep(Sketchup::Face).empty?
raise 'no geometry' unless group.entities.any?
begin
  host.add_stroke_text('A', font: 123)
  raise 'invalid font accepted'
rescue ArgumentError => e
  raise unless e.message.include?('font must')
end

# letter_spacing is a SketchUp length: the same spacing value must add the same
# absolute width at any height. Geometry is laid out in font units and scaled by
# height/10 afterwards, so undo that scale before comparing.
def ink_width(host)
  xs = host.flat_map { |e| e.is_a?(Array) ? [e[0][0], e[1][0]] : [] }
  xs.max - xs.min
end

gaps = [20.mm, 200.mm].map do |h|
  scale = h / 10.0
  plain = ink_width(Sketchup::Entities.new.add_stroke_text('建建', height: h, font: font, letter_spacing: 0).entities)
  spaced = ink_width(Sketchup::Entities.new.add_stroke_text('建建', height: h, font: font, letter_spacing: 5.mm).entities)
  (spaced - plain) * scale  # 还原为实际长度
end
raise "letter_spacing scaled with height: #{gaps.inspect}" unless gaps.all? { |g| (g - 5.mm).abs < 1e-9 }

puts 'PASS: safe loading, injection, cache, Group, parameters, missing glyphs, faces, letter spacing units'
