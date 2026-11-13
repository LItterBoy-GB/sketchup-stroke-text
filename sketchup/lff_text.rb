# encoding: UTF-8
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Hei Stroke contributors
# Standalone LFF stroke reader for SketchUp. Model operations belong to caller.
module LFFText
  class Font
    attr_reader :path, :letter_spacing, :word_spacing, :line_spacing
    def initialize(path)
      @path = path
      @raw = {}; @cache = {}; @advances = {}
      @letter_spacing = 3.0; @word_spacing = 6.75; @line_spacing = 1.0
      key = nil
      File.foreach(path, encoding: 'UTF-8') do |line|
        line = line.strip
        if key && line =~ /^#\s*Advance:\s*([\d.]+)/i
          @advances[key] = $1.to_f
        elsif line =~ /^#\s*(LetterSpacing|WordSpacing|LineSpacingFactor):\s*([\d.]+)/i
          case $1.downcase
          when 'letterspacing' then @letter_spacing = $2.to_f
          when 'wordspacing' then @word_spacing = $2.to_f
          when 'linespacingfactor' then @line_spacing = $2.to_f
          end
        elsif line =~ /^\[#?([0-9a-f]{1,6})\]/i
          key = $1.to_i(16); @raw[key] = []
        elsif key && !line.empty? && !line.start_with?('#')
          @raw[key] << line
        end
      end
    end
    def has?(char)
      @raw.key?(char.ord)
    end
    def advance(char)
      @advances[char.ord]
    end
    def glyph(code, stack = [])
      return @cache[code] if @cache.key?(code)
      raise "Cyclic LFF glyph reference U+#{code.to_s(16)}" if stack.include?(code)
      lines = @raw[code] or raise "Missing LFF reference U+#{code.to_s(16)}"
      result = []
      lines.each do |line|
        if line =~ /^C([0-9a-f]+)$/i
          result.concat(glyph($1.to_i(16), stack + [code]))
        else
          points = line.split(';').map do |part|
            vals = part.split(','); [Float(vals[0]), (vals[1] || '0').to_f, vals[2] && vals[2].start_with?('A') ? vals[2][1..-1].to_f : 0.0]
          end
          result << points if points.length >= 2
        end
      end
      @cache[code] = result
    end
  end

  # LibreCAD's LFF reader assigns each segment the bulge on its end vertex.
  def self.segment(a, b, max_angle = Math::PI / 18.0)
    bulge = b[2] || 0.0
    return [[a[0], a[1]], [b[0], b[1]]] if bulge.abs < 1e-10
    dx = b[0] - a[0]; dy = b[1] - a[1]; chord = Math.sqrt(dx * dx + dy * dy)
    return [[a[0], a[1]], [b[0], b[1]]] if chord < 1e-12
    cx = (a[0] + b[0]) / 2.0 - dy * (1.0 - bulge * bulge) / (4.0 * bulge)
    cy = (a[1] + b[1]) / 2.0 + dx * (1.0 - bulge * bulge) / (4.0 * bulge)
    start = Math.atan2(a[1] - cy, a[0] - cx); theta = 4.0 * Math.atan(bulge)
    radius = Math.sqrt((a[0] - cx)**2 + (a[1] - cy)**2)
    n = [(theta.abs / max_angle).ceil, 1].max
    (0..n).map { |i| ang = start + theta * i / n; [cx + radius * Math.cos(ang), cy + radius * Math.sin(ang)] }
  end

  # height and origin are SketchUp internal lengths (e.g. 100.mm).
  def self.draw(entities:, text:, font:, height:, origin: [0, 0, 0], width_factor: 1.0, letter_spacing: 0.0)
    raise ArgumentError, 'height and width_factor must be positive' unless height.to_f > 0 && width_factor.to_f > 0
    raise ArgumentError, 'font must be LFFText::Font' unless font.is_a?(Font)
    missing = text.each_char.reject { |c| c == "\n" || c == "\r" || c == ' ' || font.has?(c) }.uniq
    group = entities.add_group
    group.name = 'LFF text'
    group.set_attribute('LFFText', 'text', text)
    group.set_attribute('LFFText', 'font', File.basename(font.path))
    group.set_attribute('LFFText', 'height_inches', height.to_f)
    group.set_attribute('LFFText', 'width_factor', width_factor.to_f)
    group.set_attribute('LFFText', 'letter_spacing_font_units', letter_spacing.to_f)
    x = 0.0; y = 0.0
    text.each_char do |char|
      next if char == "\r"
      if char == "\n"
        x = 0.0; y -= 10.0 * font.line_spacing; next
      end
      if char == ' '
        x += font.word_spacing + letter_spacing.to_f; next
      end
      paths = if font.has?(char)
                font.glyph(char.ord)
              else
                [[[0.0, 0.0, 0], [8.0, 0.0, 0], [8.0, 10.0, 0], [0.0, 10.0, 0], [0.0, 0.0, 0]]]
              end
      max_x = paths.flat_map { |p| p.map { |v| v[0] } }.max || 8.0
      paths.each do |path|
        path.each_cons(2) do |a, b|
          pts = segment(a, b).map { |p| [(x + p[0]) * width_factor.to_f, y + p[1], 0] }
          pts.each_cons(2) { |u, v| group.entities.add_line(u, v) unless u == v }
        end
      end
      x += (font.advance(char) || max_x + font.letter_spacing) + letter_spacing.to_f
    end
    # Intersecting closed strokes can induce faces in SketchUp; retain edges only.
    faces = group.entities.grep(Sketchup::Face)
    group.entities.erase_entities(faces) unless faces.empty?
    scale = height.to_f / 10.0
    group.transform!(Geom::Transformation.scaling(scale))
    group.transform!(Geom::Transformation.translation(origin))
    { group: group, missing: missing }
  end
end
