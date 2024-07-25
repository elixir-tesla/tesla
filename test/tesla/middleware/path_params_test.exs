defmodule Tesla.Middleware.PathParamsTest do
  use ExUnit.Case, async: true

  alias Tesla.Env

  @middleware Tesla.Middleware.PathParams

  defmodule TestUser do
    defstruct [:id]
  end

  describe "Phoenix-style params (:id)" do
    test "leaves the identifier with no parameters" do
      assert {:ok, env} = @middleware.call(%Env{url: "/users/:id"}, [], nil)
      assert env.url == "/users/:id"
    end

    test "replaces the identifier with passed params" do
      opts = [path_params: [id: 42]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/:id", opts: opts}, [], nil)
      assert env.url == "/users/42"
    end

    test "replaces the identifier with empty passed params" do
      opts = [path_params: [id: ""]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/:id", opts: opts}, [], nil)
      assert env.url == "/users/"
    end

    test "leaves the identifier if no value is given" do
      opts = [path_params: [y: 42]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/:x", opts: opts}, [], nil)
      assert env.url == "/users/:x"
    end

    test "leaves the identifier if the value is nil" do
      opts = [path_params: [id: nil]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/:id", opts: opts}, [], nil)
      assert env.url == "/users/:id"
    end

    test "correctly handles shorter identifiers in longer identifiers" do
      opts = [path_params: [id: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:id/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "correctly handles shorter identifiers in longer identifiers (not provided)" do
      opts = [path_params: [id: 1]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:id/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/1/p/:id_post"
    end

    test "leaves identifiers that start with a number" do
      opts = [path_params: ["1id": 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:1id/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/:1id/p/2"
    end

    test "leaves identifiers that are a single digit" do
      opts = [path_params: ["1": 1, id_post: 2]]

      assert {:ok, env} = @middleware.call(%Env{url: "/users/:1/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/:1/p/2"
    end

    test "replaces identifiers one character long" do
      opts = [path_params: [i: 1, id_post: 2]]

      assert {:ok, env} = @middleware.call(%Env{url: "/users/:i/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "leaves identifiers that are only numbers" do
      opts = [path_params: ["123": 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:123/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/:123/p/2"
    end

    test "leaves identifiers that start with underscore" do
      opts = [path_params: [_id: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:_id/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/:_id/p/2"
    end

    test "replaces any valid identifier" do
      opts = [path_params: [id_1_a: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:id_1_a/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "replaces identifiers that start with a capital letter" do
      opts = [path_params: [id_1_a: 1, IdPost: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:id_1_a/p/:IdPost", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "replaces identifiers where the path params is a struct" do
      opts = [path_params: %TestUser{id: 1}]

      assert {:ok, env} = @middleware.call(%Env{url: "/users/:id", opts: opts}, [], nil)
      assert env.url == "/users/1"
    end

    test "URI-encodes path parameters with reserved characters" do
      opts = [path_params: [id: "user#1", post_id: "post#2"]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:id/p/:post_id", opts: opts}, [], nil)

      assert env.url == "/users/user%231/p/post%232"
    end
  end

  describe "OpenAPI-style params ({id})" do
    test "leaves the identifier with no parameters" do
      assert {:ok, env} = @middleware.call(%Env{url: "/users/{id}"}, [], nil)
      assert env.url == "/users/{id}"
    end

    test "replaces the identifier with passed params" do
      opts = [path_params: [id: 42]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/{id}", opts: opts}, [], nil)
      assert env.url == "/users/42"
    end

    test "replaces the identifier with empty passed params" do
      opts = [path_params: [id: ""]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/{id}", opts: opts}, [], nil)
      assert env.url == "/users/"
    end

    test "leaves the identifier if no value is given" do
      opts = [path_params: [y: 42]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/{x}", opts: opts}, [], nil)
      assert env.url == "/users/{x}"
    end

    test "leaves the identifier if the value is nil" do
      opts = [path_params: [id: nil]]
      assert {:ok, env} = @middleware.call(%Env{url: "/users/{id}", opts: opts}, [], nil)
      assert env.url == "/users/{id}"
    end

    test "leaves identifiers that start with a number" do
      opts = [path_params: ["1id": 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{1id}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/{1id}/p/2"
    end

    test "leaves identifiers that are a single digit" do
      opts = [path_params: ["1": 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{1}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/{1}/p/2"
    end

    test "replaces identifiers one character long" do
      opts = [path_params: [i: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{i}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "leaves identifiers that are only numbers" do
      opts = [path_params: ["123": 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{123}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/{123}/p/2"
    end

    test "leaves identifiers that start with underscore" do
      opts = [path_params: [_id: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{_id}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/{_id}/p/2"
    end

    test "leaves identifiers that start with dash" do
      opts = [path_params: ["-id": 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{-id}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/{-id}/p/2"
    end

    test "replaces any valid identifier" do
      opts = [path_params: [id_1_a: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{id_1_a}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "replaces any valid identifier with hyphens" do
      opts = [path_params: [id_1_a: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{id_1_a}/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "replaces identifiers that start with a capital letter" do
      opts = [path_params: [id_1_a: 1, IdPost: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{id_1_a}/p/{IdPost}", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "replaces identifiers where the path params is a struct" do
      opts = [path_params: %TestUser{id: 1}]

      assert {:ok, env} = @middleware.call(%Env{url: "/users/{id}", opts: opts}, [], nil)
      assert env.url == "/users/1"
    end

    test "URI-encodes path parameters with reserved characters" do
      opts = [path_params: [id: "user#1", post_id: "post#2"]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{id}/p/{post_id}", opts: opts}, [], nil)

      assert env.url == "/users/user%231/p/post%232"
    end
  end

  describe "Mixed params (not recommended, {id} and :id)" do
    test "replaces identifiers one character long" do
      opts = [path_params: [i: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/:i/p/{id_post}", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "replaces any valid identifier" do
      opts = [path_params: [id_1_a: 1, id_post: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{id_1_a}/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "replaces identifiers that start with a capital letter" do
      opts = [path_params: [id_1_a: 1, IdPost: 2]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{id_1_a}/p/:IdPost", opts: opts}, [], nil)

      assert env.url == "/users/1/p/2"
    end

    test "URI-encodes path parameters with reserved characters" do
      opts = [path_params: [id: "user#1", id_post: "post#2"]]

      assert {:ok, env} =
               @middleware.call(%Env{url: "/users/{id}/p/:id_post", opts: opts}, [], nil)

      assert env.url == "/users/user%231/p/post%232"
    end
  end
end
