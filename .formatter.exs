# Used by "mix format" and to export configuration.
export_locals_without_parens = [
  plug: 1,
  plug: 2,
  adapter: 1,
  adapter: 2
]

internal = [
  assert_cached: 1,
  refute_cached: 1
]

[
  inputs: [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "mix.exs"
  ],
  locals_without_parens: export_locals_without_parens ++ internal,
  export: [locals_without_parens: export_locals_without_parens]
]
