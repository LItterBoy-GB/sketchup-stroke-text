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

  # Layout is pure Ruby. Coordinates are in the target entities' local units.
  # line_spacing defaults to the font's line spacing, and may be overridden
  # with a SketchUp length. Extra letter spacing is not affected by width_factor.
  def self.layout(text:, font:, height:, origin: [0, 0, 0], width_factor: 1.0, letter_spacing: 0.0, line_spacing: nil, align: nil)
    raise ArgumentError, 'height and width_factor must be positive' unless height.to_f > 0 && width_factor.to_f > 0
    raise ArgumentError, 'font must be LFFText::Font' unless font.is_a?(Font)
    raise ArgumentError, 'align must be :left, :center, or :right' unless [nil, :left, :center, :right].include?(align)
    origin = origin.to_a
    raise ArgumentError, 'origin must contain three coordinates' unless origin.length == 3
    scale = height.to_f / 10.0
    step = line_spacing.nil? ? height.to_f * font.line_spacing : line_spacing.to_f
    missing = []
    lines = text.to_s.split("\n", -1).each_with_index.map do |line, index|
      x = 0.0
      extra = 0.0
      paths_out = []
      line.each_char do |char|
        next if char == "\r"
        if char == ' '
          x += font.word_spacing
          extra += letter_spacing.to_f
          next
        end
        paths = if font.has?(char)
                  font.glyph(char.ord)
                else
                  missing << char unless missing.include?(char)
                  [[[0.0, 0.0, 0], [8.0, 0.0, 0], [8.0, 10.0, 0], [0.0, 10.0, 0], [0.0, 0.0, 0]]]
                end
        max_x = paths.flat_map { |path| path.map { |point| point[0] } }.max || 8.0
        paths.each do |path|
          points = []
          path.each_cons(2) do |a, b|
            curve = segment(a, b)
            points.concat(points.empty? ? curve : curve.drop(1))
          end
          points.map! { |p| [origin[0].to_f + (x + p[0]) * width_factor.to_f * scale + extra,
                              origin[1].to_f + p[1] * scale - index * step, origin[2].to_f] }
          paths_out << points unless points.empty?
        end
        x += font.advance(char) || max_x + font.letter_spacing
        extra += letter_spacing.to_f
      end
      points = paths_out.flatten(1)
      min_x, max_x = points.map { |p| p[0] }.minmax
      { paths: paths_out, min_x: min_x, max_x: max_x }
    end
    max_width = lines.map { |line| line[:min_x] ? line[:max_x] - line[:min_x] : 0.0 }.max || 0.0
    lines.each do |line|
      next unless line[:min_x] && align
      width = line[:max_x] - line[:min_x]
      offset = case align
               when :center then (max_width - width) / 2.0
               when :right then max_width - width
               else 0.0
               end
      offset += origin[0].to_f - line[:min_x]
      line[:paths].each { |path| path.each { |point| point[0] += offset } }
      line[:min_x] += offset
      line[:max_x] += offset
    end
    { lines: lines, missing: missing }
  end

  # SketchUp rejects edges shorter than about 0.001 inch. Coalesce consecutive
  # points before insertion so tiny tessellation segments do not abort a glyph.
  def self.drawable_points(path, tolerance = 0.001)
    return [] if path.length < 2
    kept = [path.first]
    path.drop(1).each do |point|
      a = kept.last
      distance = Math.sqrt(3.times.sum { |i| (point[i] - a[i])**2 })
      kept << point if distance >= tolerance
    end
    last = path.last
    if kept.length > 1 && kept.last != last
      previous = kept[-2]
      distance = Math.sqrt(3.times.sum { |i| (last[i] - previous[i])**2 })
      kept[-1] = last if distance >= tolerance
    end
    kept.length > 1 ? kept : []
  end

  # Writes directly into entities, without creating a group or moving existing
  # geometry. SketchUp 2022+ uses Entities#build to avoid creating faces.
  def self.draw(entities:, text:, font:, height:, origin: [0, 0, 0], width_factor: 1.0, letter_spacing: 0.0, line_spacing: nil, align: nil)
    result = layout(text: text, font: font, height: height, origin: origin,
                    width_factor: width_factor, letter_spacing: letter_spacing,
                    line_spacing: line_spacing, align: align)
    paths = result[:lines].flat_map { |line| line[:paths] }.map { |path| drawable_points(path) }.reject(&:empty?)
    if defined?(Sketchup::Edge)
      existing = entities.grep(Sketchup::Edge).each_with_object({}) { |edge, hash| hash[edge] = true }
    else
      existing = {}
    end
    edges = []
    raise NotImplementedError, 'direct stroke text requires SketchUp 2022+ Entities#build' unless entities.respond_to?(:build)
    entities.build do |builder|
      paths.each do |path|
        path.each_cons(2) do |a, b|
          Array(builder.add_edges(a, b)).each { |edge| edges << edge if edge && !existing[edge] }
        end
      end
    end
    result[:edges] = edges.uniq.select { |edge| !edge.respond_to?(:valid?) || edge.valid? }
    result
  end
end
