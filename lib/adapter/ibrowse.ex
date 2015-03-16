defmodule Tesla.Adapter.Ibrowse do
  def start do
    :ibrowse.start
  end

  def call(env) do
    {:ok, status, headers, body} = :ibrowse.send_req(
      env.url |> to_char_list,
      env.headers,
      env.method
    )

    %{env | status:   status,
            headers:  headers,
            body:     body}
  end
end
