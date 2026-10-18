require "nokogiri"
require_relative "gep_tables"

# Reads the Contents pages of the Global Economic Prospects PDF into an ordered outline,
# then walks the body in reading order and cuts it into sections.
module GepOutline
  TOC_PAGES = (9..11)
  PAGE_OFFSET = 22     # PDF page = printed page + 22 in the body
  MIN_LINE_HEIGHT = 7.4 # smaller text is chart axis ticks and labels
  Entry = Struct.new(:chapter, :level, :title, :page, keyword_init: true)

  def self.norm(text)
    text.unicode_normalize(:nfkc).downcase.gsub(/[^[:alnum:]]+/, " ").strip
  end

  def self.line_text(line)
    line.css("word").map(&:text).join(" ").unicode_normalize(:nfkc)
  end

  def self.load_pages(path)
    Nokogiri::HTML(File.read(path)).css("page")
  end

  # Ordered entries: chapter titles (level 0), sections (1), sub-sections (2).
  def self.parse_toc(pages)
    entries = []
    chapter = nil
    pending = nil
    TOC_PAGES.each do |n|
      pages[n - 1].css("line").each do |l|
        text = line_text(l)
        x = l["xmin"].to_f
        if (m = text.match(/\AChapter (\d)\z/))
          chapter = m[1].to_i
          next
        end
        next if chapter.nil? || x < 160 || x > 215 # skips page labels, annex and list columns
        dotted = text.match(/\A(.*?)\s*\.{3,}\s*(\d+)?\z/) || text.match(/\A(.*?)\s*\.{3,}\s*\z/)
        if dotted
          title = [pending, dotted[1]].compact.join(" ").strip
          pending = nil
          level = x > 190 ? 2 : 1
          level = 0 if entries.none? { |e| e.chapter == chapter }
          entries << Entry.new(chapter: chapter, level: level, title: title, page: dotted[2]&.to_i)
        else
          pending = [pending, text].compact.join(" ")
        end
      end
    end
    fill_missing_pages(entries)
  end

  # A few TOC lines lose their page number in extraction. Use the previous entry's page.
  def self.fill_missing_pages(entries)
    last = nil
    entries.each do |e|
      e.page ||= last
      last = e.page
    end
    entries
  end
end

module GepOutline
  FRONT = [["Foreword", 17], ["Executive Summary", 19], ["Abbreviations", 21]].freeze
  APPENDIX_PAGE = 185
  RUNNING = /\A(GLOBAL ECONOMIC PROSPECTS \| JUNE 2026|CHAPTER \d|\d{1,3}|[ivxl]+)\z/

  # Ordered headings with their PDF page: front matter, the 4 chapters, then the appendix.
  def self.headings(toc)
    front = FRONT.map { |t, p| Entry.new(chapter: 0, level: 0, title: t, page: p) }
    body = toc.map { |e| Entry.new(chapter: e.chapter, level: e.level, title: e.title, page: e.page + PAGE_OFFSET) }
    appendix = Entry.new(chapter: 5, level: 0, title: "Statistical Appendix", page: APPENDIX_PAGE)
    front + body + [appendix]
  end

  # Returns [{page:, text:}] paragraphs in reading order for one PDF page.
  # Table cells are left out of the plain text. The rebuilt table rows are added at the end of the page.
  def self.page_blocks(page, number)
    opener = chapter_opener?(page)
    in_table = GepTables.table_nodes(page)
    blocks = page.css("block").map do |b|
      lines = b.css("line").select do |l|
        keep_line?(l) && !in_table.include?(l) && !(opener && height(l) >= 30)
      end.map { |l| line_text(l) }
      lines.empty? ? nil : { page: number, lines: lines }
    end.compact
    blocks + GepTables.paragraphs(page).map { |row| { page: number, lines: [row] } }
  end

  def self.height(line)
    line["ymax"].to_f - line["ymin"].to_f
  end

  # A chapter's first page has a big "CHAPTER n" label. Its big title lines are not body text.
  def self.chapter_opener?(page)
    page.css("line").any? { |l| height(l) >= 30 && line_text(l).match?(/\ACHAPTER \d\z/) }
  end

  def self.keep_line?(line)
    height = height(line)
    text = line_text(line)
    height >= MIN_LINE_HEIGHT && !text.match?(RUNNING) && line["ymin"].to_f > 50
  end

  def self.join_lines(lines)
    lines.inject do |acc, l|
      if acc.match?(/[[:alpha:]]-\z/) && l.match?(/\A[[:lower:]]/)
        acc[0...-1] + l
      elsif acc.end_with?("-")
        acc + l
      else
        "#{acc} #{l}"
      end
    end.gsub(/\s+/, " ").strip
  end

  # Walks all blocks in order, cutting a new section at each heading found in `headings`.
  def self.sections(pages, headings)
    out = []
    idx = -1
    (headings.first.page..pages.size).each do |n|
      if chapter_opener?(pages[n - 1]) && (h = headings.index { |e| e.level == 0 && e.page == n && e.chapter.between?(1, 4) })
        idx = h
        out << { entry: headings[idx], start_page: n, paragraphs: [] }
      end
      lines = page_blocks(pages[n - 1], n)
      lines.each do |block|
        buffer = []
        i = 0
        while i < block[:lines].size
          hit = find_heading(block[:lines], i, headings, idx, n)
          if hit
            flush(out, buffer, n)
            idx = hit[:index]
            out << { entry: headings[idx], start_page: n, paragraphs: [] }
            buffer = []
            i += hit[:used]
          else
            buffer << block[:lines][i]
            i += 1
          end
        end
        flush(out, buffer, n)
      end
    end
    out
  end

  def self.flush(out, buffer, page)
    return if buffer.empty? || out.empty?
    out.last[:paragraphs] << { page: page, text: join_lines(buffer) }
  end

  # Does line i (alone, or with the next 1-2 lines) equal one of the next headings on this page?
  def self.find_heading(lines, i, headings, idx, page)
    (idx + 1..[idx + 10, headings.size - 1].min).each do |h|
      next unless (headings[h].page - page).between?(-1, 1)
      (1..3).each do |used|
        joined = lines[i, used].join(" ")
        return { index: h, used: used } if norm(joined) == norm(headings[h].title)
      end
    end
    nil
  end
end
