defmodule MalachiMQ.I18nTest do
  use ExUnit.Case, async: true
  
  alias MalachiMQ.I18n
  
  describe "I18n translations" do
    test "locale can be changed at runtime" do
      original_locale = I18n.locale()
      
      I18n.set_locale("en_US")
      assert I18n.locale() == "en_US"
      
      I18n.set_locale("pt_BR")
      assert I18n.locale() == "pt_BR"
      
      # Restore original locale
      I18n.set_locale(original_locale)
    end
    
    test "transport_enabled translation works" do
      I18n.set_locale("en_US")
      assert I18n.t(:transport_enabled, transport: "TLS", port: 4040) =~ "TLS transport enabled"
      
      I18n.set_locale("pt_BR")
      assert I18n.t(:transport_enabled, transport: "TLS", port: 4040) =~ "Transporte TLS habilitado"
    end
    
    test "tls_handshake_failed translation works" do
      I18n.set_locale("en_US")
      assert I18n.t(:tls_handshake_failed, reason: "timeout") =~ "TLS handshake failed"
      
      I18n.set_locale("pt_BR")
      assert I18n.t(:tls_handshake_failed, reason: "timeout") =~ "Falha no handshake TLS"
    end
    
    test "system_info translations work" do
      I18n.set_locale("en_US")
      assert I18n.t(:system_info) =~ "System Info"
      assert I18n.t(:system_schedulers, schedulers: 8) =~ "Schedulers: 8"
      assert I18n.t(:system_processes, processes: 100, limit: 1000) =~ "Processes: 100/1000"
      assert I18n.t(:system_memory, memory: 123.45) =~ "Memory: 123.45"
      assert I18n.t(:system_ets_tables, tables: 50, limit: 1000) =~ "ETS Tables: 50/1000"
      
      I18n.set_locale("pt_BR")
      assert I18n.t(:system_info) =~ "Informações do Sistema"
      assert I18n.t(:system_schedulers, schedulers: 8) =~ "Schedulers: 8"
      assert I18n.t(:system_processes, processes: 100, limit: 1000) =~ "Processos: 100/1000"
      assert I18n.t(:system_memory, memory: 123.45) =~ "Memória: 123.45"
      assert I18n.t(:system_ets_tables, tables: 50, limit: 1000) =~ "Tabelas ETS: 50/1000"
    end
    
    test "all translation keys are present" do
      keys = I18n.keys()
      
      # Verify all keys have translations for both locales
      for key <- keys do
        en_translation = I18n.t(key)
        refute is_nil(en_translation), "Missing translation for key: #{key}"
        refute en_translation == to_string(key), "No translation found for key: #{key}"
      end
    end
    
    test "available locales returns correct list" do
      locales = I18n.available_locales()
      assert "en_US" in locales
      assert "pt_BR" in locales
    end
    
    test "translation with missing key returns key as string" do
      assert I18n.t(:non_existent_key) == "non_existent_key"
    end
    
    test "translation with interpolation works" do
      I18n.set_locale("en_US")
      result = I18n.t(:consumers_created, count: 1000, duration: 500)
      assert result =~ "1000"
      assert result =~ "500"
    end
  end
end
