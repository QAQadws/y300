# Migration guide

## 0.2.x to 0.3.0

Use `buildStandardClient()` for new integrations:

```dart
final client = YamiboForumClientBuilder.standardDio(
  config: config,
  cookies: persistentCookies,
  caches: cachePorts,
  waf: platformWafDelegate,
).buildStandardClient();
```

`buildStandardReads()` is deprecated but delegates to the same composition.
The standard client now installs independent password-login, session, and
logout contracts. Consume `DataCommandResult` exhaustively: an
`outcomeUnknown` command may already have changed server state and must never
be treated as a rollback.

Advanced Host-transport integrations must provide `cookieStore` to
`YamiboForumClientBuilder` to enable authentication commands. Without it,
reads remain available while login/logout return `unsupported`.

Custom `ForumFormhashProvider` implementations must accept the new optional
`cancellation` argument. Providers should pass it to their network request so
a Host login timeout can stop formhash preparation before credentials are
submitted.

`ForumSessionSnapshot.formhashUpdatedAt` is optional for backward-compatible
Host stores. New implementations should preserve it when merging a response
that contains no new formhash. The old `updatedAt` value is used only when the
dedicated timestamp is absent.

Only the standard `action=logout&formhash=...` protocol is used in 0.3.0. Any
Host dependency on the former `mlogout/hash` fallback must be removed.

## 0.1.x to 0.2.0

Existing custom Host integrations remain source-compatible:

```dart
YamiboForumClientBuilder(
  config: config,
  network: hostNetwork,
  sessionStore: hostSession,
  documentStore: documents,
  snapshotStore: snapshots,
  formhashProvider: hostFormhash,
).buildStandardReads();
```

Third-party clients without an existing transport should migrate to the
supported standard runtime:

```dart
YamiboForumClientBuilder.standardDio(
  config: config,
  cookies: persistentCookies,
  caches: ForumClientCachePorts(
    documents: persistentDocuments,
    snapshots: persistentSnapshots,
    stickers: persistentStickers,
  ),
  waf: platformWafDelegate,
).buildStandardReads();
```

The standard runtime now installs search without a custom formhash provider.
It reads formhash from `profile`, falls back to `forumindex`, and stores the
result in a package-owned in-memory session projection. Authentication still
comes from the persistent Cookie store.

`ForumClientSourcePlan` and concrete adapters are now explicitly experimental.
Code that only consumes data should import
`yamibo_forum_client_contracts.dart`; composition roots may import the adapters
entry point when replacing an individual source.

No endpoint, source choice, cache key, snapshot schema, WAF evidence, or
resource replay rule changed in `0.2.0`.

## Future migrations

Each breaking supported-API change will receive a section containing the old
shape, replacement, behavioral differences, and the first version in which the
old API can be removed.
