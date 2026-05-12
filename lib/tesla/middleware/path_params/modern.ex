defmodule Tesla.Middleware.PathParams.Modern do
  @moduledoc false

  alias Tesla.Env
  alias Tesla.Param
  alias Tesla.PathParam
  alias Tesla.PathTemplate

  def call(%Env{opts: opts} = env, next) do
    url = build_url(env, opts[:path_params])
    Tesla.run(%{env | url: url}, next)
  end

  defp build_url(%Env{} = env, nil) do
    env.url
  end

  defp build_url(%Env{} = env, params) when is_list(params) do
    case PathTemplate.fetch_private(env.private) do
      {:ok, template} ->
        build_url(env.url, template, params)

      :error ->
        build_url(env.url, params)
    end
  end

  defp build_url(%Env{} = env, params) do
    build_url(env.url, params)
  end

  defp build_url(url, params) when is_list(params) do
    params = path_params_by_name!(params)

    Regex.replace(~r/[{]([^{}]+)[}]/, url, &replace_placeholder(params, &1, &2))
  end

  defp build_url(url, _params) do
    url
  end

  defp build_url(url, template, params) do
    params = path_params_by_name!(params)

    case PathTemplate.render(template, url, params, &render_template_expression/3) do
      {:ok, rendered_url} ->
        rendered_url

      {:error, :path_mismatch} ->
        Regex.replace(~r/[{]([^{}]+)[}]/, url, &replace_placeholder(params, &1, &2))
    end
  end

  defp render_template_expression(name, expression, params) do
    params
    |> Map.get(name)
    |> replace_param(expression)
  end

  defp path_params_by_name!(params) do
    Enum.reduce(params, %{}, &put_path_param_by_name!/2)
  end

  defp put_path_param_by_name!(%PathParam{name: name} = param, params) do
    case Map.has_key?(params, name) do
      true ->
        raise ArgumentError, "duplicate path parameter #{inspect(name)} in modern mode"

      false ->
        Map.put(params, name, param)
    end
  end

  defp put_path_param_by_name!(value, _params) do
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
