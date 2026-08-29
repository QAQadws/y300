# Migration guide

## 0.5.x to 0.6.0

The standard client now installs independent thread-creation preparation,
thread-creation command, post-reply preparation, and reply-command slots.
Preserve preparation tokens unchanged and submit only against the preparation
that produced them. Ordinary replies do not require an HTML preparation read;
the command obtains formhash through the configured package provider.

Creation supports ordinary and poll threads, tags, attachment identities, the
existing parsing switches, and `minimumReadAccess`. The default is `0`.
Non-zero access is read back when possible; inspect
`ThreadCreationReceipt.readAccess` instead of treating a failed read-back as a
failed creation. Once the response proves a positive `tid` and `pid`, an
inconclusive read-back yields `unverified` evidence and must not cause a second
thread submission.

Thread/reply success receipts no longer contain server text or raw JSON. Only
`DataCommandApplied` proves success. Preserve authored content and attachments
for `DataCommandOutcomeUnknown`, and ask the user to inspect the thread before
an explicit retry.

Custom source plans must install all four slots they support. Existing read,
authentication, favorite, rating/comment, Cookie, formhash, WAF, and cache
ports are unchanged.

## 0.4.x to 0.5.0

The standard client now installs four independent post-interaction slots:
`ThreadPostRatingPreparationRepository`, `ThreadPostRatingCommand`,
`ThreadPostCommentPreparationRepository`, and `ThreadPostCommentCommand`.
Always prepare the current server form before constructing a submission, and
preserve its opaque token unchanged.

Success receipts contain only stable thread/post identities. Server
`messagestr`, AJAX markup, HTML, and XML are intentionally unavailable. Treat
`DataCommandOutcomeUnknown` as a possibly applied command: refresh the thread
or ask the user before any explicit retry.

Custom source plans must install preparation and command contracts separately.
This permits a future source to provide one capability without pretending to
support the other. Existing read, authentication, favorite, Cookie, formhash,
WAF, and cache ports are unchanged.

## 0.3.x to 0.4.0

The standard client now installs independent `FavoriteForumCommand` and
`FavoriteThreadCommand` slots. Applications should request a final state and
handle `DataCommandResult` exhaustively:

```dart
final result = await client.setThreadFavorite(
  const SetThreadFavoriteRequest(
    tid: '10001',
    targetState: FavoriteTargetState.unfavorited,
  ),
);
```

Do not delete local favorite state unless the result is
`DataCommandApplied`. In particular, `DataCommandOutcomeUnknown` means the
server may already have accepted the mutation but the directory could not
prove its final state; retrying automatically could repeat a non-idempotent
write.

Forum removal callers may pass a known `remoteFavoriteId` only as an untrusted
hint. The standard adapter always reloads the forum favorite directory and
verifies that the `favid` belongs to the requested `fid`. Thread removal uses
the stable `tid` protocol and does not require a `favid`.

Custom source plans must install the two command contracts explicitly or they
will fail closed as `unsupported`. Existing read, authentication, Cookie,
formhash, and WAF ports are unchanged.

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
