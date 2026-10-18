require "json"
require "open3"

# Step 1: read a PDF page by page in reading order and clean the text.
module Ingest
  # Lines that repeat on at least this share of pages are headers or footers.
  REPEAT_SHARE = 0.3

  def self.page_count(pdf)
    out, = Open3.capture2("pdfinfo", pdf)
    out[/^Pages:\s+(\d+)/, 1].to_i
  end

  def self.raw_page(pdf, number)
    out, = Open3.capture2("pdftotext", "-f", number.to_s, "-l", number.to_s, "-enc", "UTF-8", pdf, "-")
    out
  end

  def self.run(pdf)
    raw = (1..page_count(pdf)).map { |n| raw_page(pdf, n) }
    repeated = repeated_lines(raw)
    raw.each_with_index.map { |text, i| { page: i + 1, text: clean(text, repeated) } }
  end

  def self.repeated_lines(raw_pages)
    counts = Hash.new(0)
    raw_pages.each { |t| t.lines.map(&:strip).reject(&:empty?).uniq.each { |l| counts[l] += 1 } }
    limit = [raw_pages.size * REPEAT_SHARE, 3].max
    counts.select { |_, c| c >= limit }.keys
  end

  def self.clean(text, repeated)
    lines = text.delete("\f").lines.map(&:strip)
    lines = lines.reject { |l| repeated.include?(l) || l.match?(/\A\d{1,3}\z/) }
    paragraphs = lines.slice_when { |_, b| b.empty? }.map { |g| g.reject(&:empty?) }.reject(&:empty?)
    paragraphs.map { |p| join_lines(p) }.join("\n\n")
  end

  # Join wrapped lines. A line ending in "-" is joined without a space.
  def self.join_lines(lines)
    lines.inject { |acc, l| acc.end_with?("-") ? acc + l : "#{acc} #{l}" }.gsub(/\s+/, " ")
  end
end
