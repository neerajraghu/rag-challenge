require "json"
require_relative "../lib/imac_index"

chunks = ImacIndex.chunks
File.write("data/imac_chunks.json", JSON.pretty_generate(chunks))
notes = ImacIndex.footnotes
puts "chunks: #{chunks.size} (min/avg/max chars #{chunks.map { |c| c[:text].length }.minmax.inspect}), footnotes: #{notes.keys.size} (#{notes.keys.min}-#{notes.keys.max})"
puts "fn 18: #{notes[18].to_s[0, 160]}"
puts "fn 7:  #{notes[7].to_s[0, 160]}"
