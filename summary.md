# Tesla 1.18.0 Release Summary

This release adds OpenAPI-friendly parameter serialization primitives for
generated and hand-written clients, plus focused adapter fixes and release
automation updates.

## OpenAPI Parameter Support

- Added OpenAPI-friendly path parameters with explicit `:simple`, `:matrix`,
  and `:label` serialization through `Tesla.OpenAPI.PathParam`,
  `Tesla.OpenAPI.PathParams`, and `Tesla.Middleware.PathParams` `:modern`
  mode. (#851)
- Added OpenAPI-friendly query parameters with `:form`, `:space_delimited`,
  `:pipe_delimited`, and `:deep_object` serialization through
  `Tesla.OpenAPI.QueryParam`, `Tesla.OpenAPI.QueryParams`, and
  `Tesla.Middleware.Query` `:modern` mode. (#852, #843)
- Added OpenAPI-friendly header parameter serialization through
  `Tesla.OpenAPI.HeaderParam` and `Tesla.OpenAPI.HeaderParams`. (#853)
- Added OpenAPI-friendly cookie parameter serialization through
  `Tesla.OpenAPI.CookieParam` and `Tesla.OpenAPI.CookieParams`. (#857)
- Added `Tesla.OpenAPI.QueryString` for OpenAPI `in: "querystring"`
  operations, where the entire URL query string is provided as one serialized
  value. (#858)
- Added `Tesla.OpenAPI.PathTemplate` so generated clients can precompile
  OpenAPI path templates once and reuse the parsed representation through
  request private data. (#859)
- Split static parameter definitions from per-request values for path and query
  parameters, matching generated-client usage where operation metadata is
  module-level and request values are dynamic. (#860, #862)
- Moved the public OpenAPI APIs under the `Tesla.OpenAPI` namespace and added
  `Tesla.OpenAPI.merge_private/1` for composing generated request private
  metadata. (#863, #864)
- Split header and cookie collection modules into first-class APIs and
  simplified parameter collection internals. (#865, #866)
- Added a Benchee benchmark that measures the generated-operation-shaped
  OpenAPI middleware path. (#867)

## Documentation

- Added the OpenAPI parameter how-to guide for generated operation modules,
  including path, query, header, cookie, response, client stack, and API module
  examples. (#861)
- Added the OpenAPI explanation guide covering parameter locations, querystring
  behavior, and OpenAPI-to-Tesla field mapping. (#861)
- Added module reference docs for the `Tesla.OpenAPI` namespace and each
  parameter value object/collection.
- Clarified `Tesla.Env` URL ownership. (#845)

## Adapter Fixes

- Fixed Mint HTTP/2 handling so request reset frames do not crash the adapter.
  (#846)
- Fixed Gun timeout-wrapped streaming so streams remain readable after timeout
  middleware wraps the request. (#847)

## Internal Cleanup

- Shared common parameter validation and encoding helpers across OpenAPI
  parameter modules. (#854)
- Removed eager parameter pair normalization and clarified parameter value
  shape handling. (#855, #856)

## Tooling

- Updated release automation and conventional-commit workflow dependencies.
  (#849, #850)
