defmodule MalachiMQ.Auth do
  @moduledoc """
  Simple authentication system for MalachiMQ.
  Manages users with username/password credentials.
  """
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  @users_table :malachimq_users
  @sessions_table :malachimq_sessions

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Authenticates a user with username and password.
  Returns {:ok, session_token} or {:error, reason}
  """
  def authenticate(username, password) do
    case :ets.lookup(@users_table, username) do
      [{^username, stored_hash, permissions}] ->
        if verify_password(password, stored_hash) do
          token = generate_session_token()
          :ets.insert(@sessions_table, {token, username, permissions, System.monotonic_time(:millisecond)})
          Logger.info(I18n.t(:auth_success, username: username))
          {:ok, token}
        else
          Logger.warning(I18n.t(:auth_failed, username: username))
          {:error, :invalid_credentials}
        end

      [] ->
        Logger.warning(I18n.t(:auth_user_not_found, username: username))
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Validates a session token.
  Returns {:ok, %{username: username, permissions: permissions}} or {:error, reason}
  """
  def validate_token(token) do
    session_timeout = Application.get_env(:malachimq, :session_timeout_ms, 3_600_000)
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@sessions_table, token) do
      [{^token, username, permissions, created_at}] ->
        if now - created_at < session_timeout do
          {:ok, %{username: username, permissions: permissions}}
        else
          :ets.delete(@sessions_table, token)
          {:error, :session_expired}
        end

      [] ->
        {:error, :invalid_token}
    end
  end

  @doc """
  Invalidates a session token (logout).
  """
  def logout(token) do
    :ets.delete(@sessions_table, token)
    :ok
  end

  @doc """
  Adds a new user.
  Permissions: :admin, :produce, :consume
  """
  def add_user(username, password, permissions \\ [:produce, :consume]) do
    GenServer.call(__MODULE__, {:add_user, username, password, permissions})
  end

  @doc """
  Removes a user.
  """
  def remove_user(username) do
    GenServer.call(__MODULE__, {:remove_user, username})
  end

  @doc """
  Changes user password.
  """
  def change_password(username, new_password) do
    GenServer.call(__MODULE__, {:change_password, username, new_password})
  end

  @doc """
  Lists all users (without passwords).
  """
  def list_users do
    :ets.foldl(
      fn {username, _hash, permissions}, acc ->
        [%{username: username, permissions: permissions} | acc]
      end,
      [],
      @users_table
    )
  end

  @doc """
  Checks if user has a specific permission.
  """
  def has_permission?(username, permission) when is_binary(username) do
    case :ets.lookup(@users_table, username) do
      [{^username, _hash, permissions}] ->
        :admin in permissions or permission in permissions

      [] ->
        false
    end
  end

  def has_permission?(permissions, permission) when is_list(permissions) do
    :admin in permissions or permission in permissions
  end

  @impl true
  def init(:ok) do
    :ets.new(@users_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    :ets.new(@sessions_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    load_default_users()
    schedule_session_cleanup()

    Logger.info(I18n.t(:auth_started))
    {:ok, %{}}
  end

  @impl true
  def handle_call({:add_user, username, password, permissions}, _from, state) do
    case :ets.lookup(@users_table, username) do
      [] ->
        hash = hash_password(password)
        :ets.insert(@users_table, {username, hash, permissions})
        Logger.info(I18n.t(:user_created, username: username))
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :user_exists}, state}
    end
  end

  @impl true
  def handle_call({:remove_user, username}, _from, state) do
    :ets.delete(@users_table, username)

    :ets.foldl(
      fn {token, user, _perms, _ts}, _ ->
        if user == username, do: :ets.delete(@sessions_table, token)
      end,
      nil,
      @sessions_table
    )

    Logger.info(I18n.t(:user_removed, username: username))
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:change_password, username, new_password}, _from, state) do
    case :ets.lookup(@users_table, username) do
      [{^username, _old_hash, permissions}] ->
        new_hash = hash_password(new_password)
        :ets.insert(@users_table, {username, new_hash, permissions})
        Logger.info(I18n.t(:password_changed, username: username))
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :user_not_found}, state}
    end
  end

  @impl true
  def handle_info(:cleanup_sessions, state) do
    cleanup_expired_sessions()
    schedule_session_cleanup()
    {:noreply, state}
  end

  defp load_default_users do
    default_users =
      Application.get_env(:malachimq, :default_users, [
        {"admin", "admin123", [:admin]},
        {"producer", "producer123", [:produce]},
        {"consumer", "consumer123", [:consume]},
        {"app", "app123", [:produce, :consume]}
      ])

    Enum.each(default_users, fn {username, password, permissions} ->
      hash = hash_password(password)
      :ets.insert(@users_table, {username, hash, permissions})
    end)

    Logger.info(I18n.t(:default_users_loaded, count: length(default_users)))
  end

  defp hash_password(password) do
    :crypto.hash(:sha256, password) |> Base.encode64()
  end

  defp verify_password(password, stored_hash) do
    hash_password(password) == stored_hash
  end

  defp generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp schedule_session_cleanup do
    interval = Application.get_env(:malachimq, :session_cleanup_interval_ms, 60_000)
    Process.send_after(self(), :cleanup_sessions, interval)
  end

  defp cleanup_expired_sessions do
    session_timeout = Application.get_env(:malachimq, :session_timeout_ms, 3_600_000)
    now = System.monotonic_time(:millisecond)

    expired_count =
      :ets.foldl(
        fn {token, _username, _perms, created_at}, count ->
          if now - created_at >= session_timeout do
            :ets.delete(@sessions_table, token)
            count + 1
          else
            count
          end
        end,
        0,
        @sessions_table
      )

    if expired_count > 0 do
      Logger.debug(I18n.t(:sessions_cleaned, count: expired_count))
    end
  end
end
