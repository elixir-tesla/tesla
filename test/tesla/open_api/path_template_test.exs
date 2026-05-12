defmodule Tesla.OpenAPI.PathTemplateTest do
  use ExUnit.Case, async: true

  alias Tesla.OpenAPI.PathTemplate

  defp render_expression(name, _expression, params) do
    Map.fetch!(params, name)
  end

  test "new! compiles OpenAPI template expressions" do
    assert %PathTemplate{
             path: "/items/{id}{coords}",
             parts: [
               "/items/",
               {:expr, "id", "{id}"},
               {:expr, "coords", "{coords}"}
             ]
           } = PathTemplate.new!("/items/{id}{coords}")
  end

  test "new! keeps literal paths" do
    assert %PathTemplate{path: "/items", parts: ["/items"]} = PathTemplate.new!("/items")
  end

  test "new! supports OpenAPI template expression names" do
    assert %PathTemplate{
             parts: [
               "/items/",
               {:expr, "color.name+shade", "{color.name+shade}"}
             ]
           } = PathTemplate.new!("/items/{color.name+shade}")
  end

  test "new! supports unicode template expression names" do
    assert %PathTemplate{
             parts: ["/items/", {:expr, "café", "{café}"}]
           } = PathTemplate.new!("/items/{café}")
  end

  test "new! supports delimiter characters inside template expression names" do
    assert %PathTemplate{
             parts: [
               "/items/",
               {:expr, "filter?sort#page", "{filter?sort#page}"}
             ]
           } = PathTemplate.new!("/items/{filter?sort#page}")
  end

  test "inspect hides compiled parts" do
    inspected = inspect(PathTemplate.new!("/items/{id}"))

    assert inspected =~ ~s(path: "/items/{id}")
    refute inspected =~ "expr"
  end

  test "put_private adds template to request private data" do
    template = PathTemplate.new!("/items/{id}")

    assert PathTemplate.put_private(template) == %{tesla_path_template: template}
  end

  test "put_private preserves existing private data" do
    template = PathTemplate.new!("/items/{id}")

    assert PathTemplate.put_private(%{request_id: "abc123"}, template) == %{
             request_id: "abc123",
             tesla_path_template: template
           }
  end

  test "fetch_private ignores invalid private data" do
    assert PathTemplate.fetch_private(%{tesla_path_template: :invalid}) == :error
  end

  test "render returns rendered path" do
    template = PathTemplate.new!("/items/{id}")

    assert PathTemplate.render(template, "/items/{id}", %{"id" => "42"}, &render_expression/3) ==
             {:ok, "/items/42"}
  end

  test "render returns named error when path does not match template path" do
    template = PathTemplate.new!("/items/{id}")

    assert PathTemplate.render(template, "/users/{id}", %{"id" => "42"}, &render_expression/3) ==
             {:error, :path_mismatch}
  end

  test "rejects paths that do not start with slash" do
    assert_raise ArgumentError, ~r/start with \//, fn ->
      PathTemplate.new!("items/{id}")
    end
  end

  test "rejects query strings" do
    assert_raise ArgumentError, ~r/not to include query or fragment/, fn ->
      PathTemplate.new!("/items/{id}?x=1")
    end
  end

  test "rejects fragments" do
    assert_raise ArgumentError, ~r/not to include query or fragment/, fn ->
      PathTemplate.new!("/items/{id}#details")
    end
  end

  test "rejects unclosed template expression" do
    assert_raise ArgumentError, ~r/unclosed template expression/, fn ->
      PathTemplate.new!("/items/{id")
    end
  end

  test "rejects unexpected closing delimiter" do
    assert_raise ArgumentError, ~r/unexpected closing \}/, fn ->
      PathTemplate.new!("/items/id}")
    end
  end

  test "rejects nested template expressions" do
    assert_raise ArgumentError, ~r/nested template expressions/, fn ->
      PathTemplate.new!("/items/{i{d}}")
    end
  end

  test "rejects empty template expressions" do
    assert_raise ArgumentError, ~r/empty template expression/, fn ->
      PathTemplate.new!("/items/{}")
    end
  end

  test "rejects duplicate template expressions" do
    assert_raise ArgumentError, ~r/duplicate template expressions \["id"\]/, fn ->
      PathTemplate.new!("/items/{id}/related/{id}")
    end
  end

  test "rejects duplicate template expressions once" do
    assert_raise ArgumentError, ~r/duplicate template expressions \["id", "org"\]/, fn ->
      PathTemplate.new!("/orgs/{org}/items/{id}/related/{id}/{org}")
    end
  end
end
