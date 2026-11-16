# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
require_relative 'lff_text'
font=LFFText::Font.new(File.join(__dir__,'..','fonts','hei-improved.lff'))
space=0x3000.chr(Encoding::UTF_8)
raise 'full-width space missing' unless font.has?(space) && font.glyph(0x3000).empty? && font.advance(space).to_f>0
a=font.glyph(0x41).first.first[0]
r=LFFText.layout(text: 'A'+space+'A', font: font, height: 10.0)
raise 'space reported missing' unless r[:missing].empty?
xs=r[:lines].flat_map{|line| line[:paths].flatten(1).map{|p|p[0]}}
expected=a+font.advance('A')+font.advance(space)
raise 'space did not advance' unless xs.any?{|x| (x-expected).abs<0.00001}
%w[⑳ ↔ ∂ ∇ ∅ ‐ 〜 ｟ æ Æ ø Å å ß ♡ ¢ £ ¡ ¿].each { |char| raise "missing #{char}" unless font.has?(char) }
puts 'PASS: font parser, full-width advance, extension glyphs'
