# Usage: ruby scripts/embed.rb gpo|gep|imac [suffix]
# Embeds every chunk. A chunk whose text was embedded before is taken from the vector cache,
# so only new or changed chunks use the free daily limit. Safe to stop and start again.
require "json"
require "digest"
require_relative "../lib/gemini"
require_relative "../lib/tasks"

name = ARGV.fetch(0)
suffix = ARGV[1].to_s
model = Tasks::EMBED_MODELS.fetch(name)
chunks = JSON.parse(File.read("data/#{name}_chunks.json"), symbolize_names: true)
cache_path = "data/#{name}_vector_cache#{suffix}.json"
cache = File.exist?(cache_path) ? JSON.parse(File.read(cache_path)) : {}
$stdout.sync = true

texts = chunks.map { |c| [c[:label], c[:text]].compact.join("\n") }
keys = texts.map { |t| Digest::SHA1.hexdigest(t) }
missing = keys.each_index.reject { |i| cache.key?(keys[i]) }
puts "model #{model}: #{chunks.size} chunks, #{chunks.size - missing.size} from cache, #{missing.size} to embed"

missing.each_slice(50) do |batch|
  vectors = Gemini.embed(batch.map { |i| texts[i] }, task: "RETRIEVAL_DOCUMENT", model: model)
  batch.each_with_index { |i, j| cache[keys[i]] = vectors[j] }
  File.write(cache_path, JSON.generate(cache))
  puts "embedded up to chunk #{batch.last + 1} (cache holds #{cache.size})"
end

File.write("data/#{name}_vectors#{suffix}.json", JSON.generate(keys.map { |k| cache.fetch(k) }))
puts "done"
