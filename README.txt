RAG challenge, three documents, plain Ruby
===========================================

What is in here
---------------
Task 1  GPO 2018 Annual Report (82 pages, plain text in columns)
Task 2  World Bank Global Economic Prospects, June 2026 (200 pages, chapters, sections, many tables)
Task 3  Apple iMac Product Environmental Report (12 pages, facts in charts, tables, icons, footnotes)

Setup
-----
1. Ruby with the nokogiri gem. The poppler tools (pdftotext, pdfinfo, pdftoppm) must be installed.
2. Put a free Google AI Studio key in .env as GEMINI_API_KEY=...
3. The PDFs are read from /home/bacancy/Desktop/RAG-USE-CASES.

How to ask a question
---------------------
ruby -W0 scripts/ask_gpo.rb  "your question"
ruby -W0 scripts/ask_gep.rb  "your question"
ruby -W0 scripts/ask_imac.rb "your question"
With no question, each script runs its 3 sample questions.

How to rebuild from the PDFs (data/ holds the generated files)
--------------------------------------------------------------
Run everything from the project folder. The commands below start from nothing (no data/ folder).
Task 1   ruby scripts/build_gpo.rb          then  ruby scripts/embed.rb gpo
Task 2   mkdir -p data
         pdftotext -bbox-layout /home/bacancy/Desktop/RAG-USE-CASES/GEP-Jun-2026.pdf data/gep_bbox.html
         ruby scripts/build_gep_sections.rb
         ruby scripts/build_gep_chunks.rb
         ruby scripts/embed.rb gep _e2
Task 3   mkdir -p data/imac
         pdftoppm -r 150 -png /home/bacancy/Desktop/RAG-USE-CASES/iMac_PER_Oct2024.pdf data/imac/page
         ruby scripts/describe_imac.rb       (Gemini reads each page image, one text file per page)
         ruby scripts/build_imac.rb
         ruby scripts/embed.rb imac
