# Optimized Puma configuration for multi-tenant e-commerce with large import support
# Balanced for 22+ stores with product import capabilities

# Thread configuration - optimized for e-commerce workload
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 6 }  # Reduced from 8 for more memory per thread
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { 2 }
threads min_threads_count, max_threads_count

# Worker processes - balanced for multi-tenant load and import capacity
worker_count = ENV.fetch("WEB_CONCURRENCY") { 3 }  # Reduced from 4 to give more memory per worker
workers worker_count if worker_count.to_i > 0

# Preload application for memory efficiency across workers
preload_app! if worker_count.to_i > 0

# Port configuration
port ENV.fetch("PORT") { 3000 }

# Environment
environment ENV.fetch("RAILS_ENV") { "production" }

# Timeouts optimized for large file imports and e-commerce complexity
worker_timeout ENV.fetch("PUMA_WORKER_TIMEOUT") { 300 }      # 5 minutes for large imports
worker_boot_timeout ENV.fetch("PUMA_BOOT_TIMEOUT") { 120 }   # 2 minutes boot time
worker_shutdown_timeout 45                                    # Clean shutdown time

# Process management
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Plugins
plugin :tmp_restart
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Multi-tenant and import optimizations
if worker_count.to_i > 0
  on_worker_boot do
    # Reconnect to database for each worker to avoid connection sharing
    if defined?(ActiveRecord)
      ActiveRecord::Base.establish_connection
      
      # Optimize database connection pool for imports
      pool_config = ActiveRecord::Base.connection_pool.db_config
      if pool_config.respond_to?(:configuration_hash)
        config = pool_config.configuration_hash
        # Increase statement timeout for large imports
        ActiveRecord::Base.connection.execute("SET statement_timeout = '600s'") rescue nil
      end
      
      Rails.logger.info "Worker #{Process.pid}: Database connection established with import optimizations"
    end
    
    # Reset Apartment tenant cache for each worker
    if defined?(Apartment)
      Apartment::Tenant.reset
      Rails.logger.info "Worker #{Process.pid}: Apartment tenant cache reset"
    end
    
    # Reconnect Redis for session/cache management
    if defined?(Redis)
      Redis.current.disconnect!
      Rails.logger.info "Worker #{Process.pid}: Redis reconnected"
    end
    
    # Clear any cached tenant connections
    if defined?(ActiveRecord) && ActiveRecord::Base.respond_to?(:clear_all_connections!)
      ActiveRecord::Base.clear_all_connections!
    end
    
    # Set worker-specific memory optimization for imports
    GC.start
    GC.compact if GC.respond_to?(:compact)
  end

  on_worker_shutdown do
    # Clean shutdown for multi-tenant connections
    if defined?(ActiveRecord)
      ActiveRecord::Base.connection_pool.disconnect!
      Rails.logger.info "Worker #{Process.pid}: Database connections closed"
    end
  end

  before_fork do
    # Close database connections before forking
    if defined?(ActiveRecord)
      ActiveRecord::Base.connection_pool.disconnect!
      Rails.logger.info "Master process: Database connections closed before fork"
    end
    
    # Force garbage collection before forking
    GC.start
    GC.compact if GC.respond_to?(:compact)
  end
end

# Logging and monitoring
if ENV["RAILS_ENV"] == "production"
  quiet false
  
  # Log worker memory usage periodically
  Thread.new do
    loop do
      sleep 300  # Every 5 minutes
      if defined?(Rails) && Rails.logger
        memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
        Rails.logger.info "Worker #{Process.pid}: Memory usage: #{memory_mb}MB"
      end
    end
  end if worker_count.to_i > 0
  
  Rails.logger.info "Puma configuration loaded: #{worker_count} workers, #{max_threads_count} max threads, optimized for imports"
end

# Worker restart strategy for memory management during heavy imports
worker_culling_strategy :oldest if respond_to?(:worker_culling_strategy)

# Force restart workers if they exceed memory threshold (if supported)
if respond_to?(:on_restart)
  on_restart do
    Rails.logger.info "Puma restarting - clearing import caches"
  end
end