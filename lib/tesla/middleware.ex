defmodule Tesla.Middleware do
  alias Tesla.Env

  @callback call(env :: Env.t, next :: Env.stack, options :: any())
    :: Env.t | {:ok, Env.t} | {:error, any()}
end