Which embedding model each task uses is set in lib/tasks.rb. Chunks and questions must use the same one.
embed.rb keeps a vector cache (data/*_vector_cache*.json) and only embeds chunks that are new or changed.
It can be stopped and started again. Before rebuilding chunks, run: ruby scripts/vector_cache.rb <task> <suffix>
so the old vectors are kept.

How it works
------------
All tasks
  1. Read the PDF in the right reading order and clean it.
  2. Cut it into chunks that never cut a sentence (about 500 characters, one sentence overlap).
  3. Search two ways: by meaning (Gemini embeddings) and by keywords (BM25, written in Ruby).
  4. Join both result lists with Reciprocal Rank Fusion (8 + 8 results become the best 8).
  5. Ask Gemini to answer using only those excerpts. The prompt says: exact fact, nothing added,
     use the report's own wording, say "Not found in the document" if it is not there, give the page.

Task 2 extras (long report with sections and tables)
  - The Contents pages give the outline. The body is cut into sections by matching the headings in order.
  - Every chunk carries its label, like "Chapter 2: Regional Outlooks > South Asia > Outlook".
  - Tables are rebuilt from word positions (lib/gep_tables.rb). Each row becomes one sentence with its
    column heading, like "TABLE 2.10 South Asia economy forecasts, Fiscal-year basis, India: 2026/27f = 6.6".
    Repeated header rows (calendar years, then fiscal years) are handled. Checked against the page image.
  - A query rewriter (Gemini) turns the question into a search query and picks filters.
    Chapter and executive summary filters are hard. The region filter is soft (merged with the unfiltered
    search), because a country question can be answered in another chapter (Pakistan: Chapter 3).
    The rewriter knows that Pakistan and Afghanistan belong to the Middle East and North Africa group.
  - Parent expansion: each top chunk is shown with the chunks next to it in the same section.
  - Answers show the page number printed on the page (PDF page minus 22 in the body).

Task 3 extras (charts, tables, icons, footnotes)
  - Gemini reads each page image together with the text layer and writes a full transcription:
    every number in charts and tables, what icons mean, footnote markers.
  - Chunks are about 250 characters. A long plain-text block is split by lines, so cover facts do not share
    a chunk. A table or chart block is never cut in the middle.
  - Each [fn N] marker pulls in the footnote text from pages 11 and 12.
  - The 4 pages with the highest total search score are sent as a whole.

Evaluation
----------
ruby -W0 scripts/evaluate.rb        (TASK=gep for one document, ONLY="part of a question" for one question)
43 questions (13 GPO, 16 World Bank, 14 iMac) in scripts/eval_questions.rb. scripts/verify_questions.rb checks
that every expected snippet really exists in the source text.
A method passes a question when every expected snippet is in the text it would send to the model.
It also gives MRR: 1 / rank of the best chunk in the top 8, averaged. Higher is better.
  Basic     = keyword search only, top 3 chunks.
  Advanced  = the full pipeline above.
Result (2026-10-18):
  task    basic    advanced   MRR basic   MRR advanced
  GPO     13/13    13/13      0.81        0.83
  World   12/16    16/16      0.60        0.81
  iMac    12/14    14/14      0.66        0.84
  all     37/43    43/43
The hard questions (tables, charts, footnotes, the Pakistan trap) are where basic search fails.
Expected snippets were first written with exact wording. Three were too strict (the same fact in other words,
like "15%" and "15 percent") and were changed to check the fact, not one phrase. The rewriter plans are saved
in data/rewrite_cache.json so a rerun tests the same plans.
This checks that the right fact reaches the model. The wording of the final answer is checked by hand.

Rebuild test (2026-10-18)
-------------------------
The README commands were run in a clean copy with no data/ folder.
  - GPO: rebuilt (418 chunks) and embedded from nothing, with real calls.
  - World Bank: rebuilt, 1463 chunks, every chunk identical to the shipped project (all vectors came from the
    cache, nothing to embed). The vector cache was copied in on purpose, to save the free daily limit.
  - iMac: Gemini read the 12 pages again and chunks were rebuilt and embedded with real calls.
  - Evaluation, using the saved rewriter plans: GPO 13/13, World Bank 16/16, iMac 14/14 for the full pipeline
    (basic: 13, 12 and 11).
Two problems were found and fixed: the scripts needed a data/ folder to exist, and the iMac chunker made one
4386-character chunk and one 1-character chunk on the new text.
Gemini's page reading is not exactly the same each time. The same table came out as "Product use: 45%" the
first time and "Product use | 45%" the second time. The facts were the same, so the expected snippets for these
rows now accept ":" or "|". The ranking score on iMac was a little lower on the new reading (0.77, was 0.84).
If you read the iMac pages again, expect small changes, and run scripts/verify_questions.rb after it.

Answers checked by hand
-----------------------
GPO       166 depository libraries (p. 21).  govinfo, scheduled to replace FDsys in December 2018 (p. 22, 39).
          More than $375 million worth of printing and other information products (p. 5).
World Bank  South Asia: 6.3 percent in 2026, about 7 percent a year in 2027-28 (printed p. 74).
          Chapter 3: rising debt means higher interest rates, higher debt-service payments, more debt distress.
          Executive summary risks: escalation of hostilities, commodity disruptions, trade policy uncertainty, and more.
          Pakistan: government guarantees underreported since 2016, about 1 percent of GDP (Chapter 3).
          Tables: Bangladesh 2026/27f 4.6, Maldives 2026f 0.7, South Asia net exports 2026f -0.5.
          Brazil growth in 2030 (not in the report): "Not found in the document."
iMac      58 percent less energy than the ENERGY STAR requirement (p. 7).
          346 kg CO2e (two ports, 256GB), product use 45 percent, production 50 percent (p. 10).
          Stand: 100 percent recycled aluminum (p. 4).

Known limits
------------
  - The backup answer model (gemini-flash-lite-latest) sometimes wrongly says "Not found in the document."
    even with the right page in front of it (seen on the iMac carbon question, 1 run in 3 on 2026-10-18).
    So "not found" is asked again up to 3 times, with the models in a different order (lib/answerer.rb).
    A question with no answer in the document therefore takes 3 model calls.
  - The report said "scheduled to replace" for FDsys, never "fully deployed". The answer keeps the report's wording.
  - World Bank: "Regional developments" (p. 71) and two sub-headings on p. 124 are not in the PDF text layer.
    Their text sits under the section before them. Footnotes of the World Bank report are not linked to their
    claims (only the iMac footnotes are). Charts in the World Bank and GPO reports are not read by the vision model.
  - Table rows are rebuilt from word positions, with settings tuned on this PDF. The second line of a wide column
    heading ("from January 2026 projections") is sometimes missing from the column name.
  - iMac: the report says 346 kg is for the 256GB model, but footnote 10 says it is based on the 512GB model.
  - Free tier limits: 1000 embedding texts a day per model, 100 a minute, about 20 answers a day for
    the best chat models. The code waits and tries the next model. Gemini is often busy (503), and short
    network errors are retried.
  - The re-ranker from the meeting notes was not built. The Field Guide says it made results worse on table
    chunks, and there are only 3 documents.
  - Not done: answers graded by a person, and a larger test set than 43 questions.
