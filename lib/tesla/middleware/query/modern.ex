defmodule Tesla.Middleware.Query.Modern do
  @moduledoc false

  alias Tesla.Env
  alias Tesla.Param
  alias Tesla.QueryParam
  alias Tesla.QueryParams
  alias Tesla.QueryString

  def call(%Env{} = env, next) do
    env
    |> build_url()
    |> Tesla.run(next)
  end

  defp build_url(%Env{query: nil} = env) do
    %{env | query: []}
  end

  defp build_url(%Env{query: []} = env) do
    env
  end

  defp build_url(%Env{query: %QueryString{}} = env) do
    env
  end

  defp build_url(%Env{query: values} = env) when is_map(values) do
    case map_size(values) do
      0 ->
        %{env | query: []}

      _size ->
        build_url_with_query_params(env, values)
    end
  end

  defp build_url(%Env{query: values}) do
    raise ArgumentError,
          "expected query to be a map of request values in modern mode; got #{inspect(values)}"
  end

  defp build_url_with_query_params(%Env{private: private} = env, values) do
    case QueryParams.fetch_private(private) do
      {:ok, query_params} ->
        {parts, extra_values} = serialize_params(query_params, values)

        %{env | url: append_query(env.url, parts), query: extra_values}

      :error ->
        env
    end
  end

  defp append_query(url, []) do
    url
  end

  defp append_query(url, parts) do
    url = url || ""
    separator = query_separator(url)

    url <> separator <> Enum.join(parts, "&")
  end

  defp query_separator(url) do
    case String.contains?(url, "?") do
      true -> "&"
      false -> "?"
    end
  end

  defp serialize_params(query_params, values) do
    {parts, extra_values} =
      query_params
      |> QueryParams.definitions()
      |> Enum.reduce({[], values}, &serialize_defined_param/2)

    {Enum.reverse(parts), normalize_extra_values(extra_values)}
  end

  defp serialize_defined_param(%QueryParam{name: name} = param, {parts, values}) do
    case Map.fetch(values, name) do
      {:ok, value} ->
        param_parts = serialize_param(param, value)

        {Enum.reverse(param_parts, parts), Map.delete(values, name)}

      :error ->
        {parts, values}
    end
  end

  defp normalize_extra_values(values) when map_size(values) == 0 do
    []
  end

  defp normalize_extra_values(values), do: values

  defp serialize_param(%QueryParam{style: :form} = param, value) do
    value
    |> value_type()
    |> serialize_form(param)
  end

  defp serialize_param(%QueryParam{style: :space_delimited} = param, value) do
    value
    |> value_type()
    |> serialize_space_delimited(param)
  end

  defp serialize_param(%QueryParam{style: :pipe_delimited} = param, value) do
    value
    |> value_type()
    |> serialize_pipe_delimited(param)
  end

  defp serialize_param(%QueryParam{style: :deep_object} = param, value) do
    value
    |> value_type()
    |> serialize_deep_object(param)
  end

  defp serialize_form(:undefined, param) do
    [serialize_empty(param)]
  end

  defp serialize_form({:primitive, value}, param) do
    [serialize_named_value(param, value)]
  end

  defp serialize_form({:array, []}, _param) do
    []
  end

  defp serialize_form({:array, items}, %QueryParam{explode: true} = param) do
    Enum.map(items, &serialize_named_value(param, &1))
  end

  defp serialize_form({:array, items}, %QueryParam{explode: false} = param) do
    [QueryParam.encode_name(param.name) <> "=" <> join_encoded_values(items, ",", param)]
  end

  defp serialize_form({:object, []}, _param) do
    []
  end

  defp serialize_form({:object, pairs}, %QueryParam{explode: true} = param) do
    Enum.map(pairs, &serialize_query_pair(&1, param))
  end

  defp serialize_form({:object, pairs}, %QueryParam{explode: false} = param) do
    [
      QueryParam.encode_name(param.name) <>
        "=" <>
        (pairs
         |> Param.flatten_pairs()
         |> join_encoded_values(",", param))
    ]
  end

  defp serialize_space_delimited(_classified, %QueryParam{explode: true} = param) do
    raise ArgumentError,
          ":space_delimited style does not define explode: true serialization for parameter #{inspect(param.name)}"
  end

  defp serialize_space_delimited({:array, []}, _param) do
    []
  end

  defp serialize_space_delimited({:array, items}, param) do
    [QueryParam.encode_name(param.name) <> "=" <> join_encoded_values(items, "%20", param)]
  end

  defp serialize_space_delimited({:object, []}, _param) do
    []
  end

  defp serialize_space_delimited({:object, pairs}, param) do
    [
      QueryParam.encode_name(param.name) <>
        "=" <>
        (pairs
         |> Param.flatten_pairs()
         |> join_encoded_values("%20", param))
    ]
  end

  defp serialize_space_delimited(_classified, param) do
    raise ArgumentError,
          ":space_delimited style requires an array or object value for parameter #{inspect(param.name)}"
  end

  defp serialize_pipe_delimited(_classified, %QueryParam{explode: true} = param) do
    raise ArgumentError,
          ":pipe_delimited style does not define explode: true serialization for parameter #{inspect(param.name)}"
  end

  defp serialize_pipe_delimited({:array, []}, _param) do
    []
  end

  defp serialize_pipe_delimited({:array, items}, param) do
    [QueryParam.encode_name(param.name) <> "=" <> join_encoded_values(items, "%7C", param)]
  end

  defp serialize_pipe_delimited({:object, []}, _param) do
    []
  end

  defp serialize_pipe_delimited({:object, pairs}, param) do
    [
      QueryParam.encode_name(param.name) <>
        "=" <>
        (pairs
         |> Param.flatten_pairs()
         |> join_encoded_values("%7C", param))
    ]
  end

  defp serialize_pipe_delimited(_classified, param) do
    raise ArgumentError,
          ":pipe_delimited style requires an array or object value for parameter #{inspect(param.name)}"
  end

  defp serialize_deep_object({:object, []}, _param) do
    []
  end

  defp serialize_deep_object({:object, pairs}, param) do
    Enum.map(pairs, &serialize_deep_object_pair(&1, param))
  end

  defp serialize_deep_object(_classified, param) do
    raise ArgumentError,
          ":deep_object style requires an object value for parameter #{inspect(param.name)}"
  end

  defp serialize_empty(param) do
    QueryParam.encode_name(param.name) <> "="
  end

  defp serialize_named_value(param, value) do
    QueryParam.encode_name(param.name) <> "=" <> QueryParam.encode_value(param, value)
  end

  defp serialize_query_pair({key, value}, param) do
    QueryParam.encode_name(key) <> "=" <> QueryParam.encode_value(param, value)
  end

  defp serialize_deep_object_pair({key, value}, param) do
    QueryParam.encode_name(param.name) <>
      "%5B" <> QueryParam.encode_name(key) <> "%5D=" <> QueryParam.encode_value(param, value)
  end

  defp join_encoded_values(values, separator, param) do
    Enum.map_join(values, separator, &QueryParam.encode_value(param, &1))
  end

  defp value_type(value) do
    Param.value_type(value)
  end
end
