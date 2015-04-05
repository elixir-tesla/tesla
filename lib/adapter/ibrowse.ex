defmodule Tesla.Adapter.Ibrowse do
  def start do
    :ibrowse.start
  end

  def call(env) do
    {:ok, status, headers, body} = :ibrowse.send_req(
      env.url |> to_char_list,
      Enum.into(env.headers, []),
      env.method
    )

    %{env | status:   status,
            headers:  Enum.into(headers, %{}),
            body:     body}
  end
end
