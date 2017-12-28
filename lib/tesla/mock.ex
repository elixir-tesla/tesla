defmodule Tesla.Mock do
  @moduledoc """
  Mock adapter for better testing.
  Based on [mox](https://github.com/plataformatec/mox)

  ### Setup

  ```
  # config/test.exs
  config :tesla, adapter: :mock

  # in case MyClient defines specific adapter with `adapter :specific`
  config :tesla, MyClient, adapter: :mock
  ```

  ### Example test
  ```
  defmodule MyAppTest do
    use ExUnit.Case

    setup do
      Tesla.Mock.mock fn
        %{method: :get} ->
          %Tesla.Env{status: 200, body: "hello"}
      end

      :ok
    end

    test "list things" do
      assert %Tesla.Env{} = env = MyApp.get("...")
      assert env.status == 200
      assert env.body == "hello"
    end
  end
  ```

  ### Setting up mocks
  ```
  # Match on method & url and return whole Tesla.Env
  Tesla.Mock.mock fn
    %{method: :get,  url: "http://example.com/list"} ->
      %Tesla.Env{status: 200, body: "hello"}
  end

  # You can use any logic required
  Tesla.Mock.mock fn env ->
    case env.url do
      "http://example.com/list" ->
        %Tesla.Env{status: 200, body: "ok!"}
      _ ->
        %Tesla.Env{status: 404, body: "NotFound"}
  end

  # mock will also accept short version of response
  # in the form of {status, headers, body}
  Tesla.Mock.mock fn
    %{method: :post} -> {201, %{}, %{id: 42}}
  end
  ```

  ### Global mocks
  By default, mocks are bound to the current process,
  i.e. the process running a single test case.
  This design allows proper isolation between test cases
  and make testing in parallel (`async: true`) possible.

  While this style is recommended, there is one drawback:
  if Tesla client is called from different process
  it will not use the setup mock.

  To solve this issue it is possible to setup a global mock
  using `set_global/0` function.

  ```
  defmodule MyTest do
    use ExUnit.Case, async: false # must be false!

    setup_all do
      Tesla.Mock.set_global()

      Tesla.Mock.mock fn
        env -> # ...
      end

      :ok
    end

    # ...
  end
  ```

  **WARNING**: Using global mocks may affect tests with local mock
  (because of fallback to global mock in case local one is not found)
  """

  require Logger
  @mox Tesla.Mock.AdapterMock
  Mox.defmock(@mox, for: Tesla.Adapter)

  defmodule Error do
    defexception env: nil, ex: nil, stacktrace: []

    def message(%__MODULE__{ex: nil}) do
      """
      There is no mock set for process #{inspect(self())}.
      Use Tesla.Mock.mock/1 to mock HTTP requests.
      See https://github.com/teamon/tesla#testing
      """
    end

    def message(%__MODULE__{env: env, ex: %FunctionClauseError{} = ex, stacktrace: stacktrace}) do
      """
      Request not mocked
      The following request was not mocked:
      #{inspect(env, pretty: true)}
      #{Exception.format(:error, ex, stacktrace)}
      """
    end

    def message(%__MODULE__{env: env, ex: %Mox.UnexpectedCallError{} = ex, stacktrace: stacktrace}) do
      """
      Mock not set
      There is no mock set for this client
      #{inspect(env, pretty: true)}
      #{Exception.format(:error, ex, stacktrace)}
      """
    end
  end

  ## PUBLIC API

  @doc """
  Setup mocks for current test.

  This mock will only be available to the current process.
  """
  @spec mock((Tesla.Env.t() -> Tesla.Env.t() | {integer, map, any})) :: no_return
  def mock(fun) do
    Mox.expect(@mox, :call, fn env, _opts -> wrap(fun.(env), env) end)
  end

  @doc """
  Setup global mock mode.

  **WARNING**: This mock will be available to ALL processes.
  It might cause conflicts when running tests in parallel!
  """
  def set_global do
    Mox.set_mox_global()
  end

  ## DEPRECATED API

  def mock_global(fun) do
    Logger.warn "DEPRECATED: #{__MODULE__}.mock_global is deprecated. Use #{__MODULE__}.set_global/0 instead"
    set_global()
    mock(fun)
  end

  ## ADAPTER IMPLEMENTATION
  def call(env, opts) do
    @mox.call(env, opts)
  rescue
    ex in [Mox.UnexpectedCallError, FunctionClauseError] ->
      raise Tesla.Mock.Error, env: env, ex: ex, stacktrace: System.stacktrace()
  end

  defp wrap(%Tesla.Env{} = env, _), do: env
  defp wrap({st, hdrs, body}, env), do: %{env | status: st, headers: hdrs, body: body}
end
