defmodule Tesla do
  defmacro __using__(_what) do
    quote do
      def get(url),   do: request(:get,  url)
      def post(url),  do: request(:post,  url)

      defp request(method, url) do
        %Tesla.Env{
          method: method,
          url:    url
        }
      end

      import Tesla
    end
  end

  defmacro adapter(ad) do
    quote do
      @adapter unquote(ad)
    end
  end
end

defmodule Tesla.Env do
  defstruct url:      "",
            method:   nil
end
