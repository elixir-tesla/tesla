Tesla
=====


## Example API client

```ex
defmodule GitHub do
  use Tesla

  with Tesla.Middleware.BaseUrl, "https://api.github.com"
  with Tesla.Middleware.Headers, [{"Authorization", "xyz"}]
  with Tesla.Middleware.EncodeJson
  with Tesla.Middleware.DecodeJson

  adapter Tesla.Adapter.Ibrowse
end
```


```ex
# Start ibrowse
Tesla.Adapter.Ibrowse.start

# Get user repos
GitHub.get("/user/teamon/repos")
```
