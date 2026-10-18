require_relative "chunker"

# Parent-child chunks for the Global Economic Prospects report.
# Parent = a whole section. Child = a small chunk of about 500 characters with its section label.
module GepChunker
  SKIP_TITLES = ["References"].freeze

  # Adds a "label" such as "Chapter 2: Regional Outlooks > South Asia > Outlook" to every section.
  def self.label_sections(sections)
    stack = []
    sections.map do |s|
      stack = stack.first(s["level"])
      stack[s["level"]] = s["chapter"].between?(1, 4) && s["level"].zero? ? "Chapter #{s['chapter']}: #{s['title']}" : s["title"]
      s.merge("label" => stack.compact.join(" > "), "chapter_title" => stack.first)
    end
  end

  # Joins paragraphs that were cut by a page break in the middle of a sentence.
  def self.paragraphs(section)
    section["paragraphs"].each_with_object([]) do |p, out|
      if out.any? && p["text"].match?(/\A[[:lower:]]/) && !out.last[:text].match?(/[.!?:]\z/)
        out.last[:text] += " #{p['text']}"
      else
        out << { page: p["page"], text: p["text"] }
      end
    end
  end

  def self.run(sections)
    chunks = []
    label_sections(sections).each do |s|
      next if SKIP_TITLES.include?(s["title"])
      chunk_section(s).each { |c| chunks << c.merge(id: chunks.size) }
    end
    chunks
  end

  def self.chunk_section(section)
    sentences = paragraphs(section).flat_map do |p|
      Chunker.sentences(p[:text]).map { |t| { page: p[:page], text: t } }
    end
    current = []
    out = []
    sentences.each do |sent|
      current << sent
      next if current.sum { |x| x[:text].length + 1 } < Chunker::TARGET
      out << build(current, section)
      current = current.last(Chunker::OVERLAP)
    end
    out << build(current, section) if current.size > Chunker::OVERLAP || (out.empty? && current.any?)
    out
  end

  def self.build(sentences, section)
    { section_id: section["id"], chapter: section["chapter"], label: section["label"],
      page: sentences.first[:page], text: sentences.map { |s| s[:text] }.join(" ") }
  end
end
