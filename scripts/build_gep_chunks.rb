require "json"
require_relative "../lib/gep_chunker"

sections = JSON.parse(File.read("data/gep_sections.json"))
chunks = GepChunker.run(sections)
File.write("data/gep_chunks.json", JSON.pretty_generate(chunks))
len = chunks.map { |c| c[:text].length }
puts "sections: #{sections.size}, chunks: #{chunks.size}"
puts "length min/avg/max: #{len.min}/#{len.sum / len.size}/#{len.max}"
puts "short chunks (<120 chars): #{len.count { |l| l < 120 }}"
sa = chunks.select { |c| c[:label].include?("South Asia > Outlook") }
puts "South Asia > Outlook chunks: #{sa.size}"; puts "  e.g. #{sa.first[:label]} (p.#{sa.first[:page]}): #{sa.first[:text][0, 150]}"
