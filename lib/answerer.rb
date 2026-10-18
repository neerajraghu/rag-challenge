require_relative "gemini"

# Step 5: ask Gemini to answer using only the retrieved chunks.
module Answerer
  PROMPT = <<~TEXT
    You answer questions about a document using ONLY the excerpts below.
    Rules:
    - Give the exact fact asked for. Add nothing that is not in the excerpts.
    - Keep the document's own wording for numbers, names and dates.
    - If the excerpts do not state something the question asks for, say so plainly.
    - If the answer is not in the excerpts, reply exactly: Not found in the document.
    - Finish with the page number(s) you used, like (p. 21), exactly as written in the excerpt headers.
    - Answer in one short sentence per thing asked. Do not add related facts, extra figures or background, even if they are true.
    - If the question uses a word the excerpts do not use (for example "fully deployed" where the text says "scheduled to replace"), give the excerpt's wording.

    EXCERPTS:
    %<context>s

    QUESTION: %<question>s
  TEXT

  def self.context(results)
    results.map { |c, _| "[#{[c[:label], "page #{c[:page]}"].compact.join(", ")}] #{c[:text]}" }.join("\n\n")
  end

  NOT_FOUND = /not found in the document/i
  TRIES = 3

  # A weaker backup model can wrongly say "not found". So that answer is asked again,
  # each time with the models in a different order. It is accepted only after TRIES tries.
  def self.answer(question, results)
    prompt = format(PROMPT, context: context(results), question: question)
    answer = nil
    TRIES.times do |i|
      answer = Gemini.generate(prompt, models: Gemini::CHAT_MODELS.rotate(i))
      return answer unless answer.match?(NOT_FOUND)
      puts "  answered 'not found', asking again (#{i + 1}/#{TRIES})" if i < TRIES - 1
    end
    answer
  end
end
