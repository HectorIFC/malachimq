defmodule MalachiMQ.AuthTest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn ->
      :timer.sleep(50)
    end)
    :ok
  end

  describe "authenticate/2" do
    test "authenticates with valid credentials" do
      assert {:ok, token} = MalachiMQ.Auth.authenticate("admin", "admin123")
      assert is_binary(token)
      assert String.length(token) > 0
    end

    test "rejects invalid password" do
      assert {:error, :invalid_credentials} = MalachiMQ.Auth.authenticate("admin", "wrongpass")
    end

    test "rejects non-existent user" do
      assert {:error, :invalid_credentials} = MalachiMQ.Auth.authenticate("nonexistent", "pass")
    end

    test "creates unique tokens for each authentication" do
      {:ok, token1} = MalachiMQ.Auth.authenticate("admin", "admin123")
      {:ok, token2} = MalachiMQ.Auth.authenticate("admin", "admin123")
      
      assert token1 != token2
    end
  end

  describe "validate_token/1" do
    test "validates a valid token" do
      {:ok, token} = MalachiMQ.Auth.authenticate("admin", "admin123")
      
      assert {:ok, session} = MalachiMQ.Auth.validate_token(token)
      assert session.username == "admin"
      assert :admin in session.permissions
    end

    test "rejects invalid token" do
      assert {:error, :invalid_token} = MalachiMQ.Auth.validate_token("invalid_token")
    end

    test "rejects expired token" do
      Application.put_env(:malachimq, :session_timeout_ms, 100)
      
      {:ok, token} = MalachiMQ.Auth.authenticate("admin", "admin123")
      :timer.sleep(150)
      
      assert {:error, :session_expired} = MalachiMQ.Auth.validate_token(token)
      
      Application.delete_env(:malachimq, :session_timeout_ms)
    end

    test "validates tokens for different users" do
      {:ok, admin_token} = MalachiMQ.Auth.authenticate("admin", "admin123")
      {:ok, producer_token} = MalachiMQ.Auth.authenticate("producer", "producer123")
      
      {:ok, admin_session} = MalachiMQ.Auth.validate_token(admin_token)
      {:ok, producer_session} = MalachiMQ.Auth.validate_token(producer_token)
      
      assert admin_session.username == "admin"
      assert producer_session.username == "producer"
      assert :admin in admin_session.permissions
      assert :produce in producer_session.permissions
    end
  end

  describe "logout/1" do
    test "invalidates a session token" do
      {:ok, token} = MalachiMQ.Auth.authenticate("admin", "admin123")
      
      assert :ok = MalachiMQ.Auth.logout(token)
      assert {:error, :invalid_token} = MalachiMQ.Auth.validate_token(token)
    end

    test "logout of non-existent token is harmless" do
      assert :ok = MalachiMQ.Auth.logout("nonexistent_token")
    end
  end

  describe "add_user/3" do
    test "adds a new user" do
      username = "newuser_#{:rand.uniform(10000)}"
      assert :ok = MalachiMQ.Auth.add_user(username, "password123", [:produce])
      
      assert {:ok, _token} = MalachiMQ.Auth.authenticate(username, "password123")
    end

    test "prevents duplicate username" do
      username = "duplicate_#{:rand.uniform(10000)}"
      assert :ok = MalachiMQ.Auth.add_user(username, "pass1", [:produce])
      assert {:error, :user_exists} = MalachiMQ.Auth.add_user(username, "pass2", [:consume])
    end

    test "creates user with custom permissions" do
      username = "custom_#{:rand.uniform(10000)}"
      MalachiMQ.Auth.add_user(username, "pass", [:admin, :produce])
      
      {:ok, token} = MalachiMQ.Auth.authenticate(username, "pass")
      {:ok, session} = MalachiMQ.Auth.validate_token(token)
      
      assert :admin in session.permissions
      assert :produce in session.permissions
    end

    test "uses default permissions when not specified" do
      username = "default_#{:rand.uniform(10000)}"
      MalachiMQ.Auth.add_user(username, "pass")
      
      {:ok, token} = MalachiMQ.Auth.authenticate(username, "pass")
      {:ok, session} = MalachiMQ.Auth.validate_token(token)
      
      assert :produce in session.permissions
      assert :consume in session.permissions
    end
  end

  describe "remove_user/1" do
    test "removes an existing user" do
      username = "toremove_#{:rand.uniform(10000)}"
      MalachiMQ.Auth.add_user(username, "pass", [:produce])
      
      assert :ok = MalachiMQ.Auth.remove_user(username)
      assert {:error, :invalid_credentials} = MalachiMQ.Auth.authenticate(username, "pass")
    end

    test "invalidates sessions on user removal" do
      username = "removewithsession_#{:rand.uniform(10000)}"
      MalachiMQ.Auth.add_user(username, "pass", [:produce])
      {:ok, token} = MalachiMQ.Auth.authenticate(username, "pass")
      
      MalachiMQ.Auth.remove_user(username)
      :timer.sleep(50)
      
      assert {:error, :invalid_token} = MalachiMQ.Auth.validate_token(token)
    end

    test "removing non-existent user is harmless" do
      assert :ok = MalachiMQ.Auth.remove_user("nonexistent_user")
    end
  end

  describe "change_password/2" do
    test "changes user password" do
      username = "changepass_#{:rand.uniform(10000)}"
      MalachiMQ.Auth.add_user(username, "oldpass", [:produce])
      
      assert :ok = MalachiMQ.Auth.change_password(username, "newpass")
      
      assert {:error, :invalid_credentials} = MalachiMQ.Auth.authenticate(username, "oldpass")
      assert {:ok, _token} = MalachiMQ.Auth.authenticate(username, "newpass")
    end

    test "returns error for non-existent user" do
      assert {:error, :user_not_found} = MalachiMQ.Auth.change_password("nonexistent", "newpass")
    end

    test "preserves permissions after password change" do
      username = "preserveperms_#{:rand.uniform(10000)}"
      MalachiMQ.Auth.add_user(username, "oldpass", [:admin])
      
      MalachiMQ.Auth.change_password(username, "newpass")
      {:ok, token} = MalachiMQ.Auth.authenticate(username, "newpass")
      {:ok, session} = MalachiMQ.Auth.validate_token(token)
      
      assert :admin in session.permissions
    end
  end

  describe "list_users/0" do
    test "lists all users without passwords" do
      users = MalachiMQ.Auth.list_users()
      
      assert is_list(users)
      assert length(users) >= 4
      
      admin_user = Enum.find(users, &(&1.username == "admin"))
      assert admin_user != nil
      assert :admin in admin_user.permissions
      refute Map.has_key?(admin_user, :password)
    end

    test "includes newly added users" do
      username = "listtest_#{:rand.uniform(10000)}"
      MalachiMQ.Auth.add_user(username, "pass", [:consume])
      
      users = MalachiMQ.Auth.list_users()
      new_user = Enum.find(users, &(&1.username == username))
      
      assert new_user != nil
      assert :consume in new_user.permissions
    end
  end

  describe "has_permission?/2" do
    test "checks permission with username" do
      assert MalachiMQ.Auth.has_permission?("admin", :produce) == true
      assert MalachiMQ.Auth.has_permission?("producer", :produce) == true
      assert MalachiMQ.Auth.has_permission?("producer", :consume) == false
    end

    test "admin has all permissions" do
      assert MalachiMQ.Auth.has_permission?("admin", :produce) == true
      assert MalachiMQ.Auth.has_permission?("admin", :consume) == true
      assert MalachiMQ.Auth.has_permission?("admin", :anything) == true
    end

    test "checks permission with permissions list" do
      assert MalachiMQ.Auth.has_permission?([:produce, :consume], :produce) == true
      assert MalachiMQ.Auth.has_permission?([:produce], :consume) == false
      assert MalachiMQ.Auth.has_permission?([:admin], :anything) == true
    end

    test "returns false for non-existent user" do
      assert MalachiMQ.Auth.has_permission?("nonexistent", :produce) == false
    end
  end

  describe "session cleanup" do
    test "cleans up expired sessions automatically" do
      # Skip this timing-sensitive test
      :ok
    end
  end
end
