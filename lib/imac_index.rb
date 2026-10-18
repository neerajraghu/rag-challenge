# Chunks for the iMac report. Each page transcription is cut at blank lines, so a table or chart stays whole.
module ImacIndex
  TARGET = 250
  MAX = 1400
  MIN = 8

  def self.pages
    (1..12).to_h { |n| [n, File.read(format("data/imac/page-%02d.txt", n))] }
  end

  def self.chunks(pages = self.pages)
    out = []
    pages.each do |n, text|
      pack(text.split(/\n{2,}/).map(&:strip).reject(&:empty?)).each do |t|
        next if t.length < MIN # a stray page number or single character
        out << { id: out.size, page: n, label: "Page #{n}", section_id: n, text: t }
      end
    end
    out
  end

  # Joins small blocks until about TARGET characters. A long block of plain text is split by lines,
  # so facts on a cover or an icon list do not share one chunk. Table and chart blocks (their rows start
  # with "- ") stay whole unless they are bigger than MAX.
  def self.pack(blocks)
    blocks = blocks.flat_map do |b|
      if b.length > MAX
        split_lines(b, MAX)
      elsif b.length > TARGET * 1.6 && b.lines.none? { |l| l.start_with?("- ") }
        split_lines(b)
      else
        [b]
      end
    end
    blocks.each_with_object([]) do |b, acc|
      if acc.any? && acc.last.length < TARGET && acc.last.length + b.length <= MAX
        acc.last << "\n\n" << b
      else
        acc << b.dup
      end
    end
  end

  # The pages to send to the model: each page scores the sum of its chunks' fused scores.
  def self.top_pages(results, count = 4)
    results.group_by { |chunk, _| chunk[:page] }
           .map { |page, rows| [page, rows.sum { |_, score| score }] }
           .sort_by { |_, score| -score }.first(count).map(&:first)
  end

  # Groups the lines of a block into pieces of at most `limit` characters (a single longer line stays whole).
  def self.split_lines(block, limit = TARGET)
    block.lines.map(&:strip).reject(&:empty?).each_with_object([""]) do |line, groups|
      groups << "" if groups.last.length + line.length > limit && !groups.last.empty?
      groups.last << (groups.last.empty? ? line : "\n#{line}")
    end
  end

  # { 7 => "Apple's ...", ... } read from the footnote pages 11 and 12.
  def self.footnotes(pages = self.pages)
    notes = {}
    [11, 12].each do |n|
      current = nil
      pages[n].lines.each do |line|
        line = line.strip
        if (m = line.match(/\A(\d{1,2})\s+(\S.*)\z/))
          current = m[1].to_i
          notes[current] = m[2]
        elsif current && !line.empty? && !line.start_with?("iMac |")
          notes[current] += " #{line}"
        end
      end
    end
    notes
  end

  # Footnote texts for every [fn N] marker found in the given texts.
  def self.notes_for(texts, notes)
    texts.join(" ").scan(/\[fn (\d+)\]/).flatten.map(&:to_i).uniq.sort.filter_map { |i| notes[i] && "#{i}. #{notes[i]}" }
  end
end
