require "net/http"
require "json"
require "uri"

File.readlines(File.expand_path("../.env", __dir__)).each do |l|
  k, v = l.strip.split("=", 2)
  ENV[k] = v if k && v
end
KEY = ENV.fetch("GEMINI_API_KEY")
BASE = "https://generativelanguage.googleapis.com/v1beta"

def call(path, body = nil)
  uri = URI("#{BASE}/#{path}")
  req = body ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  req["x-goog-api-key"] = KEY
  req["Content-Type"] = "application/json"
  req.body = body.to_json if body
  res = Net::HTTP.start(uri.host, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
  [res.code, (JSON.parse(res.body) rescue {})]
end

code, data = call("models?pageSize=200")
names = (data["models"] || []).map { |m| [m["name"].sub("models/", ""), m["supportedGenerationMethods"]] }
puts "list models: HTTP #{code}, #{names.size} models"
puts "embedding models: #{names.select { |_, m| m.include?("embedContent") }.map(&:first).join(', ')}"
puts "chat models (flash): #{names.select { |n, m| n.include?("flash") && m.include?("generateContent") }.map(&:first).first(8).join(', ')}"

emb = names.map(&:first).find { |n| n.include?("embedding") }
if emb
  code, d = call("models/#{emb}:embedContent", { content: { parts: [{ text: "hello world" }] } })
  puts "embed (#{emb}): HTTP #{code}, dims=#{d.dig('embedding', 'values')&.size.inspect} #{d.dig('error', 'message')}"
end

chat = ARGV[0] || names.map(&:first).find { |n| n.match?(/\Agemini-.*flash\z/) } || "gemini-2.5-flash"
code, d = call("models/#{chat}:generateContent", { contents: [{ parts: [{ text: "Reply with the single word: ok" }] }] })
puts "chat (#{chat}): HTTP #{code}, reply=#{d.dig('candidates', 0, 'content', 'parts', 0, 'text').to_s.strip.inspect} #{d.dig('error', 'message').to_s[0, 150]}"
