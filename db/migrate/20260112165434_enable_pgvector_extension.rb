class EnablePgvectorExtension < ActiveRecord::Migration[8.0]
  def up
    # pgvector extension enabled manually via: sudo -u postgres psql -d dbname -c "CREATE EXTENSION IF NOT EXISTS vector;"
    # This migration kept for documentation purposes
    say "pgvector extension should already be enabled"
  end

  def down
    # Don't remove extension in case other apps use it
    say "pgvector extension not removed - may be used by other applications"
  end
end
