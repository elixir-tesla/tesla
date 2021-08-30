defmodule Tesla.OpenApi do
  defmacro __using__(opts \\ []) do
    file = Keyword.fetch!(opts, :spec)
    spec = Jason.decode!(File.read!(file))

    [
      quote do
        @external_resource unquote(file)
      end,
      gen_schemas(spec),
      gen_operations(spec),
      gen_new(spec)
    ]
    |> tap(&print/1)
  end

  defp print(x), do: x |> Macro.to_string() |> Code.format_string!() |> IO.puts()

  def gen_schemas(spec) do
    for {name, definition} <- spec["definitions"] do
      props =
        case definition do
          %{"type" => "object", "properties" => properties} ->
            properties

          %{"type" => "object", "allOf" => all_of} ->
            all_of
            |> Enum.flat_map(fn
              %{"properties" => properties} -> properties
              _ -> []
            end)
        end

      props_def = Enum.map(props, fn {key, _} -> {String.to_atom(key), nil} end)

      props_build =
        Enum.map(props, fn {key, _} ->
          {String.to_atom(key), quote(do: body[unquote(key)])}
        end)

      quote do
        defmodule unquote({:__aliases__, [alias: false], [String.to_atom(name)]}) do
          defstruct unquote(props_def)

          def decode(body) do
            %__MODULE__{unquote_splicing(props_build)}
          end
        end
      end
    end
  end

  def gen_operations(spec) do
    for {path, methods} <- spec["paths"] do
      for {method, operation} <- methods do
        name = String.to_atom(Macro.underscore(operation["operationId"]))
        meth = String.to_atom(method)
        parameters = Map.get(operation, "parameters", [])

        params =
          parameters
          |> Enum.filter(&match?(%{"in" => "path"}, &1))
          |> Enum.map(fn %{"name" => name} ->
            var = String.to_atom(name)
            Macro.var(var, __MODULE__)
          end)

        params = [quote(do: client \\ new()) | params]

        parts =
          ~r/\{([^}]+?)\}/
          |> Regex.split(path, include_captures: true, trim: true)
          |> Enum.map(fn x ->
            case Regex.run(~r/\{([^}]+?)\}/, x) do
              [_, name] ->
                {:<<>>, [], [part]} =
                  quote(do: "#{unquote(Macro.var(String.to_atom(name), __MODULE__))}")

                part

              _ ->
                x
            end
          end)

        path = {:<<>>, [], parts}

        responses = Map.get(operation, "responses", %{})
        {default, responses} = Map.pop(responses, "default")

        responses =
          Enum.map(responses, fn
            {code,
             %{
               "schema" => %{
                 "type" => "array",
                 "items" => %{"$ref" => "#/definitions/" <> schema}
               }
             }} ->
              body = Macro.var(:body, __MODULE__)
              schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}

              match =
                quote(
                  do:
                    {:ok,
                     %{
                       status: unquote(String.to_integer(code)),
                       body: unquote(body)
                     }}
                    when is_list(body)
                )

              resp =
                {:ok,
                 quote(
                   do:
                     Enum.map(body, fn item ->
                       unquote(schema).decode(item)
                     end)
                 )}

              {:->, [], [[match], resp]}

            {code, %{"schema" => %{"$ref" => "#/definitions/" <> schema}}} ->
              body = Macro.var(:body, __MODULE__)
              schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}

              match =
                quote(
                  do:
                    {:ok,
                     %{
                       status: unquote(String.to_integer(code)),
                       body: unquote(body)
                     }}
                )

              resp = {:ok, quote(do: unquote(schema).decode(unquote(body)))}
              {:->, [], [[match], resp]}

            {code, _} ->
              match = quote(do: {:ok, %{status: unquote(String.to_integer(code))}})
              resp = :ok
              {:->, [], [[match], resp]}
          end)

        error = {:->, [], [[quote(do: {:error, error})], quote(do: {:error, error})]}

        responses =
          case default do
            %{"schema" => %{"$ref" => "#/definitions/" <> schema}} ->
              body = Macro.var(:body, __MODULE__)
              schema = {:__aliases__, [alias: false], [String.to_atom(schema)]}

              match =
                quote(
                  do:
                    {:ok,
                     %{
                       body: unquote(body)
                     }}
                )

              resp = {:error, quote(do: unquote(schema).decode(unquote(body)))}
              clause = {:->, [], [[match], resp]}
              responses ++ [clause, error]

            _ ->
              responses ++ [error]
          end

        quote do
          def unquote(name)(unquote_splicing(params)) do
            case Tesla.unquote(meth)(client, unquote(path)) do
              unquote(responses)
            end
          end
        end
      end
    end
  end

  defp gen_new(spec) do
    middleware =
      Enum.flat_map(spec["consumes"], fn
        "application/json" -> [Tesla.Middleware.JSON]
        _ -> []
      end)

    quote do
      @middleware unquote(middleware)
      def new(opts \\ []) do
        middleware = Keyword.get(opts, :middleware, [])
        adapter = Keyword.get(opts, :adapter)
        Tesla.client(@middleware ++ middleware, adapter)
      end
    end
  end
end
