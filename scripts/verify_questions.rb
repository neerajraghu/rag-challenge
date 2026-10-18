# Checks that every "must appear" snippet really exists in the source text of its document.
require "json"
require_relative "eval_questions"

def clean(t) = t.unicode_normalize(:nfkc).gsub(/\s+/, " ")

corpus = {
  "gpo" => JSON.parse(File.read("data/gpo_pages.json")).map { |p| p["text"] }.join(" "),
  "gep" => JSON.parse(File.read("data/gep_sections.json")).flat_map { |s| s["paragraphs"].map { |p| p["text"] } }.join(" "),
  "imac" => (1..12).map { |n| File.read(format("data/imac/page-%02d.txt", n)) }.join(" ")
}.transform_values { |t| clean(t) }

bad = 0
QUESTIONS.each do |task, q, gold, key|
  gold.each do |g|
    ok = g.is_a?(Regexp) ? corpus[task].match?(g) : corpus[task].include?(g)
    (bad += 1; puts "MISSING [#{task}] #{g.inspect}  <- #{q[0, 60]}") unless ok
  end
  k = key || gold.first
  (bad += 1; puts "BAD KEY [#{task}] #{k.inspect}") unless gold.include?(k) || (k.is_a?(String) && corpus[task].include?(k))
end
puts "questions: #{QUESTIONS.size} (#{QUESTIONS.group_by(&:first).map { |t, v| "#{t} #{v.size}" }.join(', ')}), problems: #{bad}"
