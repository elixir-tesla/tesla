defmodule Tesla.OpenApiTest.Helpers do
  # alias Tesla.OpenApi

  # defmodule Config do
  #   def op_name(name), do: name
  #   def generate?(_), do: true
  # end

  defmacro assert_code(code, do: body) do
    quote do
      a = render(unquote(code))
      b = unquote(render(body))
      assert a == b, message: "Assert failed\n\n#{a}\n\nis not equal to\n\n#{b}"
    end
  end

  # def type(field), do: OpenApi.type(field)
  # def model(field), do: OpenApi.model("t", field)
  # def encode(field), do: OpenApi.encode(field, Macro.var(:x, Tesla.OpenApi))
  # def decode(field), do: OpenApi.decode(field, Macro.var(:x, Tesla.OpenApi))

  # def operation(method, path, op, config \\ Config),
  #   do: OpenApi.operation(method, path, op, config)

  def render(code) do
    code
    |> Macro.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end
end
