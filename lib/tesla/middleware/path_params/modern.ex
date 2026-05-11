defmodule Tesla.Middleware.PathParams.Modern do
  @moduledoc false

  alias Tesla.Param
  alias Tesla.PathParam

  def call(env, next) do
    url = build_url(env.url, env.opts[:path_params])
    Tesla.run(%{env | url: url}, next)
  end

  defp build_url(url, nil) do
    url
  end

  defp build_url(url, params) when is_list(params) do
    params = index_params!(params)

    Regex.replace(~r/[{]([^{}]+)[}]/, url, &replace_placeholder(params, &1, &2))
  end

  defp build_url(url, _params) do
    url
  end

  defp index_params!(params) do
    Enum.reduce(params, %{}, &index_param!/2)
  end

  defp index_param!(%PathParam{name: name} = param, params) do
    case Map.has_key?(params, name) do
      true ->
        raise ArgumentError, "duplicate path parameter #{inspect(name)} in modern mode"

      false ->
        Map.put(params, name, param)
    end
  end

  defp index_param!(value, _params) do
    raise ArgumentError,
          "expected path_params to be a list of #{inspect(PathParam)} structs in modern mode; got #{inspect(value)}"
  end

  defp replace_placeholder(params, match, name) when is_map(params) do
    replace_param(Map.get(params, name), match)
  end

  defp replace_param(%PathParam{value: nil}, match) do
    match
  end

  defp replace_param(%PathParam{} = param, _match) do
    serialize_value(param)
  end

  defp replace_param(nil, match) do
    match
  end

  defp serialize_undefined(:simple, _param) do
    ""
  end

  defp serialize_undefined(:matrix, param) do
    ";" <> PathParam.encode_value(param, param.name)
  end

  defp serialize_undefined(:label, _param) do
    "."
  end

  defp serialize_value(%PathParam{style: :simple} = param) do
    param
    |> value_type()
    |> serialize_simple(param)
  end

  defp serialize_value(%PathParam{style: :matrix} = param) do
    param
    |> value_type()
    |> serialize_matrix(param)
  end

  defp serialize_value(%PathParam{style: :label} = param) do
    param
    |> value_type()
    |> serialize_label(param)
  end

  defp serialize_simple({:primitive, value}, param) do
    PathParam.encode_value(param, value)
  end

  defp serialize_simple({:array, []}, param) do
    serialize_undefined(:simple, param)
  end

  defp serialize_simple({:array, items}, param) do
    join_encoded_values(items, ",", param)
  end

  defp serialize_simple({:object, []}, param) do
    serialize_undefined(:simple, param)
  end

  defp serialize_simple({:object, pairs}, %PathParam{explode: true} = param) do
    join_encoded_pairs(pairs, ",", param)
  end

  defp serialize_simple({:object, pairs}, %PathParam{explode: false} = param) do
    pairs
    |> Param.flatten_pairs()
    |> join_encoded_values(",", param)
  end

  defp serialize_matrix({:primitive, value}, param) do
    ";" <>
      PathParam.encode_value(param, param.name) <> "=" <> PathParam.encode_value(param, value)
  end

  defp serialize_matrix({:array, []}, param) do
    serialize_undefined(:matrix, param)
  end

  defp serialize_matrix({:array, items}, %PathParam{explode: true} = param) do
    Enum.map_join(items, "", &serialize_matrix_array_item(&1, param))
  end

  defp serialize_matrix({:array, items}, %PathParam{explode: false} = param) do
    ";" <>
      PathParam.encode_value(param, param.name) <>
      "=" <> join_encoded_values(items, ",", param)
  end

  defp serialize_matrix({:object, []}, param) do
    serialize_undefined(:matrix, param)
  end

  defp serialize_matrix({:object, pairs}, %PathParam{explode: true} = param) do
    Enum.map_join(pairs, "", &serialize_matrix_pair(&1, param))
  end

  defp serialize_matrix({:object, pairs}, %PathParam{explode: false} = param) do
    ";" <>
      PathParam.encode_value(param, param.name) <>
      "=" <>
      (pairs
       |> Param.flatten_pairs()
       |> join_encoded_values(",", param))
  end

  defp serialize_label({:primitive, value}, param) do
    "." <> PathParam.encode_value(param, value)
  end

  defp serialize_label({:array, []}, param) do
    serialize_undefined(:label, param)
  end

  defp serialize_label({:array, items}, %PathParam{explode: true} = param) do
    "." <> join_encoded_values(items, ".", param)
  end

  defp serialize_label({:array, items}, %PathParam{explode: false} = param) do
    "." <> join_encoded_values(items, ",", param)
  end

  defp serialize_label({:object, []}, param) do
    serialize_undefined(:label, param)
  end

  defp serialize_label({:object, pairs}, %PathParam{explode: true} = param) do
    "." <> join_encoded_pairs(pairs, ".", param)
  end

  defp serialize_label({:object, pairs}, %PathParam{explode: false} = param) do
    "." <>
      (pairs
       |> Param.flatten_pairs()
       |> join_encoded_values(",", param))
  end

  defp serialize_matrix_array_item(value, param) do
    ";" <>
      PathParam.encode_value(param, param.name) <> "=" <> PathParam.encode_value(param, value)
  end

  defp serialize_matrix_pair(pair, param) do
    ";" <> serialize_key_value_pair(pair, param)
  end

  defp join_encoded_pairs(pairs, separator, param) do
    Enum.map_join(pairs, separator, &serialize_key_value_pair(&1, param))
  end

  defp serialize_key_value_pair({key, value}, param) do
    "#{PathParam.encode_value(param, key)}=#{PathParam.encode_value(param, value)}"
  end

  defp join_encoded_values(values, separator, param) do
    Enum.map_join(values, separator, &PathParam.encode_value(param, &1))
  end

  defp value_type(%PathParam{value: value}) do
    Param.value_type(value)
  end
end
