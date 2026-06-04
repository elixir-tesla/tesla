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

  defmodule NestedClient do
    use Tesla

    plug Tesla.Middleware.FormUrlencoded, encode: :brackets

    adapter fn env ->
      {:ok, %{env | status: 201, headers: [{"content-type", "text/html"}], body: env.body}}
    end
  end

  defmodule Profile do
    defstruct [:name, :age]
  end

  describe "encode: :brackets end-to-end through middleware" do
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

  describe "encode: :brackets encoder behavior" do
    test "indexes flat list items" do
      assert encode_body(%{ids: ["a", "b"]}, encode: :brackets) == "ids[0]=a&ids[1]=b"
    end

    test "brackets nested map keys" do
      assert encode_body(%{user: %{name: "a"}}, encode: :brackets) == "user[name]=a"
    end

    test "indexes lists of objects" do
      assert encode_body(%{users: [%{name: "a"}, %{name: "b"}]}, encode: :brackets)
             |> as_pairs() ==
               MapSet.new(["users[0][name]=a", "users[1][name]=b"])
    end

    test "drops nil at the top level" do
      assert encode_body(%{a: 1, b: nil, c: 2}, encode: :brackets) |> as_pairs() ==
               MapSet.new(["a=1", "c=2"])
    end

    test "drops nil inside nested maps" do
      assert encode_body(%{user: %{name: "a", email: nil}}, encode: :brackets) ==
               "user[name]=a"
    end

    test "drops nil from lists and preserves original indices" do
      assert encode_body(%{ids: [1, nil, 2, nil, 3]}, encode: :brackets) ==
               "ids[0]=1&ids[2]=2&ids[4]=3"
    end

    test "encodes booleans as true/false" do
      assert encode_body(%{a: true, b: false}, encode: :brackets) |> as_pairs() ==
               MapSet.new(["a=true", "b=false"])
    end

    test "encodes atom values via Atom.to_string/1" do
      assert encode_body(%{state: :active}, encode: :brackets) == "state=active"
    end

    test "encodes integers and floats" do
      assert encode_body(%{count: 42, ratio: 1.5}, encode: :brackets) |> as_pairs() ==
               MapSet.new(["count=42", "ratio=1.5"])
    end

    test "URI-encodes special characters in values" do
      assert encode_body(%{q: "a&b=c%d e"}, encode: :brackets) == "q=a%26b%3Dc%25d+e"
    end

    test "URI-encodes special characters in keys" do
      assert encode_body(%{"weird key" => "v"}, encode: :brackets) == "weird+key=v"
    end

    test "raises on top-level struct" do
      assert_raise ArgumentError, ~r/cannot encode .*Profile struct/, fn ->
        encode_body(%Profile{name: "Alice", age: 30}, encode: :brackets)
      end
    end

    test "raises on nested struct" do
      assert_raise ArgumentError, ~r/cannot encode DateTime struct/, fn ->
        encode_body(%{at: ~U[2024-01-02 03:04:05Z]}, encode: :brackets)
      end
    end

    test "raises on struct inside a list" do
      assert_raise ArgumentError, ~r/cannot encode Date struct/, fn ->
        encode_body(%{days: [~D[2024-01-01], ~D[2024-01-02]]}, encode: :brackets)
      end
    end

    test "raises on tuple value with a clear error" do
      assert_raise ArgumentError, ~r/cannot encode tuple \{1, 2\}/, fn ->
        encode_body(%{point: {1, 2}}, encode: :brackets)
      end
    end

    test "empty map encodes to empty string" do
      assert encode_body(%{}, encode: :brackets) == ""
    end

    test "empty list value emits nothing" do
      assert encode_body(%{ids: []}, encode: :brackets) == ""
    end

    test "empty list inside nested map drops the parent key" do
      assert encode_body(%{user: %{tags: []}}, encode: :brackets) == ""
    end

    test "raises clear error for non-enumerable root value" do
      assert_raise ArgumentError, ~r/cannot encode 42 with :brackets/, fn ->
        encode_body(42, encode: :brackets)
      end
    end

    test "raises clear error for non-keyword list at the root" do
      assert_raise ArgumentError, ~r/cannot encode \[1, 2, 3\] with :brackets/, fn ->
        encode_body([1, 2, 3], encode: :brackets)
      end
    end

    test "raises clear error for mixed list at the root" do
      assert_raise ArgumentError, ~r/cannot encode \[\{:a, 1\}, 2\] with :brackets/, fn ->
        encode_body([{:a, 1}, 2], encode: :brackets)
      end
    end

    test "list of tuples inside a map raises the tuple error (use a map for nesting)" do
      assert_raise ArgumentError, ~r/cannot encode tuple \{"a", 1\}/, fn ->
        encode_body(%{user: [{"a", 1}, {"b", 2}]}, encode: :brackets)
      end
    end

    test "keyword list inside a map raises the tuple error (use a map for nesting)" do
      assert_raise ArgumentError, ~r/cannot encode tuple \{:role, "admin"\}/, fn ->
        encode_body(%{filter: [role: "admin"]}, encode: :brackets)
      end
    end

    test "boolean_as: :integer does not rewrite arbitrary 2-tuple values before erroring" do
      assert_raise ArgumentError, ~r/cannot encode tuple \{1, true\}/, fn ->
        encode_body(%{point: {1, true}}, encode: {:brackets, boolean_as: :integer})
      end
    end

    test "keyword list at top level encodes in given order" do
      assert encode_body([a: 1, b: 2, c: 3], encode: :brackets) == "a=1&b=2&c=3"
    end

    test "list of 2-tuples at top level preserves order" do
      assert encode_body([{"a", 1}, {"b", 2}, {"c", 3}], encode: :brackets) == "a=1&b=2&c=3"
    end

    test "list of 2-tuples at top level allows duplicate keys" do
      assert encode_body([{"tag", "a"}, {"tag", "b"}, {"tag", "c"}], encode: :brackets) ==
               "tag=a&tag=b&tag=c"
    end

    test "list of 2-tuples at top level allows non-atom keys mixed with values" do
      assert encode_body([{"a b", "hello world"}, {"c", "d"}], encode: :brackets) ==
               "a+b=hello+world&c=d"
    end

    test "deeply nested map+list mix" do
      assert encode_body(%{a: %{b: [%{c: 1}, %{c: 2}]}}, encode: :brackets) |> as_pairs() ==
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

  describe "encode: :brackets PHP http_build_query parity" do
    # Each tuple: {label, input, expected}.
    #
    # Expected outputs were captured from PHP 8.3's http_build_query and
    # then normalized two ways before comparison:
    #
    #   * `%5B`/`%5D` rewritten to literal `[`/`]` — Tesla emits literal
    #     brackets while PHP percent-encodes them. Both forms URL-decode to
    #     the same key, so any conformant parser (Rack, Plug.Conn.Query,
    #     PHP parse_str) treats them as equivalent.
    #   * Top-level `key=value` pairs sorted alphabetically — Elixir maps
    #     don't preserve insertion order, so the test normalizes both sides
    #     by sorting before comparing.
    #
    # Booleans are excluded here and tested separately below: PHP emits
    # `1`/`0`, Tesla emits `true`/`false` (the convention Stripe's API
    # requires; stripe-php normalizes booleans before calling
    # http_build_query, so the SDK-level output also uses `true`/`false`).
    @php_corpus [
      {"scalar/string", %{"key" => "hello"}, "key=hello"},
      {"scalar/integer", %{"key" => 42}, "key=42"},
      {"scalar/zero", %{"key" => 0}, "key=0"},
      {"scalar/negative", %{"key" => -5}, "key=-5"},
      {"scalar/float", %{"key" => 1.5}, "key=1.5"},
      {"scalar/empty_string", %{"key" => ""}, "key="},
      {"nil/top_level_only_nil", %{"key" => nil}, ""},
      {"nil/top_level_mixed", %{"a" => 1, "b" => nil, "c" => 2}, "a=1&c=2"},
      {"nil/all_nil", %{"a" => nil, "b" => nil}, ""},
      {"nil/in_nested_map", %{"user" => %{"name" => "a", "email" => nil}}, "user[name]=a"},
      {"nil/in_list_middle", %{"ids" => ["a", nil, "b"]}, "ids[0]=a&ids[2]=b"},
      {"nil/in_list_leading", %{"ids" => [nil, "a", "b"]}, "ids[1]=a&ids[2]=b"},
      {"nil/in_list_trailing", %{"ids" => ["a", "b", nil]}, "ids[0]=a&ids[1]=b"},
      {"nil/in_list_all_nil", %{"ids" => [nil, nil, nil]}, ""},
      {"nil/multiple_in_list", %{"ids" => [1, nil, 2, nil, 3]}, "ids[0]=1&ids[2]=2&ids[4]=3"},
      {"nil/in_list_of_objects",
       %{"users" => [%{"name" => "a", "email" => nil}, %{"name" => "b"}]},
       "users[0][name]=a&users[1][name]=b"},
      {"empty/map", %{}, ""},
      {"empty/empty_list_value", %{"ids" => []}, ""},
      {"empty/empty_map_value", %{"user" => %{}}, ""},
      {"list/single", %{"ids" => ["a"]}, "ids[0]=a"},
      {"list/multi", %{"ids" => ["a", "b", "c"]}, "ids[0]=a&ids[1]=b&ids[2]=c"},
      {"list/of_ints", %{"nums" => [1, 2, 3]}, "nums[0]=1&nums[1]=2&nums[2]=3"},
      {"list/of_objects", %{"users" => [%{"name" => "a"}, %{"name" => "b"}]},
       "users[0][name]=a&users[1][name]=b"},
      {"list/nested_list", %{"matrix" => [[1, 2], [3, 4]]},
       "matrix[0][0]=1&matrix[0][1]=2&matrix[1][0]=3&matrix[1][1]=4"},
      {"nested/one_level", %{"user" => %{"name" => "a"}}, "user[name]=a"},
      {"nested/two_levels", %{"a" => %{"b" => %{"c" => 1}}}, "a[b][c]=1"},
      {"nested/three_levels", %{"a" => %{"b" => %{"c" => %{"d" => "x"}}}}, "a[b][c][d]=x"},
      {"mixed/object_in_list", %{"users" => [%{"name" => "a", "age" => 30}]},
       "users[0][age]=30&users[0][name]=a"},
      {"mixed/list_in_object", %{"user" => %{"tags" => ["x", "y"]}},
       "user[tags][0]=x&user[tags][1]=y"},
      {"mixed/list_object_list", %{"users" => [%{"tags" => ["x", "y"]}]},
       "users[0][tags][0]=x&users[0][tags][1]=y"},
      {"mixed/stripe_expand", %{"expand" => ["customers", "subscriptions"]},
       "expand[0]=customers&expand[1]=subscriptions"},
      {"mixed/stripe_complex",
       %{
         "expand" => ["objects"],
         "objects" => %{"customers" => ["cus_123", "cus_456"]},
         "validation_behavior" => "fix"
       },
       "expand[0]=objects&objects[customers][0]=cus_123&objects[customers][1]=cus_456&validation_behavior=fix"},
      {"encoding/space_in_value", %{"q" => "hello world"}, "q=hello+world"},
      {"encoding/space_in_key", %{"weird key" => "v"}, "weird+key=v"},
      {"encoding/ampersand_value", %{"q" => "a&b"}, "q=a%26b"},
      {"encoding/equals_value", %{"q" => "a=b"}, "q=a%3Db"},
      {"encoding/percent_value", %{"q" => "a%b"}, "q=a%25b"},
      {"encoding/plus_value", %{"q" => "a+b"}, "q=a%2Bb"},
      {"encoding/hash_value", %{"q" => "a#b"}, "q=a%23b"},
      {"encoding/qmark_value", %{"q" => "a?b"}, "q=a%3Fb"},
      {"encoding/slash_value", %{"q" => "a/b"}, "q=a%2Fb"},
      {"encoding/special_combo", %{"q" => "a&b=c%d e"}, "q=a%26b%3Dc%25d+e"},
      {"encoding/unicode_value", %{"q" => "café"}, "q=caf%C3%A9"},
      {"encoding/unicode_emoji", %{"q" => "🚀"}, "q=%F0%9F%9A%80"},
      {"encoding/newline_value", %{"q" => "line1\nline2"}, "q=line1%0Aline2"},
      {"encoding/tab_value", %{"q" => "a\tb"}, "q=a%09b"},
      {"encoding/quote_value", %{"q" => "he said \"hi\""}, "q=he+said+%22hi%22"},
      {"deep/four_levels", %{"a" => %{"b" => %{"c" => %{"d" => 1}}}}, "a[b][c][d]=1"},
      {"deep/list_of_lists_of_maps", %{"x" => [[%{"k" => 1}], [%{"k" => 2}]]},
       "x[0][0][k]=1&x[1][0][k]=2"}
    ]

    for {label, input, expected} <- @php_corpus do
      test "matches PHP http_build_query: #{label}" do
        actual =
          %Tesla.Env{body: unquote(Macro.escape(input))}
          |> Tesla.Middleware.FormUrlencoded.encode(encode: :brackets)
          |> Map.fetch!(:body)
          |> sort_pairs()

        assert actual == unquote(expected)
      end
    end

    test "default: boolean true encodes as 'true' (Stripe V2 convention)" do
      assert %Tesla.Env{body: %{"key" => true}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: :brackets)
             |> Map.fetch!(:body) == "key=true"
    end

    test "default: boolean false encodes as 'false' (Stripe V2 convention)" do
      assert %Tesla.Env{body: %{"key" => false}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: :brackets)
             |> Map.fetch!(:body) == "key=false"
    end

    test "default: list of booleans uses true/false" do
      assert %Tesla.Env{body: %{"flags" => [true, false, true]}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: :brackets)
             |> Map.fetch!(:body) == "flags[0]=true&flags[1]=false&flags[2]=true"
    end

    test "boolean_as: :string is identical to the default" do
      assert %Tesla.Env{body: %{"key" => true}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :string})
             |> Map.fetch!(:body) == "key=true"
    end

    test "boolean_as: :integer opts into PHP http_build_query parity (true → 1)" do
      assert %Tesla.Env{body: %{"key" => true}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :integer})
             |> Map.fetch!(:body) == "key=1"
    end

    test "boolean_as: :integer opts into PHP http_build_query parity (false → 0)" do
      assert %Tesla.Env{body: %{"key" => false}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :integer})
             |> Map.fetch!(:body) == "key=0"
    end

    test "boolean_as: :integer encodes a list of booleans as 1/0 (matches PHP exactly)" do
      assert %Tesla.Env{body: %{"flags" => [true, false, true]}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :integer})
             |> Map.fetch!(:body) == "flags[0]=1&flags[1]=0&flags[2]=1"
    end

    test "boolean_as: :integer recurses into nested maps" do
      assert %Tesla.Env{body: %{"user" => %{"active" => true, "verified" => false}}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :integer})
             |> Map.fetch!(:body)
             |> sort_pairs() == "user[active]=1&user[verified]=0"
    end

    test "boolean_as: :integer recurses into lists of objects" do
      assert %Tesla.Env{body: %{"items" => [%{"flag" => true}, %{"flag" => false}]}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :integer})
             |> Map.fetch!(:body) == "items[0][flag]=1&items[1][flag]=0"
    end

    test "boolean_as: :integer leaves non-boolean values untouched" do
      assert %Tesla.Env{body: %{"name" => "alice", "age" => 30, "score" => 1.5, "tag" => :ok}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :integer})
             |> Map.fetch!(:body)
             |> sort_pairs() == "age=30&name=alice&score=1.5&tag=ok"
    end

    test "{:brackets, []} with no sub-options behaves like :brackets" do
      assert %Tesla.Env{body: %{"key" => true}}
             |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, []})
             |> Map.fetch!(:body) == "key=true"
    end

    test "invalid :boolean_as value raises" do
      assert_raise ArgumentError, ~r/invalid :boolean_as :nope/, fn ->
        %Tesla.Env{body: %{"k" => true}}
        |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :nope})
      end
    end

    test "unknown sub-option key raises" do
      assert_raise ArgumentError, ~r/unknown option\(s\) \[:weird\]/, fn ->
        %Tesla.Env{body: %{"k" => true}}
        |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, weird: true})
      end
    end

    defp sort_pairs(""), do: ""
    defp sort_pairs(encoded), do: encoded |> String.split("&") |> Enum.sort() |> Enum.join("&")
  end

  describe "encode: {:brackets, boolean_as: :integer} full PHP parity" do
    # The three cases that diverged from PHP under the default Stripe-flavored
    # boolean handling. With boolean_as: :integer, output matches PHP
    # http_build_query byte-for-byte (after the standard %5B/%5D → [/] decode
    # and top-level pair sort applied in the main parity corpus above).
    @php_boolean_corpus [
      {"scalar/bool_true", %{"key" => true}, "key=1"},
      {"scalar/bool_false", %{"key" => false}, "key=0"},
      {"list/of_bools", %{"flags" => [true, false, true]}, "flags[0]=1&flags[1]=0&flags[2]=1"}
    ]

    for {label, input, expected} <- @php_boolean_corpus do
      test "matches PHP http_build_query with boolean_as: :integer: #{label}" do
        actual =
          %Tesla.Env{body: unquote(Macro.escape(input))}
          |> Tesla.Middleware.FormUrlencoded.encode(encode: {:brackets, boolean_as: :integer})
          |> Map.fetch!(:body)
          |> String.split("&")
          |> Enum.sort()
          |> Enum.join("&")

        assert actual == unquote(expected)
      end
    end
  end

  describe "encode: :brackets wire format is parseable" do
    test "URI.decode_query round-trips bracket-keyed pairs" do
      body = %{
        "expand" => ["objects"],
        "objects" => %{"customers" => ["cus_123", "cus_456"]},
        "validation_behavior" => "fix"
      }

      encoded =
        %Tesla.Env{body: body}
        |> Tesla.Middleware.FormUrlencoded.encode(encode: :brackets)
        |> Map.fetch!(:body)

      assert URI.decode_query(encoded) == %{
               "expand[0]" => "objects",
               "objects[customers][0]" => "cus_123",
               "objects[customers][1]" => "cus_456",
               "validation_behavior" => "fix"
             }
    end
  end

  describe "tagged {:form, data} tuples" do
    test "{:form_urlencoded, map} is encoded with default URI.encode_query/1" do
      env =
        %Tesla.Env{body: {:form_urlencoded, %{"foo" => "bar"}}}
        |> Tesla.Middleware.FormUrlencoded.encode([])

      assert env.body == "foo=bar"
      assert Tesla.get_header(env, "content-type") == "application/x-www-form-urlencoded"
    end

    test "{:form_urlencoded, map} is encoded with bracket notation when encode: :brackets" do
      env =
        %Tesla.Env{body: {:form_urlencoded, %{name: "Alice"}}}
        |> Tesla.Middleware.FormUrlencoded.encode(encode: :brackets)

      assert env.body == "name=Alice"
      assert Tesla.get_header(env, "content-type") == "application/x-www-form-urlencoded"
    end

    test "plain map bodies still work as before (backward compatible)" do
      env =
        %Tesla.Env{body: %{"foo" => "bar"}}
        |> Tesla.Middleware.FormUrlencoded.encode([])

      assert env.body == "foo=bar"
      assert Tesla.get_header(env, "content-type") == "application/x-www-form-urlencoded"
    end
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
