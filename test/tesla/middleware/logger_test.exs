defmodule Tesla.Middleware.LoggerTest do
  use ExUnit.Case, async: false

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.Logger

    adapter fn env ->
      env = Tesla.put_header(env, "content-type", "text/plain")

      case env.url do
        "/connection-error" ->
          {:error, :econnrefused}

        "/server-error" ->
          {:ok, %{env | status: 500, body: "error"}}

        "/client-error" ->
          {:ok, %{env | status: 404, body: "error"}}

        "/redirect" ->
          {:ok, %{env | status: 301, body: "moved"}}

        "/ok" ->
          {:ok, %{env | status: 200, body: "ok"}}
      end
    end
  end

  import ExUnit.CaptureLog

  describe "Logger" do
    setup do
      Logger.configure(level: :info)

      :ok
    end

    test "connection error" do
      log = capture_log(fn -> Client.get("/connection-error") end)
      assert log =~ "/connection-error -> error: :econnrefused"
    end

    test "server error" do
      log = capture_log(fn -> Client.get("/server-error") end)
      assert log =~ "/server-error -> 500"
    end

    test "client error" do
      log = capture_log(fn -> Client.get("/client-error") end)
      assert log =~ "/client-error -> 404"
    end

    test "redirect" do
      log = capture_log(fn -> Client.get("/redirect") end)
      assert log =~ "/redirect -> 301"
    end

    test "ok" do
      log = capture_log(fn -> Client.get("/ok") end)
      assert log =~ "/ok -> 200"
    end
  end

  describe "Debug mode" do
    setup do
      Logger.configure(level: :debug)
      :ok
    end

    test "ok with params" do
      log = capture_log(fn -> Client.get("/ok", query: %{"test" => "true"}) end)
      assert log =~ "Query: test: true"
    end

    test "ok with list params" do
      log = capture_log(fn -> Client.get("/ok", query: %{"test" => ["first", "second"]}) end)
      assert log =~ "Query: test[]: first"
      assert log =~ "Query: test[]: second"
    end

    test "multipart" do
      mp = Tesla.Multipart.new() |> Tesla.Multipart.add_field("field1", "foo")
      log = capture_log(fn -> Client.post("/ok", mp) end)
      assert log =~ "boundary: #{mp.boundary}"
      assert log =~ inspect(List.first(mp.parts))
    end

    test "stream" do
      stream = Stream.map(1..10, fn i -> "chunk: #{i}" end)
      log = capture_log(fn -> Client.post("/ok", stream) end)
      assert log =~ "/ok -> 200"
      assert log =~ "Stream"
    end

    test "config at runtime" do
      client =
        Tesla.client([{Tesla.Middleware.Logger, debug: false}], fn env ->
          {:ok, %{env | body: "response"}}
        end)

      log = capture_log(fn -> Tesla.get(client, "/ok", query: %{"test" => "true"}) end)
      refute log =~ "Query: test: true"
    end
  end

  describe "Debug mode with custom structs" do
    # An example of such use case is google-elixir-apis

    setup do
      Logger.configure(level: :debug)
      :ok
    end

    defmodule CustomStruct do
      defstruct [:data]

      def call(env, next, _opts) do
        env = %{env | body: encode(env.body)}

        with {:ok, env} <- Tesla.run(env, next) do
          {:ok, %{env | body: decode(env.body)}}
        end
      end

      defp encode(%__MODULE__{data: body}), do: body
      defp decode(body), do: %__MODULE__{data: body}
    end

    defmodule CustomStructClient do
      use Tesla

      plug Tesla.Middleware.Logger
      plug CustomStruct

      adapter fn env -> {:ok, %{env | status: 200, body: "ok"}} end
    end

    test "when used with custom encoders" do
      body = %CustomStruct{data: "some data"}
      log = capture_log(fn -> CustomStructClient.post("/", body) end)
      assert log =~ "CustomStruct{data"
    end
  end

  describe "with log_level" do
    defmodule ClientWithLogLevel do
      use Tesla

      plug Tesla.Middleware.Logger, log_level: &log_level/1

      defp log_level(env) do
        cond do
          env.status == 404 -> :info
          true -> Tesla.Middleware.Logger.default_log_level(env)
        end
      end

      adapter fn env ->
        case env.url do
          "/bad-request" ->
            {:ok, %{env | status: 400, body: "bad request"}}

          "/not-found" ->
            {:ok, %{env | status: 404, body: "not found"}}

          "/ok" ->
            {:ok, %{env | status: 200, body: "ok"}}
        end
      end
    end

    test "not found" do
      log = capture_log(fn -> ClientWithLogLevel.get("/not-found") end)
      assert log =~ "[info] GET /not-found -> 404"
    end

    test "bad request" do
      log = capture_log(fn -> ClientWithLogLevel.get("/bad-request") end)
      assert log =~ "[error] GET /bad-request -> 400"
    end

    test "ok" do
      log = capture_log(fn -> ClientWithLogLevel.get("/ok") end)
      assert log =~ "[info] GET /ok -> 200"
    end
  end

  describe "with filter_headers" do
    setup do
      Logger.configure(level: :debug)
      middleware = [{Tesla.Middleware.Logger, filter_headers: ["authorization"]}]
      adapter = fn env -> {:ok, %{env | status: 200, body: "ok"}} end
      client = Tesla.client(middleware, adapter)
      %{client: client}
    end

    test "sanitizes given header values", %{client: client} do
      headers = [
        {"authorization", "Basic my-secret"},
        {"other-header", "is not filtered"}
      ]

      log = capture_log(fn -> Tesla.get(client, "/ok", headers: headers) end)

      assert log =~ "authorization: [FILTERED]"
      assert log =~ "other-header: is not filtered"
    end
  end

  alias Tesla.Middleware.Logger.Formatter

  defmodule CompileMod do
    def format(_req, _resp, _time) do
      "message"
    end
  end

  describe "Formatter: compile/1" do
    test "compile default format" do
      assert is_list(Formatter.compile(nil))
    end

    test "compile with funtion" do
      assert Formatter.compile(&CompileMod.format/3) == (&CompileMod.format/3)
    end

    test "compile with {mod, fun}" do
      assert Formatter.compile({CompileMod, :format}) == {CompileMod, :format}
    end

    test "comppile pattern" do
      assert Formatter.compile("$method $url => $status") == [:method, " ", :url, " => ", :status]
    end

    test "raise compile-time error when pattern not found" do
      assert_raise ArgumentError, fn ->
        Formatter.compile("$method $nope")
      end
    end
  end

  describe "Formatter: format/2" do
    setup do
      format = Formatter.compile("$method $url $query -> $status | $time")
      {:ok, format: format}
    end

    test "format error", %{format: format} do
      req = %Tesla.Env{method: :get, url: "/error"}
      res = {:error, :econnrefused}

      assert IO.chardata_to_string(Formatter.format(req, res, 200_000, format)) ==
               "GET /error  -> error: :econnrefused | 200.000"
    end

    test "format ok response", %{format: format} do
      req = %Tesla.Env{method: :get, url: "/ok"}
      res = {:ok, %Tesla.Env{method: :get, url: "/ok", status: 201}}

      assert IO.chardata_to_string(Formatter.format(req, res, 200_000, format)) ==
               "GET /ok  -> 201 | 200.000"
    end

    test "format query string", %{format: format} do
      req = %Tesla.Env{
        method: :get,
        url: "/get",
        query: [
          page: 1,
          sort: "desc",
          status: ["a", "b", "c"],
          user: [name: "Jon", age: 20]
        ]
      }

      res = {:ok, %Tesla.Env{method: :get, url: "/ok", status: 201}}

      assert IO.chardata_to_string(Formatter.format(req, res, 200_000, format)) ==
               "GET /get page=1&sort=desc&status%5B%5D=a&status%5B%5D=b&status%5B%5D=c&user%5Bname%5D=Jon&user%5Bage%5D=20 -> 201 | 200.000"
    end

    test "format with funtion" do
      assert Formatter.format(nil, nil, nil, &CompileMod.format/3) == "message"
    end

    test "format with {mod, fun}" do
      assert Formatter.format(nil, nil, nil, {CompileMod, :format}) == "message"
    end
  end
end
