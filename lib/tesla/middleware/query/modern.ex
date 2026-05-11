defmodule Tesla.Middleware.Query.Modern do
  @moduledoc false

  alias Tesla.QueryParam

  def call(env, next) do
    env
    |> build_url()
    |> Tesla.run(next)
  end

  defp build_url(%{query: nil} = env) do
    %{env | query: []}
  end

  defp build_url(%{query: params} = env) when is_list(params) do
    parts = Enum.flat_map(params, &serialize_param/1)

    %{env | url: append_query(env.url, parts), query: []}
  end

  defp build_url(%{query: params}) do
    raise ArgumentError,
          "expected query to be a list of #{inspect(QueryParam)} structs in modern mode; got #{inspect(params)}"
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

  defp serialize_param(%QueryParam{style: :form} = param) do
    param
    |> classify_param()
    |> serialize_form(param)
  end

  defp serialize_param(%QueryParam{style: :space_delimited} = param) do
    param
    |> classify_param()
    |> serialize_space_delimited(param)
  end

  defp serialize_param(%QueryParam{style: :pipe_delimited} = param) do
    param
    |> classify_param()
    |> serialize_pipe_delimited(param)
  end

  defp serialize_param(%QueryParam{style: :deep_object} = param) do
    param
    |> classify_param()
    |> serialize_deep_object(param)
  end

  defp serialize_param(param) do
    raise ArgumentError,
          "expected query to be a list of #{inspect(QueryParam)} structs in modern mode; got #{inspect(param)}"
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
         |> flatten_pairs()
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
         |> flatten_pairs()
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
         |> flatten_pairs()
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

  defp flatten_pairs(pairs) do
    Enum.flat_map(pairs, &pair_values/1)
  end

  defp pair_values({key, value}) do
    [key, value]
  end

  defp join_encoded_values(values, separator, param) do
    Enum.map_join(values, separator, &QueryParam.encode_value(param, &1))
  end

  defp classify_param(%QueryParam{value: value}) do
    classify_value(value)
  end

  defp classify_value(nil) do
    :undefined
  end

  defp classify_value(value) when is_struct(value) do
    classify_value(Map.from_struct(value))
  end

  defp classify_value(value) when is_map(value) do
    {:object, value |> Map.to_list() |> Enum.map(&stringify_pair/1)}
  end

  defp classify_value([]) do
    {:array, []}
  end

  defp classify_value(value) when is_list(value) do
    case Enum.all?(value, &object_pair?/1) do
      true -> {:object, Enum.map(value, &stringify_pair/1)}
      false -> {:array, value}
    end
  end

  defp classify_value(value) do
    {:primitive, value}
  end

  defp stringify_pair({key, value}) do
    {to_string(key), value}
  end

  defp object_pair?({key, _value}) when is_atom(key) or is_binary(key) do
    true
  end

  defp object_pair?(_value) do
    false
  end
end
