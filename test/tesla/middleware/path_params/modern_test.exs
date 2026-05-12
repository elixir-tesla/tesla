defmodule Tesla.Middleware.PathParams.ModernTest do
  use ExUnit.Case, async: true

  alias Tesla.Env
  alias Tesla.PathParam
  alias Tesla.PathTemplate

  @middleware Tesla.Middleware.PathParams

  defmodule TestUser do
    defstruct [:id]
  end

  defp path_param(value), do: PathParam.new!("id", value)
  defp path_param(name, value) when is_binary(name), do: PathParam.new!(name, value)
  defp path_param(value, opts) when is_list(opts), do: PathParam.new!("id", value, opts)
  defp path_param(name, value, opts), do: PathParam.new!(name, value, opts)

  defp path_template_private(template) do
    PathTemplate.put_private(template)
  end

  describe "mode: :modern — simple style" do
    test "primitive (explode false) renders raw value" do
      opts = [path_params: [path_param(5, style: :simple, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/5"
    end

    test "primitive (explode true) renders raw value" do
      opts = [path_params: [path_param(5, style: :simple, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/5"
    end

    test "array (explode false) is comma-joined" do
      opts = [path_params: [path_param([3, 4, 5], style: :simple, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/3,4,5"
    end

    test "array (explode true) is also comma-joined" do
      opts = [path_params: [path_param([3, 4, 5], style: :simple, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/3,4,5"
    end

    test "object (explode false) flattens key-value pairs with commas" do
      opts = [
        path_params: [
          path_param([role: "admin", firstName: "Alex"], style: :simple, explode: false)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/role,admin,firstName,Alex"
    end

    test "object (explode true) joins key=value with commas" do
      opts = [
        path_params: [
          path_param([role: "admin", firstName: "Alex"], style: :simple, explode: true)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/role=admin,firstName=Alex"
    end
  end

  describe "mode: :modern — matrix style" do
    test "primitive renders ;name=value" do
      opts = [path_params: [path_param(5, style: :matrix, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;id=5"
    end

    test "array (explode false) renders ;name=v1,v2,v3" do
      opts = [path_params: [path_param([3, 4, 5], style: :matrix, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;id=3,4,5"
    end

    test "array (explode true) repeats ;name=v" do
      opts = [path_params: [path_param([3, 4, 5], style: :matrix, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;id=3;id=4;id=5"
    end

    test "object (explode false) renders ;name=k1,v1,k2,v2" do
      opts = [
        path_params: [
          path_param([role: "admin", firstName: "Alex"], style: :matrix, explode: false)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;id=role,admin,firstName,Alex"
    end

    test "object (explode true) renders ;k1=v1;k2=v2 (no name prefix)" do
      opts = [
        path_params: [
          path_param([role: "admin", firstName: "Alex"], style: :matrix, explode: true)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;role=admin;firstName=Alex"
    end
  end

  describe "mode: :modern — label style" do
    test "primitive renders .value" do
      opts = [path_params: [path_param(5, style: :label, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/.5"
    end

    test "array (explode false) renders .v1,v2,v3" do
      opts = [path_params: [path_param([3, 4, 5], style: :label, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/.3,4,5"
    end

    test "array (explode true) renders .v1.v2.v3" do
      opts = [path_params: [path_param([3, 4, 5], style: :label, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/.3.4.5"
    end

    test "object (explode false) flattens key-value pairs with commas" do
      opts = [
        path_params: [
          path_param([role: "admin", firstName: "Alex"], style: :label, explode: false)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/.role,admin,firstName,Alex"
    end

    test "object (explode true) joins key=value with dots" do
      opts = [
        path_params: [
          path_param([role: "admin", firstName: "Alex"], style: :label, explode: true)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/.role=admin.firstName=Alex"
    end
  end

  describe "mode: :modern — OpenAPI specification style examples" do
    spec_examples = [
      {"matrix explode=false string", :matrix, false, "blue", ";color=blue"},
      {"matrix explode=false array", :matrix, false, ["blue", "black", "brown"],
       ";color=blue,black,brown"},
      {"matrix explode=false object", :matrix, false, [R: 100, G: 200, B: 150],
       ";color=R,100,G,200,B,150"},
      {"matrix explode=true string", :matrix, true, "blue", ";color=blue"},
      {"matrix explode=true array", :matrix, true, ["blue", "black", "brown"],
       ";color=blue;color=black;color=brown"},
      {"matrix explode=true object", :matrix, true, [R: 100, G: 200, B: 150],
       ";R=100;G=200;B=150"},
      {"label explode=false string", :label, false, "blue", ".blue"},
      {"label explode=false array", :label, false, ["blue", "black", "brown"],
       ".blue,black,brown"},
      {"label explode=false object", :label, false, [R: 100, G: 200, B: 150],
       ".R,100,G,200,B,150"},
      {"label explode=true string", :label, true, "blue", ".blue"},
      {"label explode=true array", :label, true, ["blue", "black", "brown"], ".blue.black.brown"},
      {"label explode=true object", :label, true, [R: 100, G: 200, B: 150], ".R=100.G=200.B=150"},
      {"simple explode=false string", :simple, false, "blue", "blue"},
      {"simple explode=false array", :simple, false, ["blue", "black", "brown"],
       "blue,black,brown"},
      {"simple explode=false object", :simple, false, [R: 100, G: 200, B: 150],
       "R,100,G,200,B,150"},
      {"simple explode=true string", :simple, true, "blue", "blue"},
      {"simple explode=true array", :simple, true, ["blue", "black", "brown"],
       "blue,black,brown"},
      {"simple explode=true object", :simple, true, [R: 100, G: 200, B: 150], "R=100,G=200,B=150"}
    ]

    for {name, style, explode, value, expected} <- spec_examples do
      test name do
        opts = [
          path_params: [
            path_param("color", unquote(Macro.escape(value)),
              style: unquote(style),
              explode: unquote(explode)
            )
          ]
        ]

        assert {:ok, env} =
                 @middleware.call(
                   %Env{url: "/users/{color}", opts: opts},
                   [],
                   mode: :modern
                 )

        assert env.url == "/users/" <> unquote(expected)
      end
    end
  end

  describe "mode: :modern — OpenAPI undefined value examples" do
    undefined_examples = [
      {"matrix explode=false empty array", :matrix, false, [], ";color"},
      {"matrix explode=true empty array", :matrix, true, [], ";color"},
      {"matrix explode=false empty object", :matrix, false, %{}, ";color"},
      {"matrix explode=true empty object", :matrix, true, %{}, ";color"},
      {"label explode=false empty array", :label, false, [], "."},
      {"label explode=true empty array", :label, true, [], "."},
      {"label explode=false empty object", :label, false, %{}, "."},
      {"label explode=true empty object", :label, true, %{}, "."},
      {"simple explode=false empty array", :simple, false, [], ""},
      {"simple explode=true empty array", :simple, true, [], ""},
      {"simple explode=false empty object", :simple, false, %{}, ""},
      {"simple explode=true empty object", :simple, true, %{}, ""}
    ]

    for {name, style, explode, value, expected} <- undefined_examples do
      test name do
        opts = [
          path_params: [
            path_param("color", unquote(Macro.escape(value)),
              style: unquote(style),
              explode: unquote(explode)
            )
          ]
        ]

        assert {:ok, env} =
                 @middleware.call(
                   %Env{url: "/users/{color}", opts: opts},
                   [],
                   mode: :modern
                 )

        assert env.url == "/users/" <> unquote(expected)
      end
    end
  end

  describe "mode: :modern — OpenAPI path template names" do
    test "replaces template names that start with a number" do
      opts = [path_params: [path_param("1color", "blue")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{1color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/blue"
    end

    test "replaces template names that start with an underscore" do
      opts = [path_params: [path_param("_color", "blue")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{_color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/blue"
    end

    test "replaces template names that start with a dash" do
      opts = [path_params: [path_param("-color", "blue")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{-color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/blue"
    end

    test "replaces template names containing path-template punctuation" do
      opts = [path_params: [path_param("color.name+shade", "blue")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color.name+shade}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/blue"
    end

    test "matches path template names case-sensitively" do
      opts = [
        path_params: [
          path_param("id", "lower"),
          path_param("Id", "upper")
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}/{Id}/{ID}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/lower/upper/{ID}"
    end

    test "replaces repeated template expressions with the same parameter value" do
      opts = [path_params: [path_param("id", "blue")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}/related/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/blue/related/blue"
    end

    test "percent-encodes non-RFC6570 template names when the name is serialized" do
      opts = [path_params: [path_param("color name", "blue", style: :matrix)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color name}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;color%20name=blue"
    end

    test "leaves empty template expressions untouched" do
      opts = [path_params: [path_param("", "blue")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{}"
    end
  end

  describe "mode: :modern — precompiled OpenAPI path templates" do
    test "uses a matching path template from private data" do
      template = PathTemplate.new!("/users/{id}{coords}")

      opts = [
        path_params: [
          path_param(5),
          path_param("coords", ["blue", "black"], style: :matrix, explode: true)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{
                   url: template.path,
                   private: path_template_private(template),
                   opts: opts
                 },
                 [],
                 mode: :modern
               )

      assert env.url == "/users/5;coords=blue;coords=black"
    end

    test "preserves missing and nil template expressions" do
      template = PathTemplate.new!("/users/{id}/{missing}")
      opts = [path_params: [path_param(nil)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{
                   url: template.path,
                   private: path_template_private(template),
                   opts: opts
                 },
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{id}/{missing}"
    end

    test "falls back when private path template does not match the request path" do
      template = PathTemplate.new!("/other/{id}")
      opts = [path_params: [path_param(42)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{
                   url: "/users/{id}",
                   private: path_template_private(template),
                   opts: opts
                 },
                 [],
                 mode: :modern
               )

      assert env.url == "/users/42"
    end

    test "falls back when private path template data is invalid" do
      opts = [path_params: [path_param(42)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{
                   url: "/users/{id}",
                   private: %{tesla_path_template: :invalid},
                   opts: opts
                 },
                 [],
                 mode: :modern
               )

      assert env.url == "/users/42"
    end
  end

  describe "mode: :modern — OpenAPI path serialization limits" do
    for style <- [:form, :space_delimited, :pipe_delimited, :deep_object, :cookie] do
      test "rejects non-path style #{style}" do
        assert_raise ArgumentError, ~r/expected :simple, :matrix, or :label/, fn ->
          path_param("color", "blue", style: unquote(style))
        end
      end
    end
  end

  describe "mode: :modern — OpenAPI percent encoding" do
    spec_path_examples = [
      {"Edsger Dijkstra", "edijkstra", "edijkstra"},
      {"Diṅnāga", "diṅnāga", "di%E1%B9%85n%C4%81ga"},
      {"Al-Khwarizmi", "الخوارزميّ",
       "%D8%A7%D9%84%D8%AE%D9%88%D8%A7%D8%B1%D8%B2%D9%85%D9%8A%D9%91"}
    ]

    for {name, value, expected} <- spec_path_examples do
      test "OpenAPI path example #{name}" do
        opts = [path_params: [path_param("username", unquote(value))]]

        assert {:ok, env} =
                 @middleware.call(
                   %Env{url: "/users/{username}", opts: opts},
                   [],
                   mode: :modern
                 )

        assert env.url == "/users/" <> unquote(expected)
      end
    end

    empty_string_examples = [
      {"simple empty string", :simple, ""},
      {"matrix empty string", :matrix, ";color="},
      {"label empty string", :label, "."}
    ]

    for {name, style, expected} <- empty_string_examples do
      test "#{name} follows primitive serialization" do
        opts = [path_params: [path_param("color", "", style: unquote(style))]]

        assert {:ok, env} =
                 @middleware.call(
                   %Env{url: "/users/{color}", opts: opts},
                   [],
                   mode: :modern
                 )

        assert env.url == "/users/" <> unquote(expected)
      end
    end

    test "encodes path-forbidden generic syntax characters" do
      opts = [path_params: [path_param("color", "a/b?c#d")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/a%2Fb%3Fc%23d"
    end

    test "encodes delimiter characters inside non-reserved array values" do
      opts = [path_params: [path_param("color", ["blue,green", "black"], style: :simple)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/blue%2Cgreen,black"
    end

    test "encodes delimiter characters inside non-reserved object values" do
      opts = [
        path_params: [
          path_param("color", [R: "100,200", G: "x+y"], style: :matrix, explode: true)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;R=100%2C200;G=x%2By"
    end

    test "allowReserved keeps path-legal reserved characters" do
      opts = [
        path_params: [path_param("color", "x+y:@", style: :simple, allow_reserved: true)]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/x+y:@"
    end

    test "allowReserved still encodes generic syntax characters forbidden in path values" do
      opts = [
        path_params: [path_param("color", "a/b?c#d", style: :simple, allow_reserved: true)]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/a%2Fb%3Fc%23d"
    end

    test "allowReserved preserves existing percent-encoded octets" do
      opts = [
        path_params: [path_param("color", "x%2By", style: :simple, allow_reserved: true)]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/x%2By"
    end

    test "allowReserved encodes percent signs outside percent-encoded octets" do
      opts = [
        path_params: [path_param("color", "x%2G%", style: :simple, allow_reserved: true)]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/x%252G%25"
    end

    test "allowReserved still encodes characters that are not valid path output" do
      opts = [
        path_params: [path_param("color", "[x]| y", style: :simple, allow_reserved: true)]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/%5Bx%5D%7C%20y"
    end
  end

  describe "mode: :modern — encoding & edge cases" do
    test "leaves URL untouched when no path_params are provided" do
      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}"},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{id}"
    end

    test "percent-encodes reserved characters per RFC 3986" do
      opts = [path_params: [path_param("a/b c#d")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/a%2Fb%20c%23d"
    end

    test "spaces become %20 (not +)" do
      opts = [path_params: [path_param("John Smith")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/John%20Smith"
    end

    test "leaves placeholder when value is missing" do
      opts = [path_params: [path_param("other", 1)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{id}"
    end

    test "leaves placeholder when PathParam value is nil" do
      opts = [path_params: [path_param(nil)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{id}"
    end

    test "serializes empty array as OpenAPI undefined" do
      opts = [path_params: [path_param([])]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/"
    end

    test "serializes empty object as OpenAPI undefined" do
      opts = [path_params: [path_param(%{})]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/"
    end

    test "PathParam value uses defaults (style: :simple, explode: false)" do
      opts = [path_params: [path_param(42)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/42"
    end

    test "PathParam opts default :explode to false when omitted" do
      opts = [path_params: [path_param([3, 4, 5], style: :matrix)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;id=3,4,5"
    end

    test "PathParam opts default :style to :simple when omitted" do
      opts = [path_params: [path_param([3, 4, 5], explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/3,4,5"
    end

    test "rejects unknown PathParam option keys" do
      assert_raise ArgumentError, ~r/unknown keys \[:future_field\]/, fn ->
        path_param(5, style: :simple, explode: false, future_field: :foo)
      end
    end

    test "accepts struct as object value" do
      opts = [path_params: [path_param(%TestUser{id: 7}, style: :simple, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/id=7"
    end

    test "accepts quoted atom keyword lists as object values" do
      opts = [
        path_params: [
          path_param("color", [R: 100, G: 200], style: :simple, explode: false)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/R,100,G,200"
    end

    test "accepts string-keyed maps as object values" do
      opts = [
        path_params: [
          path_param("color", %{"R" => 100}, style: :simple, explode: true)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{color}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/R=100"
    end

    test "supports list-shaped path_params" do
      opts = [
        path_params: [
          path_param(5),
          path_param("coords", ["blue", "black"], style: :matrix, explode: true)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/items/{id}{coords}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/items/5;coords=blue;coords=black"
    end

    test "supports named PathParam structs" do
      opts = [path_params: [path_param(42)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/42"
    end

    test "raises on duplicate PathParam names" do
      opts = [path_params: [path_param(1), path_param(2)]]

      assert_raise ArgumentError, ~r/duplicate path parameter "id" in modern mode/, fn ->
        @middleware.call(
          %Env{url: "/users/{id}", opts: opts},
          [],
          mode: :modern
        )
      end
    end

    test "does not treat maps as modern path_params" do
      opts = [path_params: %{"id" => path_param(42)}]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{id}"
    end

    test "ignores struct-shaped outer containers" do
      opts = [path_params: %TestUser{id: path_param(7)}]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{id}"
    end

    test "leaves Phoenix-style placeholders untouched" do
      opts = [path_params: [path_param([3, 4, 5], style: :matrix, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/:id", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/:id"
    end

    test "raises on unsupported style atom" do
      assert_raise ArgumentError, ~r/expected :simple, :matrix, or :label/, fn ->
        path_param(5, style: :form, explode: false)
      end
    end

    test "expands multiple placeholders in one URL" do
      opts = [
        path_params: [
          path_param(5),
          path_param("coords", ["blue", "black"], style: :matrix, explode: true),
          path_param("tags", ["a", "b", "c"], style: :label, explode: false)
        ]
      ]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/items/{id}{coords}{tags}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/items/5;coords=blue;coords=black.a,b,c"
    end

    test "leaves URL untouched when path_params is an unsupported type" do
      opts = [path_params: 42]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/{id}"
    end

    test "raises when list entries are not PathParam structs" do
      opts = [path_params: [id: path_param(42)]]

      assert_raise ArgumentError,
                   ~r/expected path_params to be a list of Tesla.PathParam structs in modern mode/,
                   fn ->
                     @middleware.call(
                       %Env{url: "/users/{id}", opts: opts},
                       [],
                       mode: :modern
                     )
                   end
    end

    test "raises when modern path_params value is not a PathParam" do
      opts = [path_params: [42]]

      assert_raise ArgumentError,
                   ~r/expected path_params to be a list of Tesla.PathParam structs in modern mode/,
                   fn ->
                     @middleware.call(
                       %Env{url: "/users/{id}", opts: opts},
                       [],
                       mode: :modern
                     )
                   end
    end

    test "raises when modern path_params value is an option map instead of a PathParam" do
      opts = [path_params: [%{style: :simple}]]

      assert_raise ArgumentError,
                   ~r/expected path_params to be a list of Tesla.PathParam structs in modern mode/,
                   fn ->
                     @middleware.call(
                       %Env{url: "/users/{id}", opts: opts},
                       [],
                       mode: :modern
                     )
                   end
    end

    test "raises when modern path_params value is a struct instead of a PathParam" do
      opts = [path_params: [%TestUser{id: 7}]]

      assert_raise ArgumentError,
                   ~r/expected path_params to be a list of Tesla.PathParam structs in modern mode/,
                   fn ->
                     @middleware.call(
                       %Env{url: "/users/{id}", opts: opts},
                       [],
                       mode: :modern
                     )
                   end
    end

    test "matrix style: empty array serializes as OpenAPI undefined" do
      opts = [path_params: [path_param([], style: :matrix, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;id"
    end

    test "matrix style: empty object serializes as OpenAPI undefined" do
      opts = [path_params: [path_param(%{}, style: :matrix, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/;id"
    end

    test "label style: empty array serializes as OpenAPI undefined" do
      opts = [path_params: [path_param([], style: :label, explode: true)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/."
    end

    test "label style: empty object serializes as OpenAPI undefined" do
      opts = [path_params: [path_param(%{}, style: :label, explode: false)]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/."
    end

    test "RFC 3986 unreserved set (-, _, ., ~) is kept as-is" do
      opts = [path_params: [path_param("a-b_c.d~e")]]

      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: opts},
                 [],
                 mode: :modern
               )

      assert env.url == "/users/a-b_c.d~e"
    end

    test "uses legacy behavior unless modern mode is matched" do
      assert {:ok, env} =
               @middleware.call(
                 %Env{url: "/users/{id}", opts: [path_params: [id: 1]]},
                 [],
                 mode: :foo
               )

      assert env.url == "/users/1"
    end
  end
end
