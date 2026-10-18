# Which embedding model made the vectors of each task. Chunks and questions must use the same one.
module Tasks
  EMBED_MODELS = {
    "gpo" => "gemini-embedding-001",
    "gep" => "gemini-embedding-2",
    "imac" => "gemini-embedding-2"
  }.freeze

  VECTOR_FILES = {
    "gpo" => "data/gpo_vectors.json",
    "gep" => "data/gep_vectors_e2.json",
    "imac" => "data/imac_vectors.json"
  }.freeze
end
