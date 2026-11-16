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
# 建筑标注补充：希腊字母、圈码 11-19、小写罗马数字、单位合字、箭头、分数、微符号
greek=%w[α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω]
greek_upper=%w[Α Β Γ Δ Ε Ζ Η Θ Ι Κ Λ Μ Ν Ξ Ο Π Ρ Σ Τ Υ Χ Ψ Ω]
extra=%w[⑪ ⑫ ⑬ ⑭ ⑮ ⑯ ⑰ ⑱ ⑲]
extra+=%w[ⅰ ⅱ ⅲ ⅳ ⅴ ⅵ ⅶ ⅷ ⅸ ⅹ]
extra+=%w[㎜ ㎝ ㎞ ㎎ ㎏ ㎥ ▼ ▽ ⇒ ⇐ ⇔ ½ ¼ ¾ µ]
(greek+greek_upper+extra).each { |char| raise "missing #{char}" unless font.has?(char) }

# 上标、下标、⁺⁻ 都是源字形 0.5 等比缩放：宽高减半，左边缘不动，上标锚顶边、下标锚底边
def variant_error(font, target, source, anchor)
  s=font.glyph(target.ord).flatten(1); d=font.glyph(source.ord).flatten(1)
  return "no geometry for #{target}" if s.empty? || d.empty?
  sx=s.map{|p|p[0]}; sy=s.map{|p|p[1]}; dx=d.map{|p|p[0]}; dy=d.map{|p|p[1]}
  return "#{target} width not halved" unless ((sx.max-sx.min)-(dx.max-dx.min)*0.5).abs<0.000001
  return "#{target} height not halved" unless ((sy.max-sy.min)-(dy.max-dy.min)*0.5).abs<0.000001
  top = anchor==:top_left ? sy.max : sy.min
  ref = anchor==:top_left ? dy.max : dy.min
  return "#{target} #{anchor} not anchored" unless (top-ref).abs<0.000001
  return "#{target} left moved" unless (sx.min-dx.min).abs<0.000001
  return "#{target} advance differs" unless (font.advance(target).to_f-font.advance(source).to_f).abs<1e-9
  nil
end

digits=%w[0 1 2 3 4 5 6 7 8 9]
sups=%w[⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹]
subs=%w[₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉]
sups.zip(digits).each do |sup, digit|
  err=variant_error(font, sup, digit, :top_left); raise err if err
  # 上标正好占原字形墨迹框的左上四分之一
  d=font.glyph(digit.ord).flatten(1); s=font.glyph(sup.ord).flatten(1)
  dx=d.map{|p|p[0]}; dy=d.map{|p|p[1]}; sx=s.map{|p|p[0]}; sy=s.map{|p|p[1]}
  raise "#{sup} not in top-left quarter" unless sx.max<=(dx.min+dx.max)/2+0.000001 && sy.min>=(dy.min+dy.max)/2-0.000001
end
subs.zip(digits).each do |sub, digit|
  err=variant_error(font, sub, digit, :bottom_left); raise err if err
  # 下标正好占原字形墨迹框的左下四分之一
  d=font.glyph(digit.ord).flatten(1); s=font.glyph(sub.ord).flatten(1)
  dx=d.map{|p|p[0]}; dy=d.map{|p|p[1]}; sx=s.map{|p|p[0]}; sy=s.map{|p|p[1]}
  raise "#{sub} not in bottom-left quarter" unless sx.max<=(dx.min+dx.max)/2+0.000001 && sy.max<=(dy.min+dy.max)/2+0.000001
end
{'⁺'=>'+', '⁻'=>'-'}.each do |sign, src|
  err=variant_error(font, sign, src, :top_left); raise err if err
end
puts 'PASS: font parser, full-width advance, extension glyphs, superscript/subscript placement'
