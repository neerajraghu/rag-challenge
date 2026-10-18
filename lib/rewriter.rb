require "json"
require_relative "gemini"

# Turns a question into a search query plus optional filters (chapter, executive summary).
module Rewriter
  REGIONS = ["East Asia and Pacific", "Europe and Central Asia", "Latin America and the Caribbean",
             "Middle East, North Africa, Afghanistan, and Pakistan", "South Asia", "Sub-Saharan Africa"].freeze

  PROMPT = <<~TEXT
    You prepare a search over the World Bank report "Global Economic Prospects, June 2026".
    Its parts: Executive Summary; Chapter 1 Global Outlook; Chapter 2 Regional Outlooks
    (East Asia and Pacific, Europe and Central Asia, Latin America and the Caribbean,
    Middle East North Africa Afghanistan and Pakistan, South Asia, Sub-Saharan Africa);
    Chapter 3 Sovereign Debt Levels and Interest Rates in EMDEs; Chapter 4 Fiscal Policy and Commodity Price Swings.
    Return JSON only, with these keys:
    - "search_query": the question rewritten as a short keyword-rich search query. Keep every number, name and year from the question. Do not add the report title or its date, the whole search is already inside this report.
    - "chapter": 1, 2, 3 or 4 if the question clearly names one chapter or clearly belongs to one, else null.
    - "executive_summary": true only if the question asks about the executive summary, else false.
    - "region": one of the six regions of Chapter 2, spelled exactly as "East Asia and Pacific",
      "Europe and Central Asia", "Latin America and the Caribbean",
      "Middle East, North Africa, Afghanistan, and Pakistan", "South Asia" or "Sub-Saharan Africa",
      if the question is about one region or about a country in it, else null.
      In this report Afghanistan and Pakistan belong to "Middle East, North Africa, Afghanistan, and Pakistan",
      not to South Asia. India, Bangladesh, Sri Lanka and Nepal belong to South Asia.

    QUESTION: %<question>s
  TEXT

  def self.rewrite(question)
    raw = Gemini.generate(format(PROMPT, question: question), json: true)
    data = JSON.parse(raw[/\{.*\}/m])
    { query: data["search_query"].to_s.empty? ? question : data["search_query"],
      chapter: data["chapter"].is_a?(Integer) ? data["chapter"] : nil,
      executive_summary: data["executive_summary"] == true,
      region: REGIONS.include?(data["region"]) ? data["region"] : nil }
  rescue StandardError => e
    puts "  rewriter failed (#{e.message[0, 60]}), using the question as it is"
    { query: question, chapter: nil, executive_summary: false, region: nil }
  end

  # Chapter and executive summary filters are hard. A region filter is soft: it is only a guess from the
  # question, and a country question can be answered in another chapter. So its results are merged
  # with the unfiltered results.
  def self.search(hybrid, plan, fetch: 8, limit: 8)
    filtered = hybrid.search(plan[:query], fetch: fetch, limit: limit, allow: filter(plan))
    return filtered unless plan[:region] && !plan[:executive_summary]
    hybrid.fuse([filtered, hybrid.search(plan[:query], fetch: fetch, limit: limit)]).first(limit)
  end

  def self.filter(plan)
    return ->(c) { c[:label].start_with?("Executive Summary") } if plan[:executive_summary]
    return ->(c) { c[:chapter] == 2 && c[:label].include?("> #{plan[:region]}") } if plan[:region]
    return ->(c) { c[:chapter] == plan[:chapter] } if plan[:chapter]
    nil
  end
end
