require "json"
require_relative "../lib/gep_outline"

pages = GepOutline.load_pages("data/gep_bbox.html")
toc = GepOutline.parse_toc(pages)
headings = GepOutline.headings(toc)
sections = GepOutline.sections(pages, headings)
found = sections.map { |s| s[:entry].title + "@" + s[:entry].page.to_s }
missing = headings.reject { |h| found.include?("#{h.title}@#{h.page}") }
puts "headings in outline: #{headings.size}, found in body: #{sections.size}"
puts "NOT FOUND (#{missing.size}): #{missing.map { |m| "#{m.title} (p#{m.page})" }.join('; ')}"
data = sections.each_with_index.map do |s, i|
  e = s[:entry]
  { id: i, chapter: e.chapter, level: e.level, title: e.title, start_page: s[:start_page],
    paragraphs: s[:paragraphs] }
end
File.write("data/gep_sections.json", JSON.pretty_generate(data))
words = data.map { |d| d[:paragraphs].sum { |p| p[:text].split.size } }
puts "total words: #{words.sum}, empty sections: #{words.count(0)}"
