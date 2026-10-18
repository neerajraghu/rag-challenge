require_relative "bm25"
require_relative "gemini"

# Meaning search (embeddings) + keyword search (BM25), joined with Reciprocal Rank Fusion.
class Hybrid
  RRF_K = 60

  # `model` is the embedding model that made the vectors. Questions must use the same one.
  def initialize(chunks, vectors, model: Gemini::EMBED_MODEL)
    @model = model
    @chunks = chunks
    @vectors = vectors
    @bm25 = BM25.new(chunks)
  end

  # `allow` is an optional filter: a lambda that takes a chunk and says if it may be returned.
  # Chunks without a vector yet are skipped by the meaning search but still found by keywords.
  def dense(query, limit, allow: nil)
    return [] if @vectors.empty?
    q = Gemini.embed([query], task: "RETRIEVAL_QUERY", model: @model).first
    scored = @vectors.each_with_index.map { |v, i| [@chunks[i], dot(q, v)] }
    scored = scored.select { |c, _| allow.call(c) } if allow
    scored.sort_by { |_, s| -s }.first(limit)
  end

  def keyword(query, limit, allow: nil)
    return @bm25.search(query, limit) unless allow
    @bm25.search(query, @chunks.size).select { |c, _| allow.call(c) }.first(limit)
  end

  # Fetch `fetch` from each search, return the best `limit` after fusion.
  def search(query, fetch: 8, limit: 8, allow: nil)
    fuse([dense(query, fetch, allow: allow), keyword(query, fetch, allow: allow)]).first(limit)
  end

  def fuse(lists)
    scores = Hash.new(0.0)
    by_id = {}
    lists.each do |list|
      list.each_with_index do |(chunk, _), rank|
        scores[chunk[:id]] += 1.0 / (RRF_K + rank + 1)
        by_id[chunk[:id]] = chunk
      end
    end
    scores.sort_by { |_, s| -s }.map { |id, s| [by_id[id], s] }
  end

  private

  def dot(a, b)
    a.each_with_index.sum { |x, i| x * b[i] }
  end
end
