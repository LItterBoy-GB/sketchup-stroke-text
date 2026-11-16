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
sups=%w[⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹]
sups.each { |char| raise "missing #{char}" unless font.has?(char) }
# 上标由数字缩半后锚定原字形左上角：正好占原字形墨迹框的左上四分之一
%w[0 1 2 3 4 5 6 7 8 9].zip(sups).each do |digit, sup|
  d=font.glyph(digit.ord).flatten(1); s=font.glyph(sup.ord).flatten(1)
  dx=d.map{|p|p[0]}; dy=d.map{|p|p[1]}; sx=s.map{|p|p[0]}; sy=s.map{|p|p[1]}
  raise "#{sup} width not halved" unless ((sx.max-sx.min)-(dx.max-dx.min)*0.5).abs<0.000001
  raise "#{sup} height not halved" unless ((sy.max-sy.min)-(dy.max-dy.min)*0.5).abs<0.000001
  raise "#{sup} top moved" unless (sy.max-dy.max).abs<0.000001
  raise "#{sup} left moved" unless (sx.min-dx.min).abs<0.000001
  raise "#{sup} not in top-left quarter" unless sx.max<=(dx.min+dx.max)/2+0.000001 && sy.min>=(dy.min+dy.max)/2-0.000001
  raise "#{sup} advance differs" unless (font.advance(sup).to_f-font.advance(digit).to_f).abs<1e-9
end
puts 'PASS: font parser, full-width advance, extension glyphs, superscript placement'
