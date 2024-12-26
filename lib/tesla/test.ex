defmodule Tesla.Test do
  @moduledoc """
  Provides utilities for testing Tesla-based HTTP clients.
  """

  import ExUnit.Assertions

  @doc """
  Asserts that two `t:Tesla.Env.t/0` structs match.

  ## Parameters

  - `given_env` - The actual `t:Tesla.Env.t/0` struct received from the request.
  - `expected_env` - The expected `t:Tesla.Env.t/0` struct to compare against.
  - `opts` - Additional options for fine-tuning the assertion (optional).
    - `:exclude_headers` - A list of header keys to exclude from the assertion.

  For the `body`, the function attempts to parse JSON and URL-encoded content
  when appropriate.

  This function is designed to be used in conjunction with
  `Tesla.Test.assert_received_tesla_call/1` for comprehensive request
  testing.

  ## Examples

      defmodule MyTest do
        use ExUnit.Case, async: true

        require Tesla.Test

        test "returns a 200 status" do
          given_env = %Tesla.Env{
            method: :post,
            url: "https://acme.com/users",
          }

          Tesla.Test.assert_tesla_env(given_env, %Tesla.Env{
            method: :post,
            url: "https://acme.com/users",
          })
        end
      end
  """
  def assert_tesla_env(%Tesla.Env{} = given_env, %Tesla.Env{} = expected_env, opts \\ []) do
    exclude_headers = Keyword.get(opts, :exclude_headers, [])

    given_headers =
      for {key, value} <- given_env.headers, key not in exclude_headers, do: {key, value}

    assert given_env.method == expected_env.method
    assert given_env.url == expected_env.url
    assert given_headers == expected_env.headers
    assert given_env.query == expected_env.query
    assert read_body!(given_env) == expected_env.body
  end

  @doc """
  Puts an HTML response.

      iex> Tesla.Test.html(%Tesla.Env{}, "<html><body>Hello, world!</body></html>")
      %Tesla.Env{
        body: "<html><body>Hello, world!</body></html>",
        headers: [{"content-type", "text/html; charset=utf-8"}],
        ...
      }
  """
  @spec html(%Tesla.Env{}, binary) :: %Tesla.Env{}
  def html(%Tesla.Env{} = env, body) when is_binary(body) do
    env
    |> put_body(body)
    |> put_headers([{"content-type", "text/html; charset=utf-8"}])
  end

  @doc """
  Puts a JSON response.

      iex> Tesla.Test.json(%Tesla.Env{}, %{"some" => "data"})
      %Tesla.Env{
        body: ~s({"some":"data"}),
        headers: [{"content-type", "application/json; charset=utf-8"}],
        ...
      }

  If the body is binary, it will be returned as is and it will not try to encode
  it to JSON.
  """
  @spec json(%Tesla.Env{}, term) :: %Tesla.Env{}
  def json(%Tesla.Env{} = env, body) do
    body = encode!(body, "application/json")

    env
    |> put_body(body)
    |> put_headers([{"content-type", "application/json; charset=utf-8"}])
  end

  @doc """
  Puts a text response.

      iex> Tesla.Test.text(%Tesla.Env{}, "Hello, world!")
      %Tesla.Env{
        body: "Hello, world!",
        headers: [{"content-type", "text/plain; charset=utf-8"}],
        ...
      }
  """
  @spec text(%Tesla.Env{}, binary) :: %Tesla.Env{}
  def text(%Tesla.Env{} = env, body) when is_binary(body) do
    env
    |> put_body(body)
    |> put_headers([{"content-type", "text/plain; charset=utf-8"}])
  end

  @doc """
  Asserts that the current process's mailbox does not contain any `Tesla.Test`
  messages.

  This function is designed to be used in conjunction with
  `Tesla.Test.assert_received_tesla_call/1` for comprehensive request
  testing.
  """
  defmacro assert_tesla_empty_mailbox do
    quote do
      refute_received {Tesla.Test, _}
    end
  end

  @doc """
  Asserts that the current process's mailbox contains a `TeslaMox` message.
  It uses `assert_received/1` under the hood.

  ## Parameters

  - `expected_env` - The expected `t:Tesla.Env.t/0` passed to the adapter.
  - `expected_opts` - The expected `t:Tesla.Adapter.options/0` passed to the
    adapter.
  - `opts` - Extra configuration options.
    - `:adapter` - Optional. The adapter to expect the call on. Falls back to
      the `:tesla` application configuration.

  ## Examples

  Asserting that the adapter received a `t:Tesla.Env.t/0` struct with a `200`
  status:

      defmodule MyTest do
        use ExUnit.Case, async: true

        require Tesla.Test

        test "returns a 200 status" do
          # given - preconditions
          Tesla.Test.expect_tesla_call(
            times: 2,
            returns: %Tesla.Env{status: 200, body: "OK"}
          )

          # when - run unit of work
          # ... do some work ...
          Tesla.post!("https://acme.com/users")
          # ...

          # then - assertions
          Tesla.Test.assert_received_tesla_call(expected_env, expected_opts)
          Tesla.Test.assert_tesla_env(expected_env, %Tesla.Env{
            url: "https://acme.com/users",
            status: 200,
            body: "OK"
          })
          assert expected_opts == []
          Tesla.Test.assert_tesla_empty_mailbox()
        end
      end
  """
  defmacro assert_received_tesla_call(expected_env, expected_opts \\ [], opts \\ []) do
    adapter = fetch_adapter!(opts)

    quote do
      assert_received {Tesla.Test,
                       {unquote(adapter), :call, [unquote(expected_env), unquote(expected_opts)]}}
    end
  end

  if Code.ensure_loaded?(Mox) do
    @doc """
    Expects a call on the given adapter using `Mox.expect/4`. Only available when
    `Mox` is loaded.

    ## Options

    - `:times` - Required. The number of times to expect the call.
    - `:returns` - Required. The value to return from the adapter.
    - `:send_to` - Optional. The process to send the message to. Defaults to
      the current process.
    - `:adapter` - Optional. The adapter to expect the call on. Falls back to
      the `:tesla` application configuration.

    ## Examples

    Returning a `t:Tesla.Env.t/0` struct with a `200` status:

        Tesla.Test.expect_tesla_call(
          times: 2,
          returns: %Tesla.Env{status: 200}
        )

    Changing the `Mox` mocked adapter:

        Tesla.Test.expect_tesla_call(
          times: 2,
          returns: %Tesla.Env{status: 200},
          adapter: MyApp.MockAdapter
        )
    """
    def expect_tesla_call(opts) do
      n_time = Keyword.fetch!(opts, :times)
      adapter = fetch_adapter!(opts)
      send_to = Keyword.get(opts, :send_to, self())

      Mox.expect(adapter, :call, n_time, fn given_env, given_opts ->
        if send_to != nil do
          message = {adapter, :call, [given_env, given_opts]}
          send(send_to, {Tesla.Test, message})
        end

        case Keyword.fetch!(opts, :returns) do
          fun when is_function(fun) ->
            fun.(given_env, given_opts)

          %Tesla.Env{} = value ->
            {:ok, Map.merge(given_env, Map.take(value, [:body, :headers, :status]))}

          {:error, error} ->
            {:error, error}
        end
      end)
    end
  end

  defp encode!(body, "application/json") when is_binary(body), do: body
  defp encode!(body, "application/json"), do: Jason.encode!(body)
  defp encode!(body, _), do: body

  defp read_body!(%Tesla.Env{} = env) do
    case Tesla.get_headers(env, "content-type") do
      ["application/json" | _] -> Jason.decode!(env.body, keys: :atoms)
      ["application/x-www-form-urlencoded" | _] -> URI.decode_query(env.body)
      _ -> env.body
    end
  end

  defp fetch_adapter!(opts) do
    adapter =
      Keyword.get_lazy(opts, :adapter, fn ->
        Application.get_env(:tesla, :adapter)
      end)

    case adapter do
      nil ->
        raise ArgumentError, """
        expected :adapter to be defined

        Set in the opts[:adapter]. Or set in the `config/test.exs`
        configuration:

            config :tesla, :adapter, MyApp.MockAdapter
        """

      adapter ->
        adapter
    end
  end

  defp put_body(%Tesla.Env{} = env, body) do
    %{env | body: body}
  end

  defp put_headers(%Tesla.Env{headers: nil} = env, headers) when is_list(headers) do
    %{env | headers: headers}
  end

  defp put_headers(%Tesla.Env{} = env, headers) when is_list(headers) do
    %{env | headers: env.headers ++ headers}
  end
end
