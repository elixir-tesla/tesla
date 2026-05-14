# Changelog

## [1.18.0](https://github.com/elixir-tesla/tesla/compare/v1.17.0...v1.18.0) (2026-05-14)


### Features

* **openapi:** add response wrapper macro ([#872](https://github.com/elixir-tesla/tesla/issues/872)) ([f824d67](https://github.com/elixir-tesla/tesla/commit/f824d672ea4524f4bba77ac3a2ea401dc7558b95))
* **openapi:** split header and cookie params ([#865](https://github.com/elixir-tesla/tesla/issues/865)) ([898bd1a](https://github.com/elixir-tesla/tesla/commit/898bd1adbf6f7067220e9084c23f85c1b2de7695))
* **path-params:** separate definitions from values ([#860](https://github.com/elixir-tesla/tesla/issues/860)) ([3639c9a](https://github.com/elixir-tesla/tesla/commit/3639c9a5e0b1303bfb305aad1dba45922e01694a))
* **path-params:** support precompiled path templates ([#859](https://github.com/elixir-tesla/tesla/issues/859)) ([a8878a0](https://github.com/elixir-tesla/tesla/commit/a8878a09d203c6972970155a1696cc6483a2b114))
* **query-params:** separate definitions from values ([#862](https://github.com/elixir-tesla/tesla/issues/862)) ([08f4d87](https://github.com/elixir-tesla/tesla/commit/08f4d8769bb990bc2dea3e8f9869ee8f62bee705))
* **query:** support API-specific query serialization ([#843](https://github.com/elixir-tesla/tesla/issues/843)) ([9b95efb](https://github.com/elixir-tesla/tesla/commit/9b95efb0d725b30a57643953f885edc4c9ca28b9))
* support OpenAPI-friendly cookie params ([#857](https://github.com/elixir-tesla/tesla/issues/857)) ([25bcf3c](https://github.com/elixir-tesla/tesla/commit/25bcf3c2d6f2a0ad6d2f700889ada0fe953b1351))
* support OpenAPI-friendly header params ([#853](https://github.com/elixir-tesla/tesla/issues/853)) ([2ec5539](https://github.com/elixir-tesla/tesla/commit/2ec5539ddd5838a7a07b3435b8b5808a55506420))
* support OpenAPI-friendly path params ([#851](https://github.com/elixir-tesla/tesla/issues/851)) ([0837672](https://github.com/elixir-tesla/tesla/commit/083767247780c4fc544c621ae1a14f46d8f8ad9a))
* support OpenAPI-friendly query params ([#852](https://github.com/elixir-tesla/tesla/issues/852)) ([7a1b582](https://github.com/elixir-tesla/tesla/commit/7a1b5826e6ab736d68824d2c278c57a225bed517))
* support OpenAPI-friendly query strings ([#858](https://github.com/elixir-tesla/tesla/issues/858)) ([a979142](https://github.com/elixir-tesla/tesla/commit/a979142b52b96822bde15751fa7e6cc916b58d20))


### Bug Fixes

* **gun:** keep timeout-wrapped streams readable ([#847](https://github.com/elixir-tesla/tesla/issues/847)) ([8a8ba74](https://github.com/elixir-tesla/tesla/commit/8a8ba747b06ab0f4487de8c584a335e9341e7ab0))
* **mint:** avoid crashes on HTTP/2 request resets ([#846](https://github.com/elixir-tesla/tesla/issues/846)) ([6a42469](https://github.com/elixir-tesla/tesla/commit/6a424699ab63e7413861cbda2d5824715340d6cc))

## [1.17.0](https://github.com/elixir-tesla/tesla/compare/v1.16.0...v1.17.0) (2026-04-18)


### Features

* Add :metadata option to Logger middleware ([#829](https://github.com/elixir-tesla/tesla/issues/829)) ([38e209a](https://github.com/elixir-tesla/tesla/commit/38e209a5a370160a723eb7a69665befdf9978b1a))
* add `assigns` and `private` fields to `Tesla.Env` ([#836](https://github.com/elixir-tesla/tesla/issues/836)) ([b8b622c](https://github.com/elixir-tesla/tesla/commit/b8b622ca1cd3104fd5d437bb3245d865d6af0b37))
* **client:** add put_middleware/2, replace_middleware!/3, update_middleware!/3, and insert_middleware!/4 ([#840](https://github.com/elixir-tesla/tesla/issues/840)) ([fa755c9](https://github.com/elixir-tesla/tesla/commit/fa755c97a24dbb4d542cffdad1bba8222053dbe1))
* **client:** add update_middleware/2 to transform middleware list ([#523](https://github.com/elixir-tesla/tesla/issues/523)) ([0689e64](https://github.com/elixir-tesla/tesla/commit/0689e64a3689bdbcb2a5921c1f3a1b32fb7f64c8))
* **logger:** emit url.template from KeepRequest preserved URL ([#839](https://github.com/elixir-tesla/tesla/issues/839)) ([544e1d7](https://github.com/elixir-tesla/tesla/commit/544e1d7473e54030315553a6534d7e291250009d))
* **logger:** semantic OTel metadata and legacy mode ([#838](https://github.com/elixir-tesla/tesla/issues/838)) ([aae0866](https://github.com/elixir-tesla/tesla/commit/aae0866c4e200858eb29789056bc90824c580be9))


### Bug Fixes

* avoid soft-deprecated warning logs when compiling tesla itself ([#834](https://github.com/elixir-tesla/tesla/issues/834)) ([ab82264](https://github.com/elixir-tesla/tesla/commit/ab822644006666702e1820625c96c60023a2a3e1))
* dialyzer spec for mock opts ([#831](https://github.com/elixir-tesla/tesla/issues/831)) ([440ec4e](https://github.com/elixir-tesla/tesla/commit/440ec4e442db3541b10f63a3da6235a5239fdab8))
* enhance response handling in Mint adapter ([#803](https://github.com/elixir-tesla/tesla/issues/803)) ([a672177](https://github.com/elixir-tesla/tesla/commit/a6721774e226ae48a9e3fc10f6592b595d5cde2f))
* include caller module name in `use Tesla` deprecation warning ([#832](https://github.com/elixir-tesla/tesla/issues/832)) ([b8fb158](https://github.com/elixir-tesla/tesla/commit/b8fb158f1ef5e2bebad7fd3b207738b1f4a3b9f6))
* **mint:** avoid active-mode message races without breaking reused connections ([#812](https://github.com/elixir-tesla/tesla/issues/812)) ([d812f54](https://github.com/elixir-tesla/tesla/commit/d812f543c905f53326899f38f687153f77551c44))

## [1.16.0](https://github.com/elixir-tesla/tesla/compare/v1.15.3...v1.16.0) (2026-01-01)


### Features

* add strict policy option for enforcing base URL ([#817](https://github.com/elixir-tesla/tesla/issues/817)) ([e476093](https://github.com/elixir-tesla/tesla/commit/e4760935caaca6f50b6e36a03ed3a5608eddb43f))
* support function streams in multipart handling ([#801](https://github.com/elixir-tesla/tesla/issues/801)) ([dd8b206](https://github.com/elixir-tesla/tesla/commit/dd8b206df618ec54082294d924eb15b0a8aafcb7)), closes [#648](https://github.com/elixir-tesla/tesla/issues/648)


### Bug Fixes

* DecompressResponse middleware for multiple encodings and keep updated content-length header ([#809](https://github.com/elixir-tesla/tesla/issues/809)) ([288699e](https://github.com/elixir-tesla/tesla/commit/288699e8f597e41ff07d8f620c21afb03ca69dd0))
* Handle breaking change in Finch.stream API ([#813](https://github.com/elixir-tesla/tesla/issues/813)) ([ce5ea80](https://github.com/elixir-tesla/tesla/commit/ce5ea80e8a244c7e15c9c4beb2a51ad55f332fe0))
* Handle errors in streaming responses ([#819](https://github.com/elixir-tesla/tesla/issues/819)) ([e7806bf](https://github.com/elixir-tesla/tesla/commit/e7806bf8252e4f05b3e2e64aab587ea20b03a9a9))
* Use Version module to check finch version ([#814](https://github.com/elixir-tesla/tesla/issues/814)) ([56f9568](https://github.com/elixir-tesla/tesla/commit/56f956818aa667c480171559c2897a8827256f28))

## [1.15.3](https://github.com/elixir-tesla/tesla/compare/v1.15.2...v1.15.3) (2025-07-30)


### Bug Fixes

* Avoid crash then gzip-decompressing empty body ([#796](https://github.com/elixir-tesla/tesla/issues/796)) ([5bc9b82](https://github.com/elixir-tesla/tesla/commit/5bc9b82823b3238257619ea3d67f0985a3707d2b))

## [1.15.2](https://github.com/elixir-tesla/tesla/compare/v1.15.1...v1.15.2) (2025-07-23)


### Bug Fixes

* suppress deprecation warning for :log_level option ([#794](https://github.com/elixir-tesla/tesla/issues/794)) ([478c16e](https://github.com/elixir-tesla/tesla/commit/478c16e79c7bad32bd70ffe51f52ad9dae071af6))
* suppress deprecation warning for :log_level option based on configuration ([478c16e](https://github.com/elixir-tesla/tesla/commit/478c16e79c7bad32bd70ffe51f52ad9dae071af6))

## [1.15.1](https://github.com/elixir-tesla/tesla/compare/v1.15.0...v1.15.1) (2025-07-23)


### Bug Fixes

* legacy log level handling to support atom values for backward compatibility ([5029174](https://github.com/elixir-tesla/tesla/commit/5029174d646a6f1d63088a8a947b4b44fb30b55f))

## [1.15.0](https://github.com/elixir-tesla/tesla/compare/v1.14.3...v1.15.0) (2025-07-22)


### Features

* add logging options to use `:level` instead of deprecated `:log_level` ([#779](https://github.com/elixir-tesla/tesla/issues/779)) ([ffc3609](https://github.com/elixir-tesla/tesla/commit/ffc36097409175f2e9b15abaffde29e8c3b52fe7))


### Bug Fixes

* Handle non-list term being emitted from Stream.chunk_while in SSE ([#788](https://github.com/elixir-tesla/tesla/issues/788)) ([0e9cf8d](https://github.com/elixir-tesla/tesla/commit/0e9cf8d30a8b3a4431bc69d2382afde2903f2499))

## [1.14.3](https://github.com/elixir-tesla/tesla/compare/v1.14.2...v1.14.3) (2025-06-02)


### Bug Fixes

* Handle carriage return \r line terminators in SSE ([1efe6e3](https://github.com/elixir-tesla/tesla/commit/1efe6e3fb426950697f4fcd7cda2bf9197ea4477))
* handle carriage return \r line terminators in SSE ([#772](https://github.com/elixir-tesla/tesla/issues/772)) ([1efe6e3](https://github.com/elixir-tesla/tesla/commit/1efe6e3fb426950697f4fcd7cda2bf9197ea4477))
* Handle named ancestors in Tesla.Mock ([#774](https://github.com/elixir-tesla/tesla/issues/774)) ([6cf380e](https://github.com/elixir-tesla/tesla/commit/6cf380e56ce04308a96d94c814e211aef063cf76))

## [1.14.2](https://github.com/elixir-tesla/tesla/compare/v1.14.1...v1.14.2) (2025-05-02)


### Bug Fixes

* bring back searching for mocks in ancestors ([#771](https://github.com/elixir-tesla/tesla/issues/771)) ([601e7b6](https://github.com/elixir-tesla/tesla/commit/601e7b69714acf63a6800945f66fa79a21d7d823))
* fix race condition in Tesla.Mock.agent_set ([8cf7745](https://github.com/elixir-tesla/tesla/commit/8cf7745179088ea96f5b4c7f2f05b2b7046b5677))
* handle HTTP response trailers when use Finch + stream ([#767](https://github.com/elixir-tesla/tesla/issues/767)) ([727cb0f](https://github.com/elixir-tesla/tesla/commit/727cb0f18369e7d307df5c051b2060c07477586a))
* move regexes out of module attributes to fix compatibility with OTP 28 ([#763](https://github.com/elixir-tesla/tesla/issues/763)) ([1196bc6](https://github.com/elixir-tesla/tesla/commit/1196bc600e30d0d9e38d72fcc6ccf1863054bb33))

## [1.14.1](https://github.com/elixir-tesla/tesla/compare/v1.14.0...v1.14.1) (2025-02-22)


### Bug Fixes

* add basic Hackney 1.22 support: {:connect_error, _} ([#754](https://github.com/elixir-tesla/tesla/issues/754)) ([127db9f](https://github.com/elixir-tesla/tesla/commit/127db9f0f4632cf290ce76d61bd1407367676266)), closes [#753](https://github.com/elixir-tesla/tesla/issues/753)

## [1.14.0](https://github.com/elixir-tesla/tesla/compare/v1.13.2...v1.14.0) (2025-02-03)


### Features

* release-please and conventional commit ([#719](https://github.com/elixir-tesla/tesla/issues/719)) ([c9f6a1c](https://github.com/elixir-tesla/tesla/commit/c9f6a1c917d707e849d51a09557b453a8f9f012f))
* support retry-after header in retry middleware ([#639](https://github.com/elixir-tesla/tesla/issues/639)) ([86ad37d](https://github.com/elixir-tesla/tesla/commit/86ad37dec511ca00047a2640510a4c6c92acf636))
* Tesla.Middleware.JSON: Add support for Elixir 1.18's JSON module ([#747](https://github.com/elixir-tesla/tesla/issues/747)) ([1413167](https://github.com/elixir-tesla/tesla/commit/1413167f5408585405b8812f307897a6501b693a))


### Bug Fixes

* mocks for supervised tasks ([#750](https://github.com/elixir-tesla/tesla/issues/750)) ([2f6b2a6](https://github.com/elixir-tesla/tesla/commit/2f6b2a646c9bff3888b7aa0f4fc4440a2b5c97ee))
