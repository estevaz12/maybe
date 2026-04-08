require "sidekiq/web"

# Longer read timeout in development: Redis can stall briefly (e.g. persistence on WSL2).
if Rails.env.development?
  dev_redis = {
    url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/1"),
    connect_timeout: 5,
    read_timeout: 30,
    write_timeout: 5
  }
  Sidekiq.configure_server { |config| config.redis = dev_redis }
  Sidekiq.configure_client { |config| config.redis = dev_redis }
end

if Rails.env.production?
  Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
    configured_username = ::Digest::SHA256.hexdigest(ENV.fetch("SIDEKIQ_WEB_USERNAME", "maybe"))
    configured_password = ::Digest::SHA256.hexdigest(ENV.fetch("SIDEKIQ_WEB_PASSWORD", "maybe"))

    ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(username), configured_username) &&
      ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), configured_password)
  end
end

Sidekiq::Cron.configure do |config|
  # 10 min "catch-up" window in case worker process is re-deploying when cron tick occurs
  config.reschedule_grace_period = 600
end
