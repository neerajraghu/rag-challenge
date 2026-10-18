require "fileutils"
FileUtils.mkdir_p("data/imac")
require "json"
require_relative "../lib/ingest"
require_relative "../lib/chunker"

pdf = "/home/bacancy/Desktop/RAG-USE-CASES/GPO-Anual-report.pdf"
pages = Ingest.run(pdf)
chunks = Chunker.run(pages, source: "GPO 2018 Annual Report")
File.write("data/gpo_pages.json", JSON.pretty_generate(pages))
File.write("data/gpo_chunks.json", JSON.pretty_generate(chunks))
lengths = chunks.map { |c| c[:text].length }
puts "pages: #{pages.size}, chunks: #{chunks.size}"
puts "chunk length min/avg/max: #{lengths.min}/#{lengths.sum / lengths.size}/#{lengths.max}"
