defmodule Tesla.AdapterCase.Echo do
  @moduledoc """
  Reads back what the httparrot echo endpoints report about a request.
  """

  def request_body(response_body) do
    response_body |> decode() |> Map.fetch!("data")
  end

  def request_header(response_body, name) do
    response_body |> decode() |> get_in(["headers", name])
  end

  defp decode(response_body) do
    response_body |> to_string() |> Jason.decode!()
  end
end
