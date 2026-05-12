defmodule Tesla.OpenAPI.QueryStringTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.QueryString
  alias Tesla.OpenAPI.QueryStringError

  test "raw! builds a query string from already serialized content" do
    assert %QueryString{
             content_type: "application/x-www-form-urlencoded"
           } = query_string = QueryString.raw!("foo=a+%2B+b&bar=true")

    assert QueryString.to_query(query_string) == "foo=a+%2B+b&bar=true"
  end

  test "raw! accepts an explicit content type" do
    query_string =
      QueryString.raw!("%7B%22numbers%22%3A%5B1%2C2%5D%7D",
        content_type: "application/json"
      )

    assert %QueryString{content_type: "application/json"} = query_string
    assert QueryString.to_query(query_string) == "%7B%22numbers%22%3A%5B1%2C2%5D%7D"
  end

  test "form! serializes structured params as form-urlencoded query content" do
    query_string = QueryString.form!(foo: "a + b", bar: true)

    assert %QueryString{content_type: "application/x-www-form-urlencoded"} = query_string
    assert QueryString.to_query(query_string) == "foo=a+%2B+b&bar=true"
  end

  test "form! supports nested params through Tesla query encoding" do
    query_string = QueryString.form!(filters: [pagination: [page: 2]])

    assert QueryString.to_query(query_string) == "filters%5Bpagination%5D%5Bpage%5D=2"
  end

  test "does not inspect encoded query content" do
    inspected = inspect(QueryString.raw!("token=secret-token"))

    refute inspected =~ "secret-token"
    assert inspected =~ ~s(content_type: "application/x-www-form-urlencoded")
  end

  test "appends to a URL without existing query params" do
    query_string = QueryString.raw!("foo=a+%2B+b&bar=true")

    assert QueryString.append_to_url(query_string, "https://api.example.com/search") ==
             "https://api.example.com/search?foo=a+%2B+b&bar=true"
  end

  test "appends before URL fragments" do
    query_string = QueryString.raw!("foo=bar")

    assert QueryString.append_to_url(query_string, "https://api.example.com/search#section") ==
             "https://api.example.com/search?foo=bar#section"
  end

  test "ignores query delimiters inside URL fragments" do
    query_string = QueryString.raw!("foo=bar")

    assert QueryString.append_to_url(query_string, "https://api.example.com/search#section?x=1") ==
             "https://api.example.com/search?foo=bar#section?x=1"
  end

  test "empty query strings leave URLs unchanged" do
    assert QueryString.raw!("") |> QueryString.append_to_url("https://api.example.com/search") ==
             "https://api.example.com/search"
  end

  test "empty query strings still reject URLs with existing query params" do
    query_string = QueryString.raw!("")

    assert_raise QueryStringError, ~r/already contains a query string/, fn ->
      QueryString.append_to_url(query_string, "https://api.example.com/search?existing=true")
    end
  end

  test "rejects appending to a URL that already contains query params" do
    query_string = QueryString.raw!("foo=bar")

    assert_raise QueryStringError, ~r/already contains a query string/, fn ->
      QueryString.append_to_url(query_string, "https://api.example.com/search?existing=true")
    end
  end

  test "rejects appending to a URL that already contains query params before a fragment" do
    query_string = QueryString.raw!("foo=bar")

    assert_raise QueryStringError, ~r/already contains a query string/, fn ->
      QueryString.append_to_url(
        query_string,
        "https://api.example.com/search?existing=true#section"
      )
    end
  end

  test "rejects a leading query delimiter" do
    assert_raise QueryStringError, ~r/not to include a leading \?/, fn ->
      QueryString.raw!("?foo=bar")
    end
  end

  test "rejects non-string raw query strings" do
    assert_raise QueryStringError, ~r/expected query string to be a string/, fn ->
      QueryString.raw!(foo: "bar")
    end
  end

  test "rejects non-string content types" do
    assert_raise QueryStringError, ~r/expected query string content type to be a string/, fn ->
      QueryString.raw!("foo=bar", content_type: :json)
    end
  end

  test "rejects empty content types" do
    assert_raise QueryStringError, ~r/content type to be a non-empty string/, fn ->
      QueryString.raw!("foo=bar", content_type: "")
    end
  end

  test "rejects document location as a hand-written option" do
    assert_raise QueryStringError, ~r/unknown keys \[:in\]/, fn ->
      QueryString.raw!("foo=bar", in: :querystring)
    end
  end

  test "rejects non-keyword options" do
    assert_raise QueryStringError, ~r/invalid query string options/, fn ->
      QueryString.raw!("foo=bar", %{})
    end
  end
end
