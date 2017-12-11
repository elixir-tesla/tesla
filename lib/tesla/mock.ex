defmodule Tesla.Mock do
  @moduledoc """
  Mock adapter for better testing.

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
  using `mock_global/1` function.

  ```
  defmodule MyTest do
    use ExUnit.Case, async: false # must be false!

    setup_all do
      Tesla.Mock.mock_global fn
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
  end

  ## PUBLIC API

  @doc """
  Setup mocks for current test.

  This mock will only be available to the current process.
  """
  @spec mock((Tesla.Env.t -> Tesla.Env.t | {integer, map, any})) :: no_return
  def mock(fun) when is_function(fun), do: pdict_set(fun)

  @doc """
  Setup global mocks.

  **WARNING**: This mock will be available to ALL processes.
  It might cause conflicts when running tests in parallel!
  """
  @spec mock_global((Tesla.Env.t -> Tesla.Env.t | {integer, map, any})) :: no_return
  def mock_global(fun) when is_function(fun), do: agent_set(fun)



  ## ADAPTER IMPLEMENTATION

  def call(env, _opts) do
    case pdict_get() || agent_get() do
      nil ->
        raise Tesla.Mock.Error, env: env
      fun ->
        case rescue_call(fun, env) do
          {status, headers, body} ->
            %{env | status: status, headers: headers, body: body}
          %Tesla.Env{} = env ->
            env
        end
    end
  end

  defp pdict_set(fun), do: Process.put(__MODULE__, fun)
  defp pdict_get, do: Process.get(__MODULE__)

  defp agent_set(fun), do: {:ok, _pid} = Agent.start_link(fn -> fun end, name: __MODULE__)
  defp agent_get do
    case Process.whereis(__MODULE__) do
      nil -> nil
      pid -> Agent.get(pid, fn f -> f end)
    end
  end

  defp rescue_call(fun, env) do
    fun.(env)
  rescue
    ex in FunctionClauseError ->
      raise Tesla.Mock.Error, env: env, ex: ex, stacktrace: System.stacktrace()
  end
end
