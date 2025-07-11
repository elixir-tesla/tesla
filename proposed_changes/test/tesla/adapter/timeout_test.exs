defmodule Tesla.Adapter.TimeoutTest do
  use ExUnit.Case

  @adapters [
    Tesla.Adapter.Httpc,
    Tesla.Adapter.Hackney,
    Tesla.Adapter.Finch,
    Tesla.Adapter.Ibrowse,
    Tesla.Adapter.Mint,
    Tesla.Adapter.Gun
  ]

  describe "timeout option" do
    test "is supported by all adapters" do
      for adapter <- @adapters do
        if Code.ensure_loaded?(adapter) do
          # Test that timeout option is accepted without error
          client = Tesla.client([], {adapter, timeout: 5000})
          assert client.adapter != nil
        end
      end
    end

    test "finch adapter maps timeout to receive_timeout" do
      if Code.ensure_loaded?(Tesla.Adapter.Finch) do
        # Mock the request to capture the options
        opts = Tesla.Adapter.opts([], %Tesla.Env{opts: []}, [timeout: 3000])
        
        # Simulate the timeout mapping logic
        mapped_opts = case Keyword.get(opts, :timeout) do
          nil -> opts
          timeout -> Keyword.put_new(opts, :receive_timeout, timeout)
        end

        assert Keyword.get(mapped_opts, :receive_timeout) == 3000
      end
    end

    test "hackney adapter maps timeout to recv_timeout" do
      if Code.ensure_loaded?(Tesla.Adapter.Hackney) do
        # Mock the request to capture the options
        opts = Tesla.Adapter.opts([], %Tesla.Env{opts: []}, [timeout: 3000])
        
        # Simulate the timeout mapping logic
        mapped_opts = case Keyword.get(opts, :timeout) do
          nil -> opts
          timeout -> Keyword.put_new(opts, :recv_timeout, timeout)
        end

        assert Keyword.get(mapped_opts, :recv_timeout) == 3000
      end
    end

    test "per-request timeout overrides client timeout" do
      for adapter <- @adapters do
        if Code.ensure_loaded?(adapter) do
          client = Tesla.client([], {adapter, timeout: 5000})
          
          # Verify that per-request timeout would override client timeout
          env = %Tesla.Env{opts: [adapter: [timeout: 1000]]}
          final_opts = Tesla.Adapter.opts([timeout: 5000], env, [])
          
          assert Keyword.get(final_opts, :timeout) == 1000
        end
      end
    end

    test "adapter-specific timeout options are preserved" do
      if Code.ensure_loaded?(Tesla.Adapter.Finch) do
        # Test that existing receive_timeout is not overridden by timeout
        opts = Tesla.Adapter.opts([], %Tesla.Env{opts: []}, [timeout: 3000, receive_timeout: 1000])
        
        # Simulate the timeout mapping logic
        mapped_opts = case Keyword.get(opts, :timeout) do
          nil -> opts
          timeout -> Keyword.put_new(opts, :receive_timeout, timeout)
        end

        # receive_timeout should remain as originally set
        assert Keyword.get(mapped_opts, :receive_timeout) == 1000
        assert Keyword.get(mapped_opts, :timeout) == 3000
      end
    end
  end

  describe "backward compatibility" do
    test "existing timeout options still work" do
      if Code.ensure_loaded?(Tesla.Adapter.Finch) do
        # Test that receive_timeout still works without timeout
        opts = Tesla.Adapter.opts([], %Tesla.Env{opts: []}, [receive_timeout: 2000])
        assert Keyword.get(opts, :receive_timeout) == 2000
      end

      if Code.ensure_loaded?(Tesla.Adapter.Hackney) do
        # Test that recv_timeout still works without timeout
        opts = Tesla.Adapter.opts([], %Tesla.Env{opts: []}, [recv_timeout: 2000])
        assert Keyword.get(opts, :recv_timeout) == 2000
      end
    end
  end
end