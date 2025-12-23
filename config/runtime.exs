import Config

config :malachimq,
  tcp_port: String.to_integer(System.get_env("MALACHIMQ_TCP_PORT") || "4040"),
  dashboard_port: String.to_integer(System.get_env("MALACHIMQ_DASHBOARD_PORT") || "4041"),
  locale: System.get_env("MALACHIMQ_LOCALE") || "en_US",
  partition_multiplier: String.to_integer(System.get_env("MALACHIMQ_PARTITION_MULTIPLIER") || "100"),
  session_timeout_ms: String.to_integer(System.get_env("MALACHIMQ_SESSION_TIMEOUT_MS") || "3600000"),
  session_cleanup_interval_ms: String.to_integer(System.get_env("MALACHIMQ_SESSION_CLEANUP_MS") || "60000"),
  auth_timeout_ms: String.to_integer(System.get_env("MALACHIMQ_AUTH_TIMEOUT_MS") || "10000"),
  tcp_recv_timeout: String.to_integer(System.get_env("MALACHIMQ_TCP_RECV_TIMEOUT") || "30000"),
  gc_interval_ms: String.to_integer(System.get_env("MALACHIMQ_GC_INTERVAL_MS") || "10000"),
  enable_tls: System.get_env("MALACHIMQ_ENABLE_TLS") == "true",
  tls_certfile: System.get_env("MALACHIMQ_TLS_CERTFILE"),
  tls_keyfile: System.get_env("MALACHIMQ_TLS_KEYFILE"),
  tls_cacertfile: System.get_env("MALACHIMQ_TLS_CACERTFILE")

default_users_env = System.get_env("MALACHIMQ_DEFAULT_USERS")

default_users =
  if default_users_env do
    default_users_env
    |> String.split(";")
    |> Enum.map(fn user_str ->
      [username, password, perms] = String.split(user_str, ":")
      permissions = perms |> String.split(",") |> Enum.map(&String.to_atom/1)
      {username, password, permissions}
    end)
  else
    [
      {"admin", System.get_env("MALACHIMQ_ADMIN_PASS") || "admin123", [:admin]},
      {"producer", System.get_env("MALACHIMQ_PRODUCER_PASS") || "producer123", [:produce]},
      {"consumer", System.get_env("MALACHIMQ_CONSUMER_PASS") || "consumer123", [:consume]},
      {"app", System.get_env("MALACHIMQ_APP_PASS") || "app123", [:produce, :consume]}
    ]
  end

config :malachimq, default_users: default_users
