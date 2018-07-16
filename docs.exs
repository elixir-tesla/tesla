[
  main: "readme",
  extras: ["README.md"],
  groups_for_modules: [
    Behaviours: [
      Tesla.Adapter,
      Tesla.Middleware
    ],
    Adapters: [
      Tesla.Adapter.Hackney,
      Tesla.Adapter.Httpc,
      Tesla.Adapter.Ibrowse
    ],
    Middlewares: [
      Tesla.Middleware.BaseUrl,
      Tesla.Middleware.BasicAuth,
      Tesla.Middleware.CompressRequest,
      Tesla.Middleware.Compression,
      Tesla.Middleware.DecodeJson,
      Tesla.Middleware.DecodeRels,
      Tesla.Middleware.DecompressResponse,
      Tesla.Middleware.DigestAuth,
      Tesla.Middleware.EncodeJson,
      Tesla.Middleware.FollowRedirects,
      Tesla.Middleware.FormUrlencoded,
      Tesla.Middleware.Fuse,
      Tesla.Middleware.Headers,
      Tesla.Middleware.JSON,
      Tesla.Middleware.KeepRequest,
      Tesla.Middleware.Logger,
      Tesla.Middleware.MethodOverride,
      Tesla.Middleware.Opts,
      Tesla.Middleware.Query,
      Tesla.Middleware.Retry,
      Tesla.Middleware.Timeout
    ]
  ]
]
