# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
loader = File.expand_path('sketchup_stroke_text.rb', __dir__)
require loader
class Numeric
  def mm; self / 25.4; end
end
module Sketchup
  class Face; end
  class Edge
    attr_reader :points
    def initialize(a,b); @points=[a,b]; end
    def valid?; true; end
  end
  class Entities < Array
    def add_group; raise 'library must not create groups'; end
    def build
      builder = Object.new
      entities = self
      builder.define_singleton_method(:add_edges) do |a,b|
        existing=entities.grep(Sketchup::Edge).find { |e| e.points==[a,b] || e.points==[b,a] }
        edge=existing || Sketchup::Edge.new(a,b)
        entities << edge unless existing
        [edge]
      end
      yield builder
    end
  end
end
load loader
load loader
raise 'method included twice' unless Sketchup::Entities.ancestors.count { |a| a == SketchupStrokeText::EntitiesMethods } == 1
font = SketchupStrokeText.resolve_font(nil)
raise 'font cache failed' unless font.equal?(SketchupStrokeText.resolve_font(SketchupStrokeText::DEFAULT_FONT_PATH))
emoji = 0x1f600.chr(Encoding::UTF_8)
host=Sketchup::Entities.new
face=Sketchup::Face.new
host << face
result=host.add_stroke_text('A'+emoji+emoji, height: 20.mm, font: font, origin: [1,2,3], width_factor: 1.5, letter_spacing: 0.25)
raise 'missing list' unless result[:missing] == [emoji]
raise 'face changed' unless host.include?(face)
raise 'no returned edges' if result[:edges].empty?
raise 'origin not applied' unless result[:edges].all? { |e| e.points.all? { |p| p[2] == 3.0 && p[0] >= 1.0 } }
first=result[:edges].first
result2=host.add_stroke_text('A'+emoji+emoji, height: 20.mm, font: font, origin: [1,2,3], width_factor: 1.5, letter_spacing: 0.25)
raise 'existing edge returned as new' if result2[:edges].include?(first)
raise 'existing face changed' unless host.include?(face)
def ink_width(result)
  xs=result[:lines].flat_map { |line| line[:paths].flatten(1).map { |p| p[0] } }
  xs.max-xs.min
end
[20.mm,200.mm].each do |height|
  [1.0,1.5].each do |factor|
    plain=LFFText.layout(text:'建建',font:font,height:height,width_factor:factor)
    spaced=LFFText.layout(text:'建建',font:font,height:height,width_factor:factor,letter_spacing:5.mm)
    raise 'letter spacing not fixed' unless (ink_width(spaced)-ink_width(plain)-5.mm).abs < 1e-9
  end
end
lines=LFFText.layout(text:"A\n\nBB",font:font,height:10.mm,line_spacing:10.mm,align: :right)[:lines]
raise 'blank line generated geometry' unless lines[1][:paths].empty?
raise 'right alignment' unless (lines[0][:max_x]-lines[2][:max_x]).abs<1e-9
begin
  host.add_stroke_text('A',font:123)
  raise 'invalid font accepted'
rescue ArgumentError => e
  raise unless e.message.include?('font must')
end
begin
  LFFText.draw(entities: [], text:'A',font:font,height:10.mm)
  raise 'unsupported host accepted'
rescue NotImplementedError
end
puts 'PASS: direct entities, existing geometry, missing glyphs, origin, spacing, alignment, reload'
