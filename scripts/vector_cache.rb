# Saves vectors by their text, so a rebuilt chunk list only embeds chunks that are new or changed.
# Usage: ruby scripts/vector_cache.rb gep _e2     (run BEFORE rebuilding chunks)
require "json"
require "digest"

name, suffix = ARGV.fetch(0), ARGV[1].to_s
chunks = JSON.parse(File.read("data/#{name}_chunks.json"), symbolize_names: true)
vectors = JSON.parse(File.read("data/#{name}_vectors#{suffix}.json"))
cache_path = "data/#{name}_vector_cache#{suffix}.json"
cache = File.exist?(cache_path) ? JSON.parse(File.read(cache_path)) : {}
chunks.each_with_index do |c, i|
  cache[Digest::SHA1.hexdigest([c[:label], c[:text]].compact.join("\n"))] = vectors[i] if vectors[i]
end
File.write(cache_path, JSON.generate(cache))
puts "#{name}: cache now holds #{cache.size} vectors"
