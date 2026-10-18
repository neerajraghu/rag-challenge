# Does the right fact reach the model? Basic (keyword search, top 3 chunks) vs the full pipeline.
# A method passes a question when every "must appear" snippet is in the text it would send to the model.
# MRR scores the ranking: 1 / rank of the first chunk that holds the key snippet, in the top 8 (0 if missing).
# Usage: ruby -W0 scripts/evaluate.rb         ONLY="part of a question" or TASK=gep to run less.
require "json"
require_relative "../lib/hybrid"
require_relative "../lib/tasks"
require_relative "../lib/rewriter"
require_relative "../lib/context"
require_relative "../lib/imac_index"
require_relative "eval_questions"
$stdout.sync = true

PLAN_CACHE = "data/rewrite_cache.json"

def clean(text) = text.unicode_normalize(:nfkc).gsub(/\s+/, " ")

def found?(text, snippet)
  t = clean(text)
  snippet.is_a?(Regexp) ? t.match?(snippet) : t.include?(snippet)
end

def passes?(text, gold) = gold.all? { |g| found?(text, g) }

def reciprocal_rank(chunks, key)
  rank = chunks.index { |c| found?(c[:text], key) }
  rank ? 1.0 / (rank + 1) : 0.0
end

def load_task(task)
  chunks = JSON.parse(File.read("data/#{task}_chunks.json"), symbolize_names: true)
  vectors = JSON.parse(File.read(Tasks::VECTOR_FILES[task]))
  vectors = [] if vectors.size != chunks.size
  { chunks: chunks, hybrid: Hybrid.new(chunks, vectors, model: Tasks::EMBED_MODELS[task]), vectors: vectors.size }
end

# The rewriter calls an LLM, so its plan is saved. A rerun then tests the same plan.
def plan_for(question)
  cache = File.exist?(PLAN_CACHE) ? JSON.parse(File.read(PLAN_CACHE)) : {}
  return cache[question].transform_keys(&:to_sym) if cache[question]
  plan = Rewriter.rewrite(question)
  unfiltered_copy = plan[:query] == question && !plan[:chapter] && !plan[:region] && !plan[:executive_summary]
  File.write(PLAN_CACHE, JSON.pretty_generate(cache.merge(question => plan))) unless unfiltered_copy
  plan
end

# What the full pipeline would send to the model, and the ranked chunks behind it.
def advanced(task, question, data)
  hybrid = data[:hybrid]
  case task
  when "gpo"
    ranked = hybrid.search(question, fetch: 8, limit: 8).map(&:first)
    [ranked.map { |c| c[:text] }.join(" "), ranked]
  when "gep"
    results = Rewriter.search(hybrid, plan_for(question))
    [Context.build(results, data[:chunks]).map { |b| b[:text] }.join(" "), results.map(&:first)]
  when "imac"
    pages = ImacIndex.pages
    results = hybrid.search(question, fetch: 8, limit: 8)
    ranked = results.map(&:first)
    texts = ImacIndex.top_pages(results).map { |n| pages[n] }
    [(texts + ImacIndex.notes_for(texts, ImacIndex.footnotes(pages))).join(" "), ranked]
  end
end

data = Tasks::EMBED_MODELS.keys.to_h { |t| [t, load_task(t)] }
data.each { |t, d| puts "#{t}: #{d[:chunks].size} chunks, #{d[:vectors]} vectors" }
only = ENV["ONLY"]
tasks = ENV["TASK"]
rows = QUESTIONS.select { |t, q, _| (only.nil? || q.include?(only)) && (tasks.nil? || t == tasks) }.map do |task, q, gold, key|
  key ||= gold.first
  basic = data[task][:hybrid].keyword(q, 8).map(&:first)
  context, ranked = advanced(task, q, data[task])
  { task: task, q: q, basic: passes?(basic.first(3).map { |c| c[:text] }.join(" "), gold),
    adv: passes?(context, gold), rr_basic: reciprocal_rank(basic, key), rr_adv: reciprocal_rank(ranked, key) }
end

puts "\n%-5s %-6s %-9s %-9s %-9s %s" % %w[task basic advanced mrr_basic mrr_adv question]
rows.each do |r|
  puts "%-5s %-6s %-9s %-9.2f %-9.2f %s" % [r[:task], r[:basic] ? "PASS" : "fail", r[:adv] ? "PASS" : "fail",
                                           r[:rr_basic], r[:rr_adv], r[:q][0, 62]]
end
puts "\n%-6s %-12s %-12s %-10s %s" % %w[task basic_pass adv_pass mrr_basic mrr_adv]
rows.group_by { |r| r[:task] }.each do |t, rs|
  n = rs.size
  puts "%-6s %-12s %-12s %-10.2f %.2f" % [t, "#{rs.count { |r| r[:basic] }}/#{n}", "#{rs.count { |r| r[:adv] }}/#{n}",
                                           rs.sum { |r| r[:rr_basic] } / n, rs.sum { |r| r[:rr_adv] } / n]
end
puts "ALL    #{rows.count { |r| r[:basic] }}/#{rows.size}        #{rows.count { |r| r[:adv] }}/#{rows.size}"
