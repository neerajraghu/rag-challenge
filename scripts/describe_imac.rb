# Reads each iMac page image together with its text layer and writes a full transcription.
require "fileutils"
FileUtils.mkdir_p("data/imac")
require_relative "../lib/gemini"
$stdout.sync = true
PDF = "/home/bacancy/Desktop/RAG-USE-CASES/iMac_PER_Oct2024.pdf"
PROMPT = <<~TEXT
  This is page %<n>d of Apple's iMac Product Environmental Report. Below is the text layer extracted from the PDF
  (it can be in the wrong order and it misses what is drawn in charts and icons).

  Write a complete transcription of the page in plain text:
  1. All headings and paragraphs, in reading order.
  2. For every chart, table, diagram or icon: say what it shows and write out EVERY number, label, unit and
     percentage it contains, one fact per line. If a bar or segment has no number, say so. Do not estimate or invent numbers.
  3. Footnote markers: where a superscript number is attached to a fact, write it like [fn 7]. List the footnote texts
     found on this page under "FOOTNOTES", with their numbers.
  Copy words and numbers exactly. Add nothing that is not on the page.

  TEXT LAYER:
  %<text>s
TEXT

(1..12).each do |n|
  out = format("data/imac/page-%02d.txt", n)
  next puts("page #{n}: cached") if File.exist?(out)
  text = `pdftotext -f #{n} -l #{n} #{PDF} -`
  png = format("data/imac/page-%02d.png", n)
  File.write(out, Gemini.generate_with_image(format(PROMPT, n: n, text: text), png))
  puts "page #{n}: done (#{File.size(out)} bytes)"
end
puts "all done"
