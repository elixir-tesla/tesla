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
  """
  @spec mock((Tesla.Env.t -> Tesla.Env.t | {integer, map, any})) :: no_return
  def mock(fun) when is_function(fun) do
    Process.put(__MODULE__, fun)
  end


  ## ADAPTER IMPLEMENTATION

  def call(env, _opts) do
    case Process.get(__MODULE__) do
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

  defp rescue_call(fun, env) do
    fun.(env)
  rescue
    ex in FunctionClauseError ->
      raise Tesla.Mock.Error, env: env, ex: ex, stacktrace: System.stacktrace()
  end
end
