require "json"
require_relative "../lib/hybrid"
require_relative "../lib/tasks"
require_relative "../lib/answerer"
require_relative "../lib/imac_index"

pages = ImacIndex.pages
chunks = JSON.parse(File.read("data/imac_chunks.json"), symbolize_names: true)
vec_path = "data/imac_vectors.json"
vectors = File.exist?(vec_path) ? JSON.parse(File.read(vec_path)) : []
hybrid = Hybrid.new(chunks, vectors.size == chunks.size ? vectors : [], model: Tasks::EMBED_MODELS["imac"])
notes = ImacIndex.footnotes(pages)
questions = ARGV.empty? ? [
  "How much less energy does iMac use compared to the ENERGY STAR requirement?",
  "What is the total carbon footprint of the iMac, and how much of that comes from product use versus manufacturing?",
  "What material is the iMac stand made from, and what percentage of it is recycled?"
] : ARGV
questions.each do |q|
  results = hybrid.search(q, fetch: 8, limit: 8)
  top_pages = ImacIndex.top_pages(results)
  blocks = top_pages.map { |n| { label: "Page #{n}", page: n, text: pages[n] } }
  fn = ImacIndex.notes_for(blocks.map { |b| b[:text] }, notes)
  blocks << { label: "Footnotes", page: "11-12", text: fn.join("\n") } if fn.any?
  puts "\nQ: #{q}\n   pages used: #{top_pages.inspect}, footnotes: #{fn.size}"
  puts "A: #{Answerer.answer(q, blocks.map { |b| [b, 0] })}"
end
