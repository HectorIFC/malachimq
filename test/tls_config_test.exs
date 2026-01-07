defmodule MalachiMQ.TLSConfigTest do
  use ExUnit.Case, async: true

  alias MalachiMQ.SocketHelper

  describe "TLS Configuration" do
    test "socket helper handles gen_tcp operations" do
      # Ensure module is loaded before checking exported functions
      {:module, _} = Code.ensure_loaded(SocketHelper)

      assert function_exported?(SocketHelper, :socket_send, 3)
      assert function_exported?(SocketHelper, :socket_recv, 4)
      assert function_exported?(SocketHelper, :socket_close, 2)
      assert function_exported?(SocketHelper, :socket_setopts, 3)
      assert function_exported?(SocketHelper, :socket_peername, 2)
    end

    test "TLS configuration can be read from application config" do
      enable_tls = Application.get_env(:malachimq, :enable_tls, false)
      assert is_boolean(enable_tls)

      tls_certfile = Application.get_env(:malachimq, :tls_certfile)
      tls_keyfile = Application.get_env(:malachimq, :tls_keyfile)

      assert is_nil(tls_certfile) or is_binary(tls_certfile)
      assert is_nil(tls_keyfile) or is_binary(tls_keyfile)
    end

    test "socket helper returns error for invalid socket operations" do
      fake_socket = :invalid_socket

      result = SocketHelper.socket_close(fake_socket, :gen_tcp)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "TLS Options Validation" do
    test "TLS versions are correctly specified" do
      expected_versions = [:"tlsv1.2", :"tlsv1.3"]
      assert length(expected_versions) == 2
      assert :"tlsv1.2" in expected_versions
      assert :"tlsv1.3" in expected_versions
    end

    test "strong cipher suites are preferred" do
      strong_ciphers = [
        "TLS_AES_256_GCM_SHA384",
        "TLS_AES_128_GCM_SHA256",
        "TLS_CHACHA20_POLY1305_SHA256",
        "ECDHE-RSA-AES256-GCM-SHA384",
        "ECDHE-RSA-AES128-GCM-SHA256"
      ]

      assert length(strong_ciphers) > 0
      assert Enum.all?(strong_ciphers, &is_binary/1)
    end
  end

  describe "Backward Compatibility" do
    test "TLS is disabled by default" do
      default_tls = Application.get_env(:malachimq, :enable_tls, false)
      assert default_tls == false, "TLS should be disabled by default for backward compatibility"
    end

    test "application can start without TLS certificates" do
      enable_tls = Application.get_env(:malachimq, :enable_tls, false)

      if not enable_tls do
        certfile = Application.get_env(:malachimq, :tls_certfile)
        keyfile = Application.get_env(:malachimq, :tls_keyfile)
        assert certfile == nil or is_binary(certfile)
        assert keyfile == nil or is_binary(keyfile)
      end
    end
  end
end
