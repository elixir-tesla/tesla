# Changelog

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
