# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
# Local non-SketchUp regression for font parser and blank advance.
require_relative 'lff_text'
module Sketchup; class Face; end; end
module Geom
  class Transformation
    def self.scaling(x); [:scale,x]; end
    def self.translation(x); [:translate,x]; end
  end
end
class FakeEntities < Array
  def add_group; FakeGroup.new; end
  def add_line(a,b); self << [a,b]; end
  def erase_entities(_faces); raise 'unexpected face'; end
end
class FakeGroup
  attr_accessor :name
  attr_reader :entities
  def initialize; @entities=FakeEntities.new; end
  def set_attribute(*); end
  def transform!(*); end
end
font=LFFText::Font.new(File.join(__dir__,'..','fonts','hei-improved.lff'))
space=0x3000.chr(Encoding::UTF_8)
raise 'full-width space missing' unless font.has?(space) && font.glyph(0x3000).empty? && font.advance(space).to_f>0
a=font.glyph(0x41).first.first[0]
r=LFFText.draw(entities: FakeEntities.new, text: 'A'+space+'A', font: font, height: 10.0)
raise 'space reported missing' unless r[:missing].empty?
xs=r[:group].entities.flat_map{|line| line.map{|p|p[0]}}
expected=a+font.advance('A')+font.advance(space)
raise 'space did not advance' unless xs.any?{|x| (x-expected).abs<0.00001}
puts 'PASS: blank glyph, full-width advance and missing list'
