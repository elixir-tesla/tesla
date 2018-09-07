defmodule Tesla.Dialyzer do
  @moduledoc """
  This module's purpose is to catch typing errors.
  It is compiled in test env and can be validated with

  MIX_ENV=test mix dialyzer
  """

  def test_client do
    middleware = [
      {Tesla.Middleware.BaseUrl, "url"},
      {Tesla.Middleware.Headers, []},
      Tesla.Middleware.JSON
    ]

    Tesla.client(middleware)
  end
end
