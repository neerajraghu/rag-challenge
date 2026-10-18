require "net/http"
require "json"
require "uri"

# Small Gemini client: embeddings and answers.
module Gemini
  BASE = "https://generativelanguage.googleapis.com/v1beta"
  EMBED_MODEL = ENV.fetch("EMBED_MODEL", "gemini-embedding-001")
  CHAT_MODELS = %w[gemini-3-flash-preview gemini-flash-lite-latest gemini-3.8-flash].freeze
  DIMS = 768

  def self.key
    @key ||= begin
      File.readlines(File.expand_path("../.env", __dir__)).each_with_object({}) do |l, h|
        k, v = l.strip.split("=", 2)
        h[k] = v if k && v
      end.fetch("GEMINI_API_KEY")
    end
  end

  def self.post(path, body, tries = 0)
    uri = URI("#{BASE}/#{path}")
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "x-goog-api-key" => key)
    req.body = body.to_json
    begin
      res = Net::HTTP.start(uri.host, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
    rescue Net::ReadTimeout, Net::OpenTimeout, SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError
      raise if tries >= 6
      puts "  network problem, trying again in 5s"
      sleep 5
      return post(path, body, tries + 1)
    end
    return JSON.parse(res.body) if res.code == "200"
    if res.code == "429" && tries < 6 && res.body[/retry in (?:\d+h)?(?:\d+m)?([\d.]+)s/] && !res.body[/retry in \d+[hm]/]
      wait = res.body[/retry in ([\d.]+)s/, 1].to_f.ceil + 2
      puts "  rate limit, waiting #{wait}s"
      sleep wait
      return post(path, body, tries + 1)
    end
    if res.code == "503" && tries < 6
      puts "  model busy (503), waiting 10s"
      sleep 10
      return post(path, body, tries + 1)
    end
    raise "Gemini HTTP #{res.code}: #{res.body[0, 600]}"
  end

  # texts -> array of unit-length vectors. task: RETRIEVAL_DOCUMENT or RETRIEVAL_QUERY
  def self.embed(texts, task:, model: EMBED_MODEL)
    requests = texts.map do |t|
      { model: "models/#{model}", content: { parts: [{ text: t }] },
        taskType: task, outputDimensionality: DIMS }
    end
    post("models/#{model}:batchEmbedContents", { requests: requests })["embeddings"].map do |e|
      normalize(e["values"])
    end
  end

  def self.normalize(v)
    n = Math.sqrt(v.sum { |x| x * x })
    v.map { |x| x / n }
  end

  # Tries each model in turn. A busy model is skipped after two quick retries.
  def self.generate(prompt, models: CHAT_MODELS, json: false)
    config = { temperature: 0 }
    config[:responseMimeType] = "application/json" if json
    body = { contents: [{ parts: [{ text: prompt }] }], generationConfig: config }
    models.each do |model|
      begin
        d = post("models/#{model}:generateContent", body, 4)
        text = d.dig("candidates", 0, "content", "parts")&.map { |p| p["text"] }&.join.to_s.strip
        return text unless text.empty?
      rescue RuntimeError, Net::ReadTimeout, Net::OpenTimeout, SocketError, Errno::ECONNRESET => e
        puts "  #{model} failed (#{e.message[0, 40].gsub(/\s+/, ' ')}), trying next model"
      end
    end
    raise "All Gemini chat models failed"
  end
end

# Reading a page image: same model fallback as `generate`, with the PNG sent inline.
module Gemini
  def self.generate_with_image(prompt, png_path, models: CHAT_MODELS)
    image = [File.binread(png_path)].pack("m0")
    body = { contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: "image/png", data: image } }] }],
             generationConfig: { temperature: 0 } }
    models.each do |model|
      begin
        d = post("models/#{model}:generateContent", body, 4)
        text = d.dig("candidates", 0, "content", "parts")&.map { |p| p["text"] }&.join.to_s.strip
        return text unless text.empty?
      rescue RuntimeError, Net::ReadTimeout, Net::OpenTimeout, SocketError, Errno::ECONNRESET => e
        puts "  #{model} failed (#{e.message[0, 40].gsub(/\s+/, ' ')}), trying next model"
      end
    end
    raise "All Gemini chat models failed"
  end
end
