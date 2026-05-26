defmodule Tesla.Middleware.FormUrlencodedTest do
  use ExUnit.Case

  defmodule Client do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/post" ->
            {201, [{"content-type", "text/html"}], env.body}

          "/check_incoming_content_type" ->
            {201, [{"content-type", "text/html"}], Tesla.get_header(env, "content-type")}

          "/decode_response" ->
            {200, [{"content-type", "application/x-www-form-urlencoded; charset=utf-8"}],
             "x=1&y=2"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "encode body as application/x-www-form-urlencoded" do
    assert {:ok, env} = Client.post("/post", %{"foo" => "%bar "})
    assert URI.decode_query(env.body) == %{"foo" => "%bar "}
  end

  test "leave body alone if binary" do
    assert {:ok, env} = Client.post("/post", "data")
    assert env.body == "data"
  end

  test "check header is set as application/x-www-form-urlencoded" do
    assert {:ok, env} = Client.post("/check_incoming_content_type", %{"foo" => "%bar "})
    assert env.body == "application/x-www-form-urlencoded"
  end

  test "decode response" do
    assert {:ok, env} = Client.get("/decode_response")
    assert env.body == %{"x" => "1", "y" => "2"}
  end

  defmodule MultipartClient do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded

    adapter fn %{url: url, body: %Tesla.Multipart{}} = env ->
      {status, headers, body} =
        case url do
          "/upload" ->
            {200, [{"content-type", "text/html"}], "ok"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "skips encoding multipart bodies" do
    alias Tesla.Multipart

    mp =
      Multipart.new()
      |> Multipart.add_field("param", "foo")

    assert {:ok, env} = MultipartClient.post("/upload", mp)
    assert env.body == "ok"
  end

  defmodule NewEncoderClient do
    use Tesla

    def encoder(_data) do
      "iamencoded"
    end

    plug Tesla.Middleware.FormUrlencoded, encode: &encoder/1

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/post" ->
            {201, [{"content-type", "text/html"}], env.body}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "uses encoder configured in options" do
    {:ok, env} = NewEncoderClient.post("/post", %{"foo" => "bar"})

    assert env.body == "iamencoded"
  end

  defmodule NewDecoderClient do
    use Tesla

    def decoder(_data) do
      "decodedbody"
    end

    plug Tesla.Middleware.FormUrlencoded, decode: &decoder/1

    adapter fn env ->
      {status, headers, body} =
        case env.url do
          "/post" ->
            {200, [{"content-type", "application/x-www-form-urlencoded; charset=utf-8"}],
             "x=1&y=2"}
        end

      {:ok, %{env | status: status, headers: headers, body: body}}
    end
  end

  test "uses decoder configured in options" do
    {:ok, env} = NewDecoderClient.post("/post", %{"foo" => "bar"})

    assert env.body == "decodedbody"
  end

  describe "encode: :deep_object end-to-end through middleware" do
    defmodule NestedClient do
      use Tesla

      plug Tesla.Middleware.FormUrlencoded, encode: :deep_object

      adapter fn env ->
        {:ok, %{env | status: 201, headers: [{"content-type", "text/html"}], body: env.body}}
      end
    end

    test "encodes nested bodies with bracket-indexed lists" do
      body = %{
        expand: ["objects"],
        objects: %{customers: ["cus_123", "cus_456"]},
        validation_behavior: :fix
      }

      assert {:ok, env} = NestedClient.post("/post", body)

      assert env.body |> String.split("&") |> MapSet.new() ==
               MapSet.new([
                 "expand[0]=objects",
                 "objects[customers][0]=cus_123",
                 "objects[customers][1]=cus_456",
                 "validation_behavior=fix"
               ])
    end
  end

  describe "encode: :deep_object encoder behavior" do
    defmodule Profile do
      defstruct [:name, :age]
    end

    test "indexes flat list items" do
      assert encode_body(%{ids: ["a", "b"]}, encode: :deep_object) == "ids[0]=a&ids[1]=b"
    end

    test "brackets nested map keys" do
      assert encode_body(%{user: %{name: "a"}}, encode: :deep_object) == "user[name]=a"
    end

    test "indexes lists of objects" do
      assert encode_body(%{users: [%{name: "a"}, %{name: "b"}]}, encode: :deep_object)
             |> as_pairs() ==
               MapSet.new(["users[0][name]=a", "users[1][name]=b"])
    end

    test "drops nil at the top level" do
      assert encode_body(%{a: 1, b: nil, c: 2}, encode: :deep_object) |> as_pairs() ==
               MapSet.new(["a=1", "c=2"])
    end

    test "drops nil inside nested maps" do
      assert encode_body(%{user: %{name: "a", email: nil}}, encode: :deep_object) ==
               "user[name]=a"
    end

    test "drops nil from lists and renumbers indices" do
      assert encode_body(%{ids: [1, nil, 2, nil, 3]}, encode: :deep_object) ==
               "ids[0]=1&ids[1]=2&ids[2]=3"
    end

    test "encodes booleans as true/false" do
      assert encode_body(%{a: true, b: false}, encode: :deep_object) |> as_pairs() ==
               MapSet.new(["a=true", "b=false"])
    end

    test "encodes atom values via Atom.to_string/1" do
      assert encode_body(%{state: :active}, encode: :deep_object) == "state=active"
    end

    test "encodes integers and floats" do
      assert encode_body(%{count: 42, ratio: 1.5}, encode: :deep_object) |> as_pairs() ==
               MapSet.new(["count=42", "ratio=1.5"])
    end

    test "URI-encodes special characters in values" do
      assert encode_body(%{q: "a&b=c%d e"}, encode: :deep_object) == "q=a%26b%3Dc%25d+e"
    end

    test "URI-encodes special characters in keys" do
      assert encode_body(%{"weird key" => "v"}, encode: :deep_object) == "weird+key=v"
    end

    test "unwraps top-level structs via Map.from_struct/1" do
      assert encode_body(%Profile{name: "Alice", age: 30}, encode: :deep_object) |> as_pairs() ==
               MapSet.new(["name=Alice", "age=30"])
    end

    test "unwraps nested structs without String.Chars" do
      assert encode_body(%{profile: %Profile{name: "Alice", age: 30}}, encode: :deep_object)
             |> as_pairs() ==
               MapSet.new(["profile[name]=Alice", "profile[age]=30"])
    end

    test "stringifies nested structs that implement String.Chars" do
      assert encode_body(%{day: ~D[2024-01-02]}, encode: :deep_object) ==
               "day=2024-01-02"

      assert encode_body(%{at: ~U[2024-01-02 03:04:05Z]}, encode: :deep_object) ==
               "at=2024-01-02+03%3A04%3A05Z"

      assert encode_body(%{target: URI.parse("https://example.com/p?x=1")}, encode: :deep_object) ==
               "target=https%3A%2F%2Fexample.com%2Fp%3Fx%3D1"
    end

    test "stringifies String.Chars structs inside lists" do
      assert encode_body(%{days: [~D[2024-01-01], ~D[2024-01-02]]}, encode: :deep_object) ==
               "days[0]=2024-01-01&days[1]=2024-01-02"
    end

    test "empty map encodes to empty string" do
      assert encode_body(%{}, encode: :deep_object) == ""
    end

    test "empty list value emits nothing" do
      assert encode_body(%{ids: []}, encode: :deep_object) == ""
    end

    test "keyword list at top level encodes in given order" do
      assert encode_body([a: 1, b: 2, c: 3], encode: :deep_object) == "a=1&b=2&c=3"
    end

    test "keyword list inside map encodes as nested object" do
      assert encode_body(%{filter: [role: "admin", active: true]}, encode: :deep_object)
             |> as_pairs() ==
               MapSet.new(["filter[role]=admin", "filter[active]=true"])
    end

    test "keyword list inside array encodes as nested object" do
      assert encode_body(%{users: [[name: "a"], [name: "b"]]}, encode: :deep_object)
             |> as_pairs() ==
               MapSet.new(["users[0][name]=a", "users[1][name]=b"])
    end

    test "deeply nested map+list mix" do
      assert encode_body(%{a: %{b: [%{c: 1}, %{c: 2}]}}, encode: :deep_object) |> as_pairs() ==
               MapSet.new(["a[b][0][c]=1", "a[b][1][c]=2"])
    end

    test "raises clear error for unknown encoder option" do
      assert_raise ArgumentError, ~r/unknown :encode option :unknown/, fn ->
        encode_body(%{a: 1}, encode: :unknown)
      end
    end

    defp encode_body(body, opts) do
      %Tesla.Env{body: body}
      |> Tesla.Middleware.FormUrlencoded.encode(opts)
      |> Map.fetch!(:body)
    end

    defp as_pairs(encoded), do: encoded |> String.split("&") |> MapSet.new()
  end

  describe "Encode / Decode" do
    defmodule EncodeDecodeFormUrlencodedClient do
      use Tesla

      plug Tesla.Middleware.DecodeFormUrlencoded
      plug Tesla.Middleware.EncodeFormUrlencoded

      adapter fn env ->
        {status, headers, body} =
          case env.url do
            "/foo2baz" ->
              {200, [{"content-type", "application/x-www-form-urlencoded"}],
               env.body |> String.replace("foo", "baz")}
          end

        {:ok, %{env | status: status, headers: headers, body: body}}
      end
    end

    test "work without options" do
      assert {:ok, env} = EncodeDecodeFormUrlencodedClient.post("/foo2baz", %{"foo" => "bar"})
      assert env.body == %{"baz" => "bar"}
    end
  end
end
