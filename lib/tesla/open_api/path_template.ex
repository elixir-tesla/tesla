defmodule Tesla.OpenAPI.PathTemplate do
  @moduledoc """
  A precompiled OpenAPI Path Templating path.

  `Tesla.OpenAPI.PathTemplate` keeps the request path as a string while carrying a
  compiled representation that `Tesla.Middleware.PathParams` can use to avoid
  parsing the same path template on every request.

      alias Tesla.OpenAPI.PathTemplate

      template = PathTemplate.new!("/items/{id}")
      path_params = Tesla.OpenAPI.PathParams.new!([Tesla.OpenAPI.PathParam.new!("id")])

      private =
        %{}
        |> PathTemplate.put_private(template)
        |> Tesla.OpenAPI.PathParams.put_private(path_params)

      Tesla.get(client, template.path,
        opts: [path_params: %{"id" => id}],
        private: private
      )

  Path templates follow the [OpenAPI Path Templating][oas-path-templating]
  syntax for `{name}` template expressions.

  [oas-path-templating]: https://spec.openapis.org/oas/latest.html#path-templating
  """

  @derive {Inspect, except: [:parts]}
  @enforce_keys [:path, :parts]
  defstruct [:path, :parts]

  @typep expression_part ::
           {:expr, name :: String.t(), expression :: String.t()}
  @typep part :: String.t() | expression_part()
  @typep renderer :: (String.t(), String.t(), term() -> iodata())
  @opaque t :: %__MODULE__{
            path: String.t(),
            parts: [part()]
          }

  @private_key :tesla_path_template

  @spec new!(String.t()) :: t()
  def new!(path) when is_binary(path) do
    parts =
      path
      |> compile()
      |> validate_unique_names!()

    %__MODULE__{path: validate_path!(path), parts: parts}
  end

  @doc """
  Adds the compiled path template to Tesla request private data.

      template = Tesla.OpenAPI.PathTemplate.new!("/items/{id}")
      path_params = Tesla.OpenAPI.PathParams.new!([Tesla.OpenAPI.PathParam.new!("id")])

      private =
        %{}
        |> Tesla.OpenAPI.PathTemplate.put_private(template)
        |> Tesla.OpenAPI.PathParams.put_private(path_params)

      Tesla.get(client, template.path,
        opts: [path_params: %{"id" => id}],
        private: private
      )
  """
  @spec put_private(t()) :: Tesla.Env.private()
  def put_private(%__MODULE__{} = template) do
    put_private(%{}, template)
  end

  @spec put_private(Tesla.Env.private(), t()) :: Tesla.Env.private()
  def put_private(private, %__MODULE__{} = template) when is_map(private) do
    Map.put(private, @private_key, template)
  end

  @doc false
  @spec fetch_private(Tesla.Env.private()) :: {:ok, t()} | :error
  def fetch_private(private) when is_map(private) do
    case Map.fetch(private, @private_key) do
      {:ok, %__MODULE__{} = template} ->
        {:ok, template}

      {:ok, _value} ->
        :error

      :error ->
        :error
    end
  end

  @doc false
  @spec render(t(), String.t(), term(), renderer()) ::
          {:ok, String.t()} | {:error, :path_mismatch}
  def render(%__MODULE__{} = template, path, params, renderer)
      when is_binary(path) and is_function(renderer, 3) do
    case template.path == path do
      true ->
        rendered_path =
          template.parts
          |> render_parts(params, renderer, [])
          |> IO.iodata_to_binary()

        {:ok, rendered_path}

      false ->
        {:error, :path_mismatch}
    end
  end

  defp render_parts([], _params, _renderer, parts) do
    :lists.reverse(parts)
  end

  defp render_parts([{:expr, name, expression} | rest], params, renderer, parts) do
    part = renderer.(name, expression, params)

    render_parts(rest, params, renderer, [part | parts])
  end

  defp render_parts([literal | rest], params, renderer, parts) do
    render_parts(rest, params, renderer, [literal | parts])
  end

  defp validate_path!("") do
    raise ArgumentError, "expected path template path to start with /"
  end

  defp validate_path!("/" <> _path = path) do
    path
  end

  defp validate_path!(_path) do
    raise ArgumentError, "expected path template path to start with /"
  end

  defp compile(path) do
    path
    |> compile_parts(0, [])
    |> :lists.reverse()
  end

  defp compile_parts(path, offset, parts) do
    case match_template_delimiter(path, offset) do
      :nomatch ->
        add_literal!(parts, binary_part(path, offset, byte_size(path) - offset))

      {index, ?}} ->
        raise ArgumentError,
              "unexpected closing } in path template #{inspect(path)} at byte #{index}"

      {open_index, ?{} ->
        compile_template_expression(path, open_index, parts, offset)
    end
  end

  defp compile_template_expression(path, open_index, parts, offset) do
    close_offset = open_index + 1

    case match_template_delimiter(path, close_offset) do
      :nomatch ->
        raise ArgumentError, "unclosed template expression in path template #{inspect(path)}"

      {_index, ?{} ->
        raise ArgumentError,
              "nested template expressions are not valid in path template #{inspect(path)}"

      {close_index, ?}} ->
        compile_closed_template_expression(path, open_index, close_index, parts, offset)
    end
  end

  defp compile_closed_template_expression(path, open_index, close_index, _parts, _offset)
       when close_index == open_index + 1 do
    raise ArgumentError, "empty template expression in path template #{inspect(path)}"
  end

  defp compile_closed_template_expression(path, open_index, close_index, parts, offset) do
    name_length = close_index - open_index - 1
    name = binary_part(path, open_index + 1, name_length)
    expression = binary_part(path, open_index, close_index - open_index + 1)
    literal = binary_part(path, offset, open_index - offset)
    parts = [{:expr, name, expression} | add_literal!(parts, literal)]

    compile_parts(path, close_index + 1, parts)
  end

  defp match_template_delimiter(path, offset) when offset < byte_size(path) do
    size = byte_size(path)

    case :binary.match(path, ["{", "}"], scope: {offset, size - offset}) do
      {index, 1} -> {index, :binary.at(path, index)}
      :nomatch -> :nomatch
    end
  end

  defp match_template_delimiter(_path, _offset) do
    :nomatch
  end

  defp add_literal!(parts, "") do
    parts
  end

  defp add_literal!(parts, literal) do
    case :binary.match(literal, ["?", "#"]) do
      :nomatch ->
        [literal | parts]

      _match ->
        raise ArgumentError, "expected path template path not to include query or fragment"
    end
  end

  defp validate_unique_names!(parts) do
    {_names, duplicates} =
      Enum.reduce(parts, {MapSet.new(), MapSet.new()}, &track_name/2)

    raise_duplicate_names!(duplicates)

    parts
  end

  defp track_name({:expr, name, _expression}, {names, duplicates}) do
    case MapSet.member?(names, name) do
      true ->
        {names, MapSet.put(duplicates, name)}

      false ->
        {MapSet.put(names, name), duplicates}
    end
  end

  defp track_name(_literal, acc) do
    acc
  end

  defp raise_duplicate_names!(duplicates) do
    names =
      duplicates
      |> MapSet.to_list()
      |> Enum.sort()

    case names do
      [] ->
        :ok

      names ->
        raise ArgumentError,
              "duplicate template expressions #{inspect(names)} in path template"
    end
  end
end
