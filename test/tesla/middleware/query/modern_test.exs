defmodule Tesla.Middleware.Query.ModernTest do
  use ExUnit.Case

  alias Tesla.Env
  alias Tesla.Middleware.Query
  alias Tesla.QueryParam
  alias Tesla.QueryParams
  alias Tesla.QueryString

  defmodule TestFilter do
    defstruct [:role, :id]
  end

  describe "OpenAPI style examples" do
    test "form style with explode false" do
      assert_url(query_param("color", nil, explode: false), "/colors?color=")
      assert_url(query_param("color", "blue", explode: false), "/colors?color=blue")

      assert_url(
        query_param("color", ["blue", "black", "brown"], explode: false),
        "/colors?color=blue,black,brown"
      )

      assert_url(
        query_param("color", [R: 100, G: 200, B: 150], explode: false),
        "/colors?color=R,100,G,200,B,150"
      )
    end

    test "form style with explode true" do
      assert_url(query_param("color", nil), "/colors?color=")
      assert_url(query_param("color", "blue"), "/colors?color=blue")

      assert_url(
        query_param("color", ["blue", "black", "brown"]),
        "/colors?color=blue&color=black&color=brown"
      )

      assert_url(
        query_param("color", R: 100, G: 200, B: 150),
        "/colors?R=100&G=200&B=150"
      )
    end

    test "space_delimited style with explode false" do
      assert_url(
        query_param("color", ["blue", "black", "brown"], style: :space_delimited),
        "/colors?color=blue%20black%20brown"
      )

      assert_url(
        query_param("color", [R: 100, G: 200, B: 150], style: :space_delimited),
        "/colors?color=R%20100%20G%20200%20B%20150"
      )
    end

    test "pipe_delimited style with explode false" do
      assert_url(
        query_param("color", ["blue", "black", "brown"], style: :pipe_delimited),
        "/colors?color=blue%7Cblack%7Cbrown"
      )

      assert_url(
        query_param("color", [R: 100, G: 200, B: 150], style: :pipe_delimited),
        "/colors?color=R%7C100%7CG%7C200%7CB%7C150"
      )
    end

    test "deep_object style" do
      assert_url(
        query_param("color", [R: 100, G: 200, B: 150], style: :deep_object),
        "/colors?color%5BR%5D=100&color%5BG%5D=200&color%5BB%5D=150"
      )
    end
  end

  describe "modern mode contract" do
    test "serializes a representative multi-style query" do
      assert_url(
        [
          query_param("page", 1),
          query_param("tags", ["blue", "black"]),
          query_param("ids", [1, 2, 3], style: :pipe_delimited),
          query_param("filter", [role: "admin"], style: :deep_object)
        ],
        "/colors?page=1&tags=blue&tags=black&ids=1%7C2%7C3&filter%5Brole%5D=admin"
      )
    end

    test "appends to an existing query string" do
      assert_url(query_param("page", 2), "/colors?existing=1&page=2", "/colors?existing=1")
    end

    test "serializes values in definition order" do
      assert_url(
        [
          query_param("b", 2),
          query_param("a", 1)
        ],
        "/colors?b=2&a=1"
      )
    end

    test "clears env.query so downstream URL builders do not encode twice" do
      query_params = QueryParams.new!([QueryParam.new!("page")])

      assert {:ok, env} =
               Query.call(
                 %Env{
                   url: "/colors",
                   query: %{"page" => 1},
                   private: QueryParams.put_private(query_params)
                 },
                 [],
                 mode: :modern
               )

      assert env.query == []
    end

    test "leaves additional query params for downstream URL builders" do
      query_params =
        QueryParams.new!([
          QueryParam.new!("ids", style: :pipe_delimited)
        ])

      assert {:ok, env} =
               Query.call(
                 %Env{
                   url: "/colors",
                   query: %{
                     "ids" => [1, 2],
                     "debug" => true,
                     "page" => 2
                   },
                   private: QueryParams.put_private(query_params)
                 },
                 [],
                 mode: :modern
               )

      assert env.url == "/colors?ids=1%7C2"
      assert env.query == %{"debug" => true, "page" => 2}
    end

    test "additional query params use normal Tesla query encoding downstream" do
      query_params =
        QueryParams.new!([
          QueryParam.new!("ids", style: :pipe_delimited)
        ])

      assert {:ok, env} =
               Query.call(
                 %Env{
                   url: "/colors",
                   query: %{
                     "ids" => [1, 2],
                     "debug" => true,
                     "q" => "John Smith"
                   },
                   private: QueryParams.put_private(query_params)
                 },
                 [],
                 mode: :modern
               )

      query = URI.parse(Tesla.build_url(env)).query

      assert String.starts_with?(query, "ids=1%7C2&")
      assert String.contains?(query, "debug=true")
      assert String.contains?(query, "q=John+Smith")
    end

    test "additional query params respect normal Tesla query encoding options downstream" do
      query_params =
        QueryParams.new!([
          QueryParam.new!("ids", style: :pipe_delimited)
        ])

      assert {:ok, env} =
               Query.call(
                 %Env{
                   url: "/colors",
                   query: %{
                     "ids" => [1, 2],
                     "q" => "John Smith"
                   },
                   opts: [query_encoding: :rfc3986],
                   private: QueryParams.put_private(query_params)
                 },
                 [],
                 mode: :modern
               )

      query = URI.parse(Tesla.build_url(env)).query

      assert String.starts_with?(query, "ids=1%7C2&")
      assert String.contains?(query, "q=John%20Smith")
    end

    test "serializes additionalProperties object values and leaves unrelated query params" do
      query_params =
        QueryParams.new!([
          QueryParam.new!("filter")
        ])

      assert {:ok, env} =
               Query.call(
                 %Env{
                   url: "/colors",
                   query: %{
                     "filter" => [status: "open", owner: "yordis"],
                     "debug" => true
                   },
                   private: QueryParams.put_private(query_params)
                 },
                 [],
                 mode: :modern
               )

      assert env.url == "/colors?status=open&owner=yordis"
      assert env.query == %{"debug" => true}
    end

    test "leaves normal query maps alone without query params private data" do
      assert {:ok, env} =
               Query.call(%Env{url: "/colors", query: %{"page" => 1}}, [], mode: :modern)

      assert env.url == "/colors"
      assert env.query == %{"page" => 1}
    end

    test "leaves URL untouched when query is empty" do
      assert {:ok, env} = Query.call(%Env{url: "/colors", query: []}, [], mode: :modern)

      assert env.url == "/colors"
      assert env.query == []
    end

    test "leaves URL untouched when query is nil" do
      assert {:ok, env} = Query.call(%Env{url: "/colors", query: nil}, [], mode: :modern)

      assert env.url == "/colors"
      assert env.query == []
    end

    test "lets whole-query-string values pass through" do
      query_string = QueryString.form!(q: "blue")

      assert {:ok, env} =
               Query.call(%Env{url: "/colors", query: query_string}, [], mode: :modern)

      assert env.url == "/colors"
      assert env.query == query_string
    end

    test "requires query to be a map of request values" do
      assert_raise ArgumentError,
                   ~r/expected query to be a map of request values/,
                   fn ->
                     Query.call(%Env{url: "/colors", query: [id: 1]}, [], mode: :modern)
                   end
    end

    test "leaves query maps alone when definitions do not match any names" do
      query_params = QueryParams.new!([QueryParam.new!("id")])

      assert {:ok, env} =
               Query.call(
                 %Env{
                   url: "/colors",
                   query: %{"unknown" => 1},
                   private: QueryParams.put_private(query_params)
                 },
                 [],
                 mode: :modern
               )

      assert env.url == "/colors"
      assert env.query == %{"unknown" => 1}
    end
  end

  describe "OpenAPI style rules" do
    for {style, value, label} <- [
          {:space_delimited, nil, "undefined"},
          {:space_delimited, "blue", "string"},
          {:pipe_delimited, nil, "undefined"},
          {:pipe_delimited, "blue", "string"}
        ] do
      test "#{style} with explode false rejects #{label}" do
        assert_raise ArgumentError, fn ->
          assert_url(
            query_param("color", unquote(Macro.escape(value)), style: unquote(style)),
            "/colors"
          )
        end
      end
    end

    for {style, value, label} <- [
          {:space_delimited, nil, "undefined"},
          {:space_delimited, "blue", "string"},
          {:space_delimited, ["blue"], "array"},
          {:space_delimited, [R: 100], "object"},
          {:pipe_delimited, nil, "undefined"},
          {:pipe_delimited, "blue", "string"},
          {:pipe_delimited, ["blue"], "array"},
          {:pipe_delimited, [R: 100], "object"}
        ] do
      test "#{style} with explode true rejects #{label}" do
        assert_raise ArgumentError, fn ->
          assert_url(
            query_param("color", unquote(Macro.escape(value)),
              style: unquote(style),
              explode: true
            ),
            "/colors"
          )
        end
      end
    end

    for {value, label} <- [
          {nil, "undefined"},
          {"blue", "string"},
          {["blue"], "array"}
        ] do
      test "deep_object rejects #{label}" do
        assert_raise ArgumentError, fn ->
          assert_url(
            query_param("color", unquote(Macro.escape(value)), style: :deep_object),
            "/colors"
          )
        end
      end
    end

    test "space_delimited does not define explode true" do
      assert_raise ArgumentError, ~r/:space_delimited style does not define explode: true/, fn ->
        assert_url(
          query_param("color", ["blue"], style: :space_delimited, explode: true),
          "/colors?color=blue"
        )
      end
    end

    test "space_delimited requires an array or object" do
      assert_raise ArgumentError,
                   ~r/:space_delimited style requires an array or object value/,
                   fn ->
                     assert_url(
                       query_param("color", "blue", style: :space_delimited),
                       "/colors?color=blue"
                     )
                   end
    end

    test "pipe_delimited does not define explode true" do
      assert_raise ArgumentError, ~r/:pipe_delimited style does not define explode: true/, fn ->
        assert_url(
          query_param("color", ["blue"], style: :pipe_delimited, explode: true),
          "/colors?color=blue"
        )
      end
    end

    test "pipe_delimited requires an array or object" do
      assert_raise ArgumentError,
                   ~r/:pipe_delimited style requires an array or object value/,
                   fn ->
                     assert_url(
                       query_param("color", "blue", style: :pipe_delimited),
                       "/colors?color=blue"
                     )
                   end
    end

    test "deep_object requires an object" do
      assert_raise ArgumentError, ~r/:deep_object style requires an object value/, fn ->
        assert_url(query_param("color", ["blue"], style: :deep_object), "/colors?color=blue")
      end
    end

    test "deep_object ignores explode" do
      assert_url(
        query_param("color", [R: 100], style: :deep_object, explode: true),
        "/colors?color%5BR%5D=100"
      )

      assert_url(
        query_param("color", [R: 100], style: :deep_object, explode: false),
        "/colors?color%5BR%5D=100"
      )
    end
  end

  describe "encoding" do
    test "percent-encodes reserved characters by default" do
      assert_url(query_param("q", "a/b c#d"), "/colors?q=a%2Fb%20c%23d")
    end

    test "keeps reserved characters in values when allow_reserved is true" do
      assert_url(query_param("q", "a/b c#d", allow_reserved: true), "/colors?q=a/b%20c#d")
    end

    test "spaces become percent-encoded spaces, not plus signs" do
      assert_url(query_param("q", "John Smith"), "/colors?q=John%20Smith")
    end

    test "unreserved characters stay as-is" do
      assert_url(query_param("q", "a-b_c.d~e"), "/colors?q=a-b_c.d~e")
    end

    test "query names are encoded even when allow_reserved is true" do
      assert_url(
        query_param("filter[role]", "admin", allow_reserved: true),
        "/colors?filter%5Brole%5D=admin"
      )
    end
  end

  describe "object values" do
    test "supports struct values as objects" do
      query_params = QueryParams.new!([QueryParam.new!("filter", style: :deep_object)])

      assert {:ok, env} =
               Query.call(
                 %Env{
                   url: "/colors",
                   query: %{"filter" => %TestFilter{role: "admin", id: 5}},
                   private: QueryParams.put_private(query_params)
                 },
                 [],
                 mode: :modern
               )

      assert env.url =~ "filter%5Brole%5D=admin"
      assert env.url =~ "filter%5Bid%5D=5"
    end

    test "omits empty arrays and objects" do
      assert_url(
        [
          query_param("empty_array", []),
          query_param("empty_form_object", %{}),
          query_param("empty_object", []),
          query_param("empty_map", %{}, style: :deep_object),
          query_param("present", 1)
        ],
        "/colors?present=1"
      )
    end

    test "omits empty arrays and objects for delimited styles" do
      assert_url(
        [
          query_param("empty_space_array", [], style: :space_delimited),
          query_param("empty_space_object", %{}, style: :space_delimited),
          query_param("empty_pipe_array", [], style: :pipe_delimited),
          query_param("empty_pipe_object", %{}, style: :pipe_delimited),
          query_param("present", 1)
        ],
        "/colors?present=1"
      )
    end
  end

  defp query_param(name, value, opts \\ []) do
    {QueryParam.new!(name, opts), value}
  end

  defp assert_url({%QueryParam{}, _value} = param, expected_url) do
    assert_url([param], expected_url)
  end

  defp assert_url(params, expected_url) when is_list(params) do
    assert_url(params, expected_url, "/colors")
  end

  defp assert_url({%QueryParam{}, _value} = param, expected_url, url) do
    assert_url([param], expected_url, url)
  end

  defp assert_url(params, expected_url, url) when is_list(params) do
    query_params = QueryParams.new!(Enum.map(params, &definition/1))
    values = Map.new(params, &query_value/1)

    assert {:ok, env} =
             Query.call(
               %Env{
                 url: url,
                 query: values,
                 private: QueryParams.put_private(query_params)
               },
               [],
               mode: :modern
             )

    assert env.url == expected_url
  end

  defp definition({%QueryParam{} = query_param, _value}) do
    query_param
  end

  defp query_value({%QueryParam{name: name}, value}) do
    {name, value}
  end
end
