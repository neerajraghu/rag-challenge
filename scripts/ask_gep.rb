require "json"
require_relative "../lib/hybrid"
require_relative "../lib/tasks"
require_relative "../lib/answerer"
require_relative "../lib/rewriter"
require_relative "../lib/context"

chunks = JSON.parse(File.read("data/gep_chunks.json"), symbolize_names: true)
vectors = JSON.parse(File.read("data/gep_vectors_e2.json"))
hybrid = Hybrid.new(chunks, vectors, model: Tasks::EMBED_MODELS["gep"])
questions = ARGV.empty? ? [
  "What is the growth outlook for South Asia in this report?",
  "What does Chapter 3 say about sovereign debt in developing economies?",
  "According to the executive summary, what are the main risks to the global outlook?"
] : ARGV
questions.each do |q|
  plan = Rewriter.rewrite(q)
  results = Rewriter.search(hybrid, plan)
  blocks = Context.build(results, chunks)
  puts "\nQ: #{q}\n   plan: #{plan}\n   used: #{blocks.map { |b| "#{b[:label].split(' > ').last(2).join(' > ')} p.#{b[:page]}" }.join(' | ')}"
  puts "A: #{Answerer.answer(q, blocks.map { |b| [b, 0] })}"
end
