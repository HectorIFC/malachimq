defmodule MalachiMQ.I18n do
  @moduledoc """
  Internationalization module for MalachiMQ.
  Supports Brazilian Portuguese (pt_BR) and American English (en_US).

  ## Configuration

      config :malachimq, :locale, "pt_BR"  # or "en_US"

  ## Usage

      MalachiMQ.I18n.t(:metrics_started)
      MalachiMQ.I18n.t(:consumers_created, count: 1000, duration: 500)
  """

  @translations %{
    partition_manager_started: %{
      "pt_BR" => "✅ PartitionManager: %{partitions} partições (%{schedulers} schedulers × %{multiplier})",
      "en_US" => "✅ PartitionManager: %{partitions} partitions (%{schedulers} schedulers × %{multiplier})"
    },
    tcp_server_started: %{
      "pt_BR" => "🚀 MalachiMQ TCP Server na porta %{port} com %{acceptors} acceptors",
      "en_US" => "🚀 MalachiMQ TCP Server on port %{port} with %{acceptors} acceptors"
    },
    transport_enabled: %{
      "pt_BR" => "🔒 Transporte %{transport} habilitado na porta %{port}",
      "en_US" => "🔒 %{transport} transport enabled on port %{port}"
    },
    tls_handshake_failed: %{
      "pt_BR" => "Falha no handshake TLS: %{reason}",
      "en_US" => "TLS handshake failed: %{reason}"
    },
    acceptor_started: %{
      "pt_BR" => "Acceptor #%{id} iniciado",
      "en_US" => "Acceptor #%{id} started"
    },
    accept_error: %{
      "pt_BR" => "Erro no accept: %{reason}",
      "en_US" => "Accept error: %{reason}"
    },
    creating_consumers: %{
      "pt_BR" => "Criando %{count} consumidores...",
      "en_US" => "Creating %{count} consumers..."
    },
    consumers_created_progress: %{
      "pt_BR" => "%{count} consumidores criados...",
      "en_US" => "%{count} consumers created..."
    },
    consumers_created: %{
      "pt_BR" => "✅ %{count} consumidores criados em %{duration}ms",
      "en_US" => "✅ %{count} consumers created in %{duration}ms"
    },
    consumers_rate: %{
      "pt_BR" => "   Taxa: %{rate} consumidores/segundo",
      "en_US" => "   Rate: %{rate} consumers/second"
    },
    total_memory: %{
      "pt_BR" => "   Memória total: %{memory} MB",
      "en_US" => "   Total memory: %{memory} MB"
    },
    memory_per_consumer: %{
      "pt_BR" => "   Memória por consumidor: ~%{memory} KB",
      "en_US" => "   Memory per consumer: ~%{memory} KB"
    },
    sending_messages: %{
      "pt_BR" => "Enviando %{count} mensagens...",
      "en_US" => "Sending %{count} messages..."
    },
    messages_sent: %{
      "pt_BR" => "✅ %{count} mensagens enviadas em %{duration}ms",
      "en_US" => "✅ %{count} messages sent in %{duration}ms"
    },
    messages_rate: %{
      "pt_BR" => "   Taxa: %{rate} msgs/segundo",
      "en_US" => "   Rate: %{rate} msgs/second"
    },
    processing_error: %{
      "pt_BR" => "Erro ao processar: %{error}",
      "en_US" => "Error processing: %{error}"
    },
    metrics_started: %{
      "pt_BR" => "✅ Sistema de métricas iniciado",
      "en_US" => "✅ Metrics system started"
    },
    dashboard_started: %{
      "pt_BR" => "🌐 MalachiMQ Dashboard rodando em http://localhost:%{port}",
      "en_US" => "🌐 MalachiMQ Dashboard running at http://localhost:%{port}"
    },
    ack_manager_started: %{
      "pt_BR" => "✅ AckManager iniciado (timeout: %{timeout}ms)",
      "en_US" => "✅ AckManager started (timeout: %{timeout}ms)"
    },
    messages_expired: %{
      "pt_BR" => "⚠️ %{count} mensagens expiraram e foram reenfileiradas",
      "en_US" => "⚠️ %{count} messages expired and were requeued"
    },
    message_expired_retry: %{
      "pt_BR" => "Mensagem %{id} expirou (tentativa %{attempt}/%{max}), reenfileirando...",
      "en_US" => "Message %{id} expired (attempt %{attempt}/%{max}), requeuing..."
    },
    message_failed_dlq: %{
      "pt_BR" => "Mensagem %{id} falhou após %{max} tentativas - movendo para DLQ",
      "en_US" => "Message %{id} failed after %{max} attempts - moving to DLQ"
    },
    processed_message: %{
      "pt_BR" => "Mensagem processada %{id}",
      "en_US" => "Processed message %{id}"
    },
    auth_started: %{
      "pt_BR" => "✅ Sistema de autenticação iniciado",
      "en_US" => "✅ Authentication system started"
    },
    auth_success: %{
      "pt_BR" => "🔓 Usuário '%{username}' autenticado",
      "en_US" => "🔓 User '%{username}' authenticated"
    },
    auth_failed: %{
      "pt_BR" => "🔒 Falha na autenticação: '%{username}'",
      "en_US" => "🔒 Authentication failed: '%{username}'"
    },
    auth_user_not_found: %{
      "pt_BR" => "🔒 Usuário não encontrado: '%{username}'",
      "en_US" => "🔒 User not found: '%{username}'"
    },
    auth_required: %{
      "pt_BR" => "🔒 Autenticação necessária",
      "en_US" => "🔒 Authentication required"
    },
    user_created: %{
      "pt_BR" => "👤 Usuário criado: '%{username}'",
      "en_US" => "👤 User created: '%{username}'"
    },
    user_removed: %{
      "pt_BR" => "👤 Usuário removido: '%{username}'",
      "en_US" => "👤 User removed: '%{username}'"
    },
    password_changed: %{
      "pt_BR" => "🔑 Senha alterada: '%{username}'",
      "en_US" => "🔑 Password changed: '%{username}'"
    },
    default_users_loaded: %{
      "pt_BR" => "👥 %{count} usuários padrão carregados",
      "en_US" => "👥 %{count} default users loaded"
    },
    sessions_cleaned: %{
      "pt_BR" => "🧹 %{count} sessões expiradas removidas",
      "en_US" => "🧹 %{count} expired sessions cleaned"
    },
    permission_denied: %{
      "pt_BR" => "⛔ Permissão negada: '%{username}' -> %{action}",
      "en_US" => "⛔ Permission denied: '%{username}' -> %{action}"
    },
    system_info: %{
      "pt_BR" => "ℹ️  Informações do Sistema MalachiMQ",
      "en_US" => "ℹ️  MalachiMQ System Info"
    },
    system_schedulers: %{
      "pt_BR" => "   Schedulers: %{schedulers}",
      "en_US" => "   Schedulers: %{schedulers}"
    },
    system_processes: %{
      "pt_BR" => "   Processos: %{processes}/%{limit}",
      "en_US" => "   Processes: %{processes}/%{limit}"
    },
    system_memory: %{
      "pt_BR" => "   Memória: %{memory} MB",
      "en_US" => "   Memory: %{memory} MB"
    },
    system_ets_tables: %{
      "pt_BR" => "   Tabelas ETS: %{tables}/%{limit}",
      "en_US" => "   ETS Tables: %{tables}/%{limit}"
    },
    closing_connections: %{
      "pt_BR" => "🔌 Fechando %{count} conexões ativas...",
      "en_US" => "🔌 Closing %{count} active connections..."
    },
    connection_registry_started: %{
      "pt_BR" => "✅ Registro de conexões iniciado",
      "en_US" => "✅ Connection registry started"
    },
    graceful_shutdown: %{
      "pt_BR" => "⏳ Iniciando shutdown gracioso...",
      "en_US" => "⏳ Starting graceful shutdown..."
    },
    queue_config_started: %{
      "pt_BR" => "✅ Sistema de configuração de filas iniciado",
      "en_US" => "✅ Queue configuration system started"
    },
    queue_created: %{
      "pt_BR" => "📋 Fila '%{queue}' criada com modo %{mode}",
      "en_US" => "📋 Queue '%{queue}' created with mode %{mode}"
    },
    queue_created_implicitly: %{
      "pt_BR" => "⚠️ Fila '%{queue}' criada implicitamente com modo %{mode}",
      "en_US" => "⚠️ Queue '%{queue}' created implicitly with mode %{mode}"
    },
    queue_deleted: %{
      "pt_BR" => "🗑️  Fila '%{queue}' removida",
      "en_US" => "🗑️  Queue '%{queue}' deleted"
    }
  }

  @doc """
  Returns the current locale.
  """
  @spec locale() :: String.t()
  def locale do
    Application.get_env(:malachimq, :locale, "pt_BR")
  end

  @doc """
  Sets the locale at runtime.
  """
  @spec set_locale(String.t()) :: :ok
  def set_locale(new_locale) when new_locale in ["pt_BR", "en_US"] do
    Application.put_env(:malachimq, :locale, new_locale)
    :ok
  end

  @doc """
  Translates a key with optional interpolation.

  ## Examples

      iex> MalachiMQ.I18n.t(:metrics_started)
      "✅ Metrics system started"

      iex> MalachiMQ.I18n.t(:consumers_created, count: 1000, duration: 500)
      "✅ 1000 consumers created in 500ms"
  """
  @spec t(atom(), keyword()) :: String.t()
  def t(key, bindings \\ [])

  def t(key, bindings) when is_atom(key) do
    current_locale = locale()

    case Map.get(@translations, key) do
      nil ->
        to_string(key)

      translations ->
        template = Map.get(translations, current_locale) || Map.get(translations, "en_US") || to_string(key)
        interpolate(template, bindings)
    end
  end

  @doc """
  Lists all available locales.
  """
  @spec available_locales() :: [String.t()]
  def available_locales, do: ["pt_BR", "en_US"]

  @doc """
  Lists all translation keys.
  """
  @spec keys() :: [atom()]
  def keys, do: Map.keys(@translations)

  defp interpolate(template, []), do: template

  defp interpolate(template, bindings) do
    Enum.reduce(bindings, template, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
