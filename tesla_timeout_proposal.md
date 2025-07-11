# Tesla Adapter Timeout Option Proposal

## Overview

This proposal addresses [Issue #255](https://github.com/elixir-tesla/tesla/issues/255) by adding a standardized `:timeout` option to all Tesla adapters. This will provide a consistent interface for request timeouts while avoiding the issues with the current `Tesla.Middleware.Timeout`.

## Problem Statement

The current `Tesla.Middleware.Timeout` has several issues:
1. **Breaks `Tesla.Mock`**: Uses `Task` which interferes with mocking
2. **Overrides adapter-specific timeouts**: Can conflict with underlying HTTP library timeouts
3. **Different semantics**: Middleware timeout wraps the entire request/response cycle, while adapter timeouts are more granular

## Solution

### 1. Add `:timeout` Option to Adapter Specification

Update `lib/tesla/adapter.ex` to include `:timeout` in the adapter specification:

```elixir
@doc """
Common adapter options supported by all adapters:

- `:timeout` - Request timeout in milliseconds. This timeout applies to the entire
  request/response cycle and will be handled by the adapter's underlying HTTP library.
  If not specified, each adapter will use its own default timeout.

Adapter-specific options may also be available. See individual adapter documentation
for details.
"""
```

### 2. Implementation Strategy per Adapter

#### 2.1 Tesla.Adapter.Finch
- **Current**: Uses `:receive_timeout` (15_000ms default)
- **Change**: Map `:timeout` to `:receive_timeout` if provided
- **Backward compatibility**: Keep existing `:receive_timeout` support

```elixir
@impl Tesla.Adapter
def call(%Tesla.Env{} = env, opts) do
  opts = Tesla.Adapter.opts(@defaults, env, opts)
  
  # Map :timeout to :receive_timeout if provided
  opts = case Keyword.get(opts, :timeout) do
    nil -> opts
    timeout -> Keyword.put_new(opts, :receive_timeout, timeout)
  end
  
  # ... rest of implementation
end
```

#### 2.2 Tesla.Adapter.Hackney
- **Current**: No explicit timeout option
- **Change**: Map `:timeout` to `:recv_timeout` (hackney's option)
- **Default**: Use 30_000ms to match other adapters

```elixir
@impl Tesla.Adapter
def call(env, opts) do
  opts = Tesla.Adapter.opts(@defaults, env, opts)
  
  # Map :timeout to :recv_timeout if provided
  opts = case Keyword.get(opts, :timeout) do
    nil -> opts
    timeout -> Keyword.put(opts, :recv_timeout, timeout)
  end
  
  # ... rest of implementation
end
```

#### 2.3 Tesla.Adapter.Httpc
- **Current**: Uses `:timeout` option
- **Change**: Already supports `:timeout` - no changes needed
- **Default**: Keep current behavior (no default timeout)

#### 2.4 Tesla.Adapter.Ibrowse
- **Current**: Uses `:timeout` option (30_000ms default)
- **Change**: Already supports `:timeout` - no changes needed
- **Default**: Keep current 30_000ms default

#### 2.5 Tesla.Adapter.Mint
- **Current**: Uses `:timeout` option (2_000ms default)
- **Change**: Already supports `:timeout` - no changes needed
- **Default**: Keep current 2_000ms default

#### 2.6 Tesla.Adapter.Gun
- **Current**: Uses `:timeout` option (1_000ms default)
- **Change**: Already supports `:timeout` - no changes needed
- **Default**: Keep current 1_000ms default

### 3. Documentation Updates

#### 3.1 Adapter Documentation
Update each adapter's moduledoc to include `:timeout` option:

```elixir
## Common Options

- `:timeout` - Request timeout in milliseconds. [adapter-specific details]

## Adapter Specific Options

[existing adapter-specific options]
```

#### 3.2 Main Tesla Documentation
Update the main Tesla documentation to recommend `:timeout` option over `Tesla.Middleware.Timeout`:

```elixir
# Recommended: Use adapter-level timeout
client = Tesla.client([], {Tesla.Adapter.Finch, name: MyFinch, timeout: 5000})

# Alternative: Use middleware timeout for complex retry scenarios
client = Tesla.client([
  {Tesla.Middleware.Retry, delay: 1000, max_retries: 3},
  {Tesla.Middleware.Timeout, timeout: 10000}  # Covers all retry attempts
], {Tesla.Adapter.Finch, name: MyFinch})
```

### 4. Migration Guide

#### 4.1 From Timeout Middleware to Adapter Timeout

```elixir
# Before
defmodule MyClient do
  def client do
    Tesla.client([
      {Tesla.Middleware.Timeout, timeout: 5000}
    ], Tesla.Adapter.Finch)
  end
end

# After
defmodule MyClient do
  def client do
    Tesla.client([], {Tesla.Adapter.Finch, timeout: 5000})
  end
end
```

#### 4.2 Per-Request Timeout

```elixir
# Using adapter options
Tesla.get(client, "/path", opts: [adapter: [timeout: 1000]])
```

### 5. Testing Strategy

#### 5.1 Unit Tests
- Test `:timeout` option works for each adapter
- Test backward compatibility with existing timeout options
- Test timeout behavior with various scenarios

#### 5.2 Integration Tests
- Test with `Tesla.Mock` to ensure no interference
- Test timeout behavior with real HTTP requests
- Test interaction with retry middleware

### 6. Implementation Plan

#### Phase 1: Core Implementation
1. Update `Tesla.Adapter` specification
2. Implement `:timeout` support in Finch and Hackney adapters
3. Add comprehensive unit tests

#### Phase 2: Documentation and Examples
1. Update adapter documentation
2. Update main Tesla documentation
3. Add migration guide
4. Update examples in README

#### Phase 3: Deprecation (Future)
1. Add deprecation warnings for `Tesla.Middleware.Timeout` in common cases
2. Provide migration path in warnings
3. Consider eventual removal in major version

### 7. Backward Compatibility

- All existing timeout options remain supported
- `:timeout` option takes precedence over adapter-specific options when both are provided
- `Tesla.Middleware.Timeout` continues to work as before
- No breaking changes to existing APIs

### 8. Benefits

1. **Consistent Interface**: All adapters support the same `:timeout` option
2. **Better Mock Support**: Avoids Task-based implementation issues
3. **Adapter-Native**: Uses underlying HTTP library's timeout mechanisms
4. **Flexible**: Still allows adapter-specific timeout options
5. **Backward Compatible**: No breaking changes to existing code

### 9. Example Usage

```elixir
# Global timeout configuration
config :tesla, :adapter, {Tesla.Adapter.Finch, name: MyFinch, timeout: 5000}

# Per-client timeout
client = Tesla.client([], {Tesla.Adapter.Hackney, timeout: 10000})

# Per-request timeout
Tesla.get(client, "/api/data", opts: [adapter: [timeout: 2000]])

# Complex scenario with retry
client = Tesla.client([
  {Tesla.Middleware.Retry, delay: 1000, max_retries: 3},
  {Tesla.Middleware.Timeout, timeout: 30000}  # Total timeout for all attempts
], {Tesla.Adapter.Finch, name: MyFinch, timeout: 5000})  # Per-request timeout
```

### 10. Future Considerations

- Consider adding `:connect_timeout` option for connection-specific timeouts
- Explore adding timeout events to telemetry
- Consider adapter-agnostic timeout defaults in future versions

---

This proposal provides a path to resolve the long-standing timeout issues in Tesla while maintaining backward compatibility and providing a consistent interface across all adapters.