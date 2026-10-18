# Parent expansion with a size limit: for each top chunk, add its neighbours in the same section.
module Context
  MAX_CHARS = 7000
  BODY_PAGES = (23..184) # PDF pages whose printed number is the PDF page minus 22

  # The page number a reader sees printed on the page, not the PDF page number.
  def self.printed_page(pdf_page)
    BODY_PAGES.cover?(pdf_page) ? (pdf_page - 22).to_s : "PDF page #{pdf_page}"
  end

  def self.build(results, chunks, top: 6)
    seen = {}
    blocks = []
    results.first(top).each do |c, _|
      next if seen[c[:id]]
      ids = [c[:id] - 1, c[:id], c[:id] + 1].select do |i|
        i >= 0 && i < chunks.size && chunks[i][:section_id] == c[:section_id] && !seen[i]
      end
      ids.each { |i| seen[i] = true }
      parts = ids.map { |i| chunks[i] }
      blocks << { label: c[:label], page: printed_page(parts.first[:page]), text: parts.map { |p| p[:text] }.join(" ") }
    end
    trim(blocks)
  end

  def self.trim(blocks)
    total = 0
    blocks.take_while { |b| (total += b[:text].length) <= MAX_CHARS || total == b[:text].length }
  end
end
