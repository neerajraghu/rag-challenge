# Step 2: split page text into chunks that never cut a sentence.
module Chunker
  TARGET = 500   # characters per chunk, a chunk closes once it passes this
  OVERLAP = 1    # sentences repeated at the start of the next chunk

  SENTENCE_END = /(?<=[.!?])\s+(?=["“(\[$]?[A-Z0-9])/

  def self.sentences(text)
    text.split(/\n{2,}/).flat_map { |para| para.split(SENTENCE_END) }.map(&:strip).reject(&:empty?)
  end

  def self.run(pages, source:)
    pages.flat_map { |page| chunk_page(page, source) }.each_with_index.map { |c, i| c.merge(id: i) }
  end

  def self.chunk_page(page, source)
    chunks = []
    current = []
    sentences(page[:text]).each do |sentence|
      current << sentence
      next if current.join(" ").length < TARGET
      chunks << build(current, page, source)
      current = current.last(OVERLAP)
    end
    chunks << build(current, page, source) if current.any? && (chunks.empty? || current.size > OVERLAP)
    chunks
  end

  def self.build(sentences, page, source)
    { source: source, page: page[:page], text: sentences.join(" ") }
  end
end
