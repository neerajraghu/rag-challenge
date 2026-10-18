# Step 3: keyword search (BM25) written in plain Ruby.
class BM25
  K1 = 1.5
  B = 0.75
  STOPWORDS = %w[a an and are as at be by for from has have in is it its of on or that the this to was were will with].freeze

  def self.tokenize(text)
    text.downcase.scan(/[[:alnum:]$%.,]+/).map { |w| w.gsub(/\A[.,]+|[.,]+\z/, "") }
        .reject { |w| w.empty? || STOPWORDS.include?(w) }
  end

  def initialize(chunks)
    @chunks = chunks
    @docs = chunks.map { |c| self.class.tokenize([c[:label], c[:text]].compact.join(" ")).tally }
    @lengths = @docs.map { |d| d.values.sum }
    @avg = @lengths.sum.to_f / [@lengths.size, 1].max
    @df = Hash.new(0)
    @docs.each { |d| d.each_key { |t| @df[t] += 1 } }
  end

  # Returns [[chunk, score], ...] best first.
  def search(query, limit = 8)
    terms = self.class.tokenize(query).uniq
    scored = @docs.each_with_index.map { |doc, i| [@chunks[i], score(doc, @lengths[i], terms)] }
    scored.select { |_, s| s > 0 }.sort_by { |_, s| -s }.first(limit)
  end

  private

  def score(doc, length, terms)
    n = @docs.size
    terms.sum do |t|
      tf = doc[t] or next 0
      idf = Math.log(1 + (n - @df[t] + 0.5) / (@df[t] + 0.5))
      idf * tf * (K1 + 1) / (tf + K1 * (1 - B + B * length / @avg))
    end
  end
end
