# Migrate away from v1 Macro

We encourage users to contribute to this guide to help others migrate away from
the `v1` macro syntax. Every case is different, so we can't provide a
one-size-fits-all solution, but we can provide a guide to help you migrate your
codebase.
Please share your learnings and suggestions in the [Migrating away from v1 Macro GitHub Discussion](https://github.com/elixir-tesla/tesla/discussions/732).

1. Find all the modules that use `use Tesla`

   ```elixir
   defmodule MyApp.MyTeslaClient do
     use Tesla # <- this line
   end
   ```

2. Remove `use Tesla`

   ```diff
    - defmodule MyApp.MyTeslaClient do
    -   use Tesla
    - end
    + defmodule MyApp.MyTeslaClient do
    + end
   ```

3. Find all the `plug` macro calls:

   ```elixir
   defmodule MyApp.MyTeslaClient do
     plug Tesla.Middleware.KeepRequest # <- this line
     plug Tesla.Middleware.PathParams # <- this line
     plug Tesla.Middleware.JSON # <- this line
   end
   ```

4. Move all the `plug` macro calls to a function that returns the middleware.

   ```diff
   defmodule MyApp.MyTeslaClient do
   - plug Tesla.Middleware.KeepRequest
   - plug Tesla.Middleware.PathParams
   - plug Tesla.Middleware.JSON
   +
   + def middleware do
   +   [Tesla.Middleware.KeepRequest, Tesla.Middleware.PathParams, Tesla.Middleware.JSON]
   + end
   end
   ```

5. Find all the `adapter` macro calls:

   ```elixir
   defmodule MyApp.MyTeslaClient do
     adapter Tesla.Adapter.Hackney # <- this line
     adapter fn env -> # <- or this line
     end
   end
   ```

6. Create a `adapter/0` function that returns the adapter to use for that given
   module, or however you prefer to configure the adapter used. Please refer to
   the [Adapter Explanation](../explanations/3.adapter.md) documentation for more
   information.

   > #### Context Matters {: .warning}
   >
   > **This step is probably the most important one.** The context in which the
   > adapter is used matters a lot. Please be careful with this step, and test
   > your changes thoroughly.

   ```diff
   defmodule MyApp.MyTeslaClient do
   - adapter Tesla.Adapter.Hackney
   + defp adapter do
   +   # if the value is `nil`, the default global Tesla adapter will be used
   +   # which is the existing behavior.
   +   :my_app
   +   |> Application.get_env(__MODULE__, [])
   +   |> Keyword.get(:adapter)
   + end
   end
   ```

7. Create a `client/0` function that returns a `Tesla.Client` struct with the
   middleware and adapter. Please refer to the [Client Explanation](../explanations/0.client.md)
   documentation for more information.

   ```elixir
   defmodule MyApp.MyTeslaClient do
     def client do
       Tesla.client(middleware(), adapter())
     end

     defp middleware do
       [Tesla.Middleware.KeepRequest, Tesla.Middleware.PathParams, Tesla.Middleware.JSON]
     end

     defp adapter do
       :my_app
       |> Application.get_env(__MODULE__, [])
       |> Keyword.get(:adapter)
     end
   end
   ```

8. Replace all the `Tesla.get/2`, `Tesla.post/2`, etc. to receive the client
   as an argument.

   ```diff
   defmodule MyApp.MyTeslaClient do
     def do_something do
   -   get("/endpoint")
   +   Tesla.get!(client(), "/endpoint")
     end
   end
   ```
