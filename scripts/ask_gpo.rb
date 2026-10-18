require "json"
require_relative "../lib/hybrid"
require_relative "../lib/tasks"
require_relative "../lib/answerer"

chunks = JSON.parse(File.read("data/gpo_chunks.json"), symbolize_names: true)
vectors = JSON.parse(File.read("data/gpo_vectors.json"))
hybrid = Hybrid.new(chunks, vectors, model: Tasks::EMBED_MODELS["gpo"])
questions = ARGV.empty? ? [
  "How many depository libraries did GPO staff visit in FY 2018?",
  "What new digital system replaced FDsys, and when was it fully deployed?",
  "How much did GPO procure in printing and information products in FY 2018 on behalf of federal agencies?"
] : ARGV
questions.each do |q|
  results = hybrid.search(q, fetch: 8, limit: 8)
  puts "\nQ: #{q}\nA: #{Answerer.answer(q, results)}"
end
