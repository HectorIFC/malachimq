defmodule MalachiMQ.ChannelIntegrationTest do
  use ExUnit.Case, async: false

  @port 4040
  @host ~c"localhost"

  defp connect_and_auth(username \\ "consumer", password \\ "consumer123") do
    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, packet: :line, active: false])

    auth_msg = Jason.encode!(%{action: "auth", username: username, password: password}) <> "\n"
    :ok = :gen_tcp.send(socket, auth_msg)

    {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
    {:ok, parsed} = Jason.decode(String.trim(response))

    assert parsed["s"] == "ok"
    assert is_binary(parsed["token"])

    socket
  end

  defp close_socket(socket) do
    :gen_tcp.close(socket)
  end

  describe "channel_publish action" do
    test "publishes message to channel" do
      socket = connect_and_auth("producer", "producer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: "test_pub_channel",
          payload: "hello channel"
        }) <> "\n"

      :ok = :gen_tcp.send(socket, publish_msg)
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"

      close_socket(socket)
    end

    test "publishes message with headers" do
      socket = connect_and_auth("producer", "producer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: "test_headers_channel",
          payload: "test",
          headers: %{"priority" => "high", "source" => "test"}
        }) <> "\n"

      :ok = :gen_tcp.send(socket, publish_msg)
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"

      close_socket(socket)
    end

    test "requires produce permission" do
      socket = connect_and_auth("consumer", "consumer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: "test_channel",
          payload: "test"
        }) <> "\n"

      :ok = :gen_tcp.send(socket, publish_msg)
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "permission_denied"

      close_socket(socket)
    end
  end

  describe "channel_subscribe action" do
    test "subscribes to channel and receives messages" do
      channel_name = "test_sub_channel_#{:rand.uniform(100_000)}"

      # Consumer subscribes
      consumer_socket = connect_and_auth("consumer", "consumer123")
      :inet.setopts(consumer_socket, active: false)

      sub_msg =
        Jason.encode!(%{action: "channel_subscribe", channel_name: channel_name}) <> "\n"

      :ok = :gen_tcp.send(consumer_socket, sub_msg)
      {:ok, sub_response} = :gen_tcp.recv(consumer_socket, 0, 5000)
      {:ok, sub_parsed} = Jason.decode(String.trim(sub_response))

      assert sub_parsed["s"] == "ok"

      # Producer publishes
      producer_socket = connect_and_auth("producer", "producer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: channel_name,
          payload: "broadcast message"
        }) <> "\n"

      :ok = :gen_tcp.send(producer_socket, publish_msg)
      {:ok, pub_response} = :gen_tcp.recv(producer_socket, 0, 5000)
      {:ok, pub_parsed} = Jason.decode(String.trim(pub_response))

      assert pub_parsed["s"] == "ok"

      # Consumer receives message
      {:ok, message_data} = :gen_tcp.recv(consumer_socket, 0, 5000)
      {:ok, message} = Jason.decode(String.trim(message_data))

      assert message["channel_message"]["payload"] == "broadcast message"
      assert message["channel_message"]["channel"] == channel_name

      close_socket(consumer_socket)
      close_socket(producer_socket)
    end

    test "multiple subscribers receive same message" do
      channel_name = "test_broadcast_#{:rand.uniform(100_000)}"

      # Two consumers subscribe
      consumer1 = connect_and_auth("consumer", "consumer123")
      consumer2 = connect_and_auth("consumer", "consumer123")

      :inet.setopts(consumer1, active: false)
      :inet.setopts(consumer2, active: false)

      sub_msg = Jason.encode!(%{action: "channel_subscribe", channel_name: channel_name}) <> "\n"

      :ok = :gen_tcp.send(consumer1, sub_msg)
      {:ok, _} = :gen_tcp.recv(consumer1, 0, 5000)

      :ok = :gen_tcp.send(consumer2, sub_msg)
      {:ok, _} = :gen_tcp.recv(consumer2, 0, 5000)

      # Producer publishes
      producer = connect_and_auth("producer", "producer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: channel_name,
          payload: "broadcast to all"
        }) <> "\n"

      :ok = :gen_tcp.send(producer, publish_msg)
      {:ok, _} = :gen_tcp.recv(producer, 0, 5000)

      # Both consumers receive
      {:ok, msg1_data} = :gen_tcp.recv(consumer1, 0, 5000)
      {:ok, msg1} = Jason.decode(String.trim(msg1_data))

      {:ok, msg2_data} = :gen_tcp.recv(consumer2, 0, 5000)
      {:ok, msg2} = Jason.decode(String.trim(msg2_data))

      assert msg1["channel_message"]["payload"] == "broadcast to all"
      assert msg2["channel_message"]["payload"] == "broadcast to all"

      close_socket(consumer1)
      close_socket(consumer2)
      close_socket(producer)
    end

    test "requires consume permission" do
      socket = connect_and_auth("producer", "producer123")

      sub_msg = Jason.encode!(%{action: "channel_subscribe", channel_name: "test"}) <> "\n"

      :ok = :gen_tcp.send(socket, sub_msg)
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "permission_denied"

      close_socket(socket)
    end
  end

  describe "get_channel_info action" do
    test "returns channel information" do
      channel_name = "test_info_channel_#{:rand.uniform(100_000)}"

      # Create channel by publishing
      producer = connect_and_auth("producer", "producer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: channel_name,
          payload: "test"
        }) <> "\n"

      :ok = :gen_tcp.send(producer, publish_msg)
      {:ok, _} = :gen_tcp.recv(producer, 0, 5000)

      # Get channel info
      info_msg = Jason.encode!(%{action: "get_channel_info", channel_name: channel_name}) <> "\n"

      :ok = :gen_tcp.send(producer, info_msg)
      {:ok, response} = :gen_tcp.recv(producer, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      assert parsed["channel_info"]["channel_name"] == channel_name
      assert parsed["channel_info"]["exists"] == true
      assert is_integer(parsed["channel_info"]["subscribers"])
      assert is_integer(parsed["channel_info"]["published"])

      close_socket(producer)
    end

    test "shows subscriber count" do
      channel_name = "test_subscriber_count_#{:rand.uniform(100_000)}"

      # Subscribe with two consumers
      consumer1 = connect_and_auth("consumer", "consumer123")
      consumer2 = connect_and_auth("consumer", "consumer123")

      sub_msg = Jason.encode!(%{action: "channel_subscribe", channel_name: channel_name}) <> "\n"

      :ok = :gen_tcp.send(consumer1, sub_msg)
      {:ok, _} = :gen_tcp.recv(consumer1, 0, 5000)

      :ok = :gen_tcp.send(consumer2, sub_msg)
      {:ok, _} = :gen_tcp.recv(consumer2, 0, 5000)

      # Check info
      admin = connect_and_auth("admin", "admin123")

      info_msg = Jason.encode!(%{action: "get_channel_info", channel_name: channel_name}) <> "\n"

      :ok = :gen_tcp.send(admin, info_msg)
      {:ok, response} = :gen_tcp.recv(admin, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["channel_info"]["subscribers"] == 2

      close_socket(consumer1)
      close_socket(consumer2)
      close_socket(admin)
    end

    test "requires appropriate permissions" do
      socket = connect_and_auth("consumer", "consumer123")

      info_msg = Jason.encode!(%{action: "get_channel_info", channel_name: "test"}) <> "\n"

      :ok = :gen_tcp.send(socket, info_msg)
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      # Consumer should have permission to get info
      assert parsed["s"] == "ok"

      close_socket(socket)
    end
  end

  describe "message delivery" do
    test "messages include headers in channel delivery" do
      channel_name = "test_headers_delivery_#{:rand.uniform(100_000)}"

      consumer = connect_and_auth("consumer", "consumer123")
      :inet.setopts(consumer, active: false)

      sub_msg = Jason.encode!(%{action: "channel_subscribe", channel_name: channel_name}) <> "\n"

      :ok = :gen_tcp.send(consumer, sub_msg)
      {:ok, _} = :gen_tcp.recv(consumer, 0, 5000)

      producer = connect_and_auth("producer", "producer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: channel_name,
          payload: "with headers",
          headers: %{"priority" => 5, "type" => "alert"}
        }) <> "\n"

      :ok = :gen_tcp.send(producer, publish_msg)
      {:ok, _} = :gen_tcp.recv(producer, 0, 5000)

      {:ok, msg_data} = :gen_tcp.recv(consumer, 0, 5000)
      {:ok, msg} = Jason.decode(String.trim(msg_data))

      assert msg["channel_message"]["headers"]["priority"] == 5
      assert msg["channel_message"]["headers"]["type"] == "alert"

      close_socket(consumer)
      close_socket(producer)
    end

    test "messages are not persisted - no buffer for offline subscribers" do
      channel_name = "test_no_buffer_#{:rand.uniform(100_000)}"

      # Publish message with no subscribers
      producer = connect_and_auth("producer", "producer123")

      publish_msg =
        Jason.encode!(%{
          action: "channel_publish",
          channel_name: channel_name,
          payload: "lost message"
        }) <> "\n"

      :ok = :gen_tcp.send(producer, publish_msg)
      {:ok, _} = :gen_tcp.recv(producer, 0, 5000)

      # Now subscribe - should not receive the old message
      consumer = connect_and_auth("consumer", "consumer123")
      :inet.setopts(consumer, active: false)

      sub_msg = Jason.encode!(%{action: "channel_subscribe", channel_name: channel_name}) <> "\n"

      :ok = :gen_tcp.send(consumer, sub_msg)
      {:ok, _} = :gen_tcp.recv(consumer, 0, 5000)

      # Should timeout waiting for message since it was dropped
      result = :gen_tcp.recv(consumer, 0, 1000)
      assert result == {:error, :timeout}

      close_socket(consumer)
      close_socket(producer)
    end
  end
end
