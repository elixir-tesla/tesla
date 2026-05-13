defmodule Tesla.Bench.OpenAPIParameterCollections.OperationTemplate do
  @moduledoc false

  defmacro __using__(size: size) do
    names = Enum.map(1..size, &"param#{&1}")
    path = "/items/" <> Enum.map_join(names, "/", &"{#{&1}}")

    path_params = params(names, Tesla.OpenAPI.PathParam)
    query_params = params(names, Tesla.OpenAPI.QueryParam)
    header_params = params(names, Tesla.OpenAPI.HeaderParam)
    cookie_params = params(names, Tesla.OpenAPI.CookieParam)

    quote do
      @moduledoc false

      defstruct path: nil,
                query: nil,
                headers: nil,
                cookies: nil

      @path_template Tesla.OpenAPI.PathTemplate.new!(unquote(path))
      @path_params Tesla.OpenAPI.PathParams.new!([unquote_splicing(path_params)])
      @query_params Tesla.OpenAPI.QueryParams.new!([unquote_splicing(query_params)])
      @header_params Tesla.OpenAPI.HeaderParams.new!([unquote_splicing(header_params)])
      @cookie_params Tesla.OpenAPI.CookieParams.new!([unquote_splicing(cookie_params)])

      @private Tesla.OpenAPI.merge_private([
                 Tesla.OpenAPI.PathTemplate.put_private(@path_template),
                 Tesla.OpenAPI.PathParams.put_private(@path_params),
                 Tesla.OpenAPI.QueryParams.put_private(@query_params)
               ])

      def handle_operation(
            %Tesla.Bench.OpenAPIParameterCollections.Client{client: client},
            %__MODULE__{} = operation
          ) do
        request_opts = [
          method: :get,
          url: @path_template.path,
          query: operation.query,
          headers: headers(operation),
          opts: [path_params: operation.path],
          private: @private
        ]

        case Tesla.request(client, request_opts) do
          {:ok, %Tesla.Env{} = env} ->
            {env.status, byte_size(env.url), length(env.headers)}

          {:error, reason} ->
            {:error, reason}
        end
      end

      defp headers(%__MODULE__{headers: headers, cookies: cookies}) do
        Tesla.OpenAPI.HeaderParams.to_headers(@header_params, headers) ++
          Tesla.OpenAPI.CookieParams.to_headers(@cookie_params, cookies)
      end
    end
  end

  defp params(names, module) do
    Enum.map(names, &param(&1, module))
  end

  defp param(name, module) do
    quote do
      unquote(module).new!(unquote(name))
    end
  end
end

defmodule Tesla.Bench.OpenAPIParameterCollections do
  @moduledoc false

  alias Tesla.Env

  defmodule Client do
    @moduledoc false

    defstruct [:client]

    def new do
      middleware = [
        {Tesla.Middleware.BaseUrl, base_url: "https://api.example.com"},
        {Tesla.Middleware.PathParams, mode: :modern},
        {Tesla.Middleware.Query, mode: :modern}
      ]

      %__MODULE__{client: Tesla.client(middleware, adapter())}
    end

    defp adapter do
      fn %Env{} = env ->
        {:ok, %{env | url: Tesla.build_url(env), query: [], status: 200, body: :ok}}
      end
    end
  end

  defmodule Operation3 do
    use Tesla.Bench.OpenAPIParameterCollections.OperationTemplate, size: 3
  end

  defmodule Operation10 do
    use Tesla.Bench.OpenAPIParameterCollections.OperationTemplate, size: 10
  end

  defmodule Operation25 do
    use Tesla.Bench.OpenAPIParameterCollections.OperationTemplate, size: 25
  end

  defmodule Operation100 do
    use Tesla.Bench.OpenAPIParameterCollections.OperationTemplate, size: 100
  end

  def inputs(sizes) do
    client = Client.new()

    Map.new(input_specs(sizes), fn {label, size, known_count, extra_count} ->
      operation_module = operation_module(size)

      operation =
        struct(operation_module,
          path: values(size, 0),
          query: values(known_count, extra_count),
          headers: values(known_count, extra_count),
          cookies: values(known_count, extra_count)
        )

      {label, %{client: client, operation: operation}}
    end)
  end

  def call(%{client: client, operation: operation}) do
    module = operation.__struct__

    module.handle_operation(client, operation)
  end

  defp operation_module(3) do
    Operation3
  end

  defp operation_module(10) do
    Operation10
  end

  defp operation_module(25) do
    Operation25
  end

  defp operation_module(100) do
    Operation100
  end

  defp input_specs(sizes) do
    for size <- sizes,
        {profile, known_count, extra_count} <- value_profiles(size) do
      {"#{size} #{profile}", size, known_count, extra_count}
    end
  end

  defp value_profiles(size) do
    sparse_count = min(size, 3)

    [
      {"dense known", size, 0},
      {"dense plus extras", size, size},
      {"sparse known", sparse_count, 0},
      {"sparse plus extras", sparse_count, size},
      {"extras only", 0, size}
    ]
  end

  defp values(known_count, extra_count) do
    known = Map.new(indexes(known_count), &{"param#{&1}", &1})
    extra = Map.new(indexes(extra_count), &{"extra#{&1}", &1})

    Map.merge(extra, known)
  end

  defp indexes(0) do
    []
  end

  defp indexes(size) do
    1..size
  end
end

alias Tesla.Bench.OpenAPIParameterCollections

sizes = [3, 10, 25, 100]

Benchee.run(
  %{
    "current middleware" => &OpenAPIParameterCollections.call/1
  },
  time: 0.5,
  warmup: 0.2,
  memory_time: 0.1,
  inputs: OpenAPIParameterCollections.inputs(sizes),
  title: "OpenAPI generated operation: current middleware stack",
  print: [
    benchmarking: false,
    configuration: false,
    fast_warning: false
  ]
)
