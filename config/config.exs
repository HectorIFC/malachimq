import Config

config :malachimq,
  tcp_port: 4040,
  dashboard_port: 4041,
  partition_multiplier: 100,
  locale: "en_US",

  # Authentication
  auth_timeout_ms: 10_000,
  session_timeout_ms: 3_600_000,
  session_cleanup_interval_ms: 60_000,

  # Default users: {username, password, permissions}
  # Permissions: :admin, :produce, :consume
  default_users: [
    {"admin", "admin123", [:admin]},
    {"producer", "producer123", [:produce]},
    {"consumer", "consumer123", [:consume]},
    {"app", "app123", [:produce, :consume]}
  ]
