defmodule Tesla.Middleware.PathParams.Modern do
  @moduledoc false

  alias Tesla.Env
  alias Tesla.Param
  alias Tesla.OpenAPI.PathParam
  alias Tesla.OpenAPI.PathParams
  alias Tesla.OpenAPI.PathTemplate

  def call(%Env{opts: opts} = env, next) do
    url = build_url(env, opts[:path_params])
    Tesla.run(%{env | url: url}, next)
  end

  defp build_url(%Env{} = env, nil) do
    env.url
  end

  defp build_url(%Env{} = env, values) when is_map(values) do
    case PathParams.fetch_private(env.private) do
      {:ok, path_params} ->
        build_url(env, path_params, values)

      :error ->
        raise ArgumentError,
              "expected #{inspect(PathParams)} private data when using path_params in modern mode"
    end
  end

  defp build_url(%Env{} = _env, values) do
    raise ArgumentError,
          "expected path_params to be a map of request values in modern mode; got #{inspect(values)}"
  end

  defp build_url(%Env{} = env, path_params, values) do
    case PathTemplate.fetch_private(env.private) do
      {:ok, template} ->
        build_url(env.url, template, path_params, values)

      :error ->
        build_url(env.url, path_params, values)
    end
  end

  defp build_url(url, path_params, values) do
    Regex.replace(~r/[{]([^{}]+)[}]/, url, &replace_placeholder(path_params, values, &1, &2))
  end

  defp build_url(url, template, path_params, values) do
    render_context = {path_params, values}

    case PathTemplate.render(template, url, render_context, &render_template_expression/3) do
      {:ok, rendered_url} ->
        rendered_url

      {:error, :path_mismatch} ->
        build_url(url, path_params, values)
    end
  end

  defp render_template_expression(name, _expression, {path_params, values}) do
    replace_param(path_params, values, name)
  end

  defp replace_placeholder(path_params, values, _match, name) do
    replace_param(path_params, values, name)
  end

  defp replace_param(path_params, values, name) do
    case fetch_param(path_params, values, name) do
      {:ok, _path_param, nil} ->
        raise_missing!(name)

      {:ok, path_param, value} ->
        serialize_value(path_param, value)

      :error ->
        raise_missing!(name)
    end
  end

  defp fetch_param(path_params, values, name) do
    case PathParams.fetch(path_params, name) do
      {:ok, path_param} ->
        fetch_value(path_param, values, name)

      :error ->
        :error
    end
  end

  defp fetch_value(path_param, values, name) do
    case Map.fetch(values, name) do
      {:ok, value} ->
        {:ok, path_param, value}

      :error ->
        :error
    end
  end

  defp raise_missing!(name) do
    raise ArgumentError, "missing value for path parameter #{inspect(name)}"
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

  defp serialize_value(%PathParam{style: :simple} = param, value) do
    value
    |> Param.value_type()
    |> serialize_simple(param)
  end

  defp serialize_value(%PathParam{style: :matrix} = param, value) do
    value
    |> Param.value_type()
    |> serialize_matrix(param)
  end

  defp serialize_value(%PathParam{style: :label} = param, value) do
    value
    |> Param.value_type()
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
end
