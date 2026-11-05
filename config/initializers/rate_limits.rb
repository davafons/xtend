# Rate limits keep their own counters so they work regardless of the cache store (tests use a null cache).
# Counters live in the web process; one Puma process serves this app.
RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)
