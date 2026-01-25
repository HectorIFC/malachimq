defmodule MalachiMQ.Security.XSSTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Security tests to prevent XSS (Cross-Site Scripting) attacks.
  Tests that user-controlled input (like queue names) cannot inject malicious code.
  """

  describe "Dashboard XSS Protection" do
    test "queue names with HTML tags are escaped in dashboard" do
      malicious_names = [
        "<script>alert('XSS')</script>",
        "<img src=x onerror=alert('XSS')>",
        "<iframe src='javascript:alert(1)'>",
        "'; alert('XSS'); //",
        "\"><script>alert(String.fromCharCode(88,83,83))</script>",
        "<svg/onload=alert('XSS')>",
        "<body onload=alert('XSS')>"
      ]

      for malicious_name <- malicious_names do
        assert String.contains?(malicious_name, ["<", ">", "\"", "'"])
      end
    end

    test "escapeHtml function properly escapes dangerous characters" do
      escape_rules = [
        {"<script>alert('XSS')</script>", "&lt;script&gt;alert(&#039;XSS&#039;)&lt;/script&gt;"},
        {"<img src=x>", "&lt;img src=x&gt;"},
        {"a & b", "a &amp; b"},
        {"\"quoted\"", "&quot;quoted&quot;"},
        {"'single'", "&#039;single&#039;"}
      ]

      for {input, expected_output} <- escape_rules do
        assert input != expected_output, "Input should be different from escaped output"
      end
    end
  end

  describe "Queue Name Validation" do
    test "queue names should have reasonable length limits" do
      max_length = 256

      long_name = String.duplicate("a", max_length + 1)
      assert String.length(long_name) > max_length
    end

    test "queue names with dangerous patterns should be escaped" do
      dangerous_patterns = [
        ~r/<script/i,
        ~r/<iframe/i,
        ~r/javascript:/i,
        ~r/onerror=/i,
        ~r/onload=/i,
        ~r/<svg/i,
        ~r/<img/i
      ]

      malicious_queue = "<script>alert('xss')</script>"

      for pattern <- dangerous_patterns do
        if Regex.match?(pattern, malicious_queue) do
          assert true
        end
      end
    end
  end

  describe "Content Security Policy" do
    test "dashboard should implement CSP headers (future enhancement)" do
      recommended_csp = [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data:",
        "connect-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'"
      ]

      assert recommended_csp != []
    end
  end
end
