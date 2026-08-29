# yamibo_forum_client

`yamibo_forum_client` is an unofficial pure-Dart read, basic-authentication,
and structured-command client used by Y300 for Yamibo forum data. It owns request descriptions,
Discuz/HTML adapters, parsing, source-neutral models, capabilities, command
outcomes, cache codecs, transport error mapping, and the protocol side of WAF
recovery.

The package remains unpublished (`publish_to: none`) and can be consumed using
a local path or Git dependency targeting this monorepo subdirectory. Version
`0.6.x` is governed by [VERSIONING.md](VERSIONING.md); API maturity is listed in
[API_STABILITY.md](API_STABILITY.md). The package is licensed under
`GPL-3.0-only`; see [LICENSE](LICENSE).

## Public boundaries

- `yamibo_forum_client.dart`: facade, standard builder, standalone runtime
  ports, stores, and configuration;
- `yamibo_forum_client_contracts.dart`: source-neutral contracts, models,
  capabilities, read results, and stable reference/image helpers;
- `yamibo_forum_client_adapters.dart`: advanced adapter construction and
  source parsers, intended only for composition roots and package tests.

Applications should consume the facade or contracts barrel. Do not import
package `src/` files.

## Quick start

```dart
final config = ForumClientConfig(
  siteOrigin: Uri.parse('https://bbs.yamibo.com'),
  apiOrigin: Uri.parse(
    'https://bbs.yamibo.com/api/mobile/index.php',
  ),
  userAgent: 'MyThirdPartyApp/1.0',
);
final client = YamiboForumClientBuilder.standardDio(
  config: config,
  cookies: persistentCookieStore,
  caches: ForumClientCachePorts(
    documents: persistentDocumentStore,
    snapshots: persistentSnapshotStore,
    stickers: persistentStickerStore,
  ),
  waf: platformWafDelegate,
).buildStandardClient();

final result = await client.loadForumDirectory(
  const ForumDirectoryQuery(),
);
switch (result) {
  case DataReadSuccess(:final data, :final capabilities, :final metadata):
    // Render only fields whose capability is supported. Metadata tells the
    // caller whether this came from network, snapshot, or stale fallback.
  case DataReadFailure(:final kind, :final code):
    // Map the stable failure kind/code into application-specific UI.
}
```

The identifiers named `persistent...` and `platformWafDelegate` above are Host
implementations. The package supplies the Dio transport, request profiles,
session projection, standard formhash discovery, adapters, and source plan.
Package tests never contact the live forum.

## Standard source matrix

`YamiboForumClientBuilder.buildStandardClient()` installs the source choices
currently verified by Y300:

| Capability | Source |
| --- | --- |
| Forum home document, directory, forum display, thread detail | HTML-first |
| Tag directory, public profile, user blogs | HTML |
| Favorites, current-user profile, notifications, private messages, stickers | Discuz API |
| Comic catalog, discovery, replies, ingestion detail | Discuz v4 API |
| Full post ratings | Discuz AJAX CDATA |
| Post location | Discuz HTML redirect plus identity proof |
| Author-filtered post pages | Discuz `viewthread version=1` |
| Search | HTML with package-owned `profile`/`forumindex` formhash discovery |
| Password login, session resolution, standard logout | Discuz v4 API |
| Forum and thread favorite target-state commands | Discuz v4 API plus favorite-directory read-back |
| Post rating/comment preparation and commands | Discuz HTML forms plus JSON/AJAX callback proof |
| Thread creation and reply preparation/commands | Discuz v4 API plus HTML post-reply preparation |

Authentication contracts are deliberately independent. A future source may
implement session resolution without implementing password login or logout.
Login is considered applied only after a subsequent profile response proves a
stable non-zero user ID. Logout uses only
`action=logout&formhash=...`; no `mlogout/hash` fallback is attempted.

Command callers must distinguish five outcomes:

- `DataCommandApplied`: the postcondition was proved;
- `DataCommandRejected`: the server explicitly refused the command;
- `DataCommandNotSent`: validation/session preparation failed before sending;
- `DataCommandOutcomeUnknown`: a request was sent but its effect is unknown;
- `DataCommandUnsupported`: the selected source does not implement it.

No ordinary command request is retried automatically. A verified same-site
HTTP 405 may still be replayed once by the shared WAF boundary before response
bytes are exposed.

Favorite changes use target-state commands rather than exposing Discuz
mutation endpoints. Forum favorite creation uses stable `fid`; forum removal
resolves and verifies the remote `favid` from the favorite directory. Thread
favorite and removal both use stable `tid`. A mutation is `applied` only after
the corresponding directory proves the requested final state. If submission
succeeds but read-back fails or disagrees, the result is `outcomeUnknown` and
the caller must not automatically submit the mutation again.

Post ratings and comments use separate preparation and command contracts. The
prepared form carries an opaque token containing protocol state; applications
render only the source-neutral fields and return the token unchanged when
submitting. Rating forms preserve every server score dimension, while Y300's
current UI intentionally edits its primary dimension. A command is applied
only when a stable JSON message code or matching Discuz AJAX success callback
proves success. Server text and raw response payloads never enter receipts.

Thread creation and replies follow the same preparation/command boundary.
Creation supports Y300's ordinary and poll fields, tags, attachment identities,
signature/notification/parsing switches, and minimum read access. Post replies
preserve dynamic hidden fields in an opaque preparation token; ordinary thread
replies obtain formhash when submitted. Only positive, matching `tid`/`pid`
values and an exact success code produce an applied receipt. A non-zero
read-access request is read back without weakening already-proved creation
success.

Image attachments use a separate preparation/upload boundary. Preparation
proves the forum identity, current image-extension limits, and remaining
quota, while keeping Discuz uid/upload-hash state opaque. Upload content is a
replay-safe stream factory: the Host may open it again only for the one WAF
replay permitted after a verified HTTP 405. Positive attachment identities are
applied; Discuz statuses `-1..-13` are stable structured rejections; empty,
zero, malformed, or transport-indeterminate responses are outcome unknown.
Unused-image deletion requires proof from the current authenticated directory
and performs one read-back when the direct count cannot prove deletion.

Hosts with an existing authenticated session stack may override the standard
formhash provider. Advanced hosts can import the adapters barrel and build a
custom `ForumClientSourcePlan` for individual contracts; this API is
experimental and there is deliberately no global HTML/API switch.

The standard client exposes the source-neutral author-post page used by Y300's
novel synchronization and permanently fixes that adapter to `version=1`.
Novel chapter construction, title parsing, synchronization, body projection,
and reader state remain application business logic and are not package models.

## Host responsibilities

A standalone production application needs to implement only these persistence
and platform boundaries:

- `ForumCookieStore`, persisted and protected according to the platform
  security model;
- `ForumDocumentStore`, `ForumSnapshotStore`, and
  `ForumStickerCatalogStore`, conveniently grouped by `ForumClientCachePorts`;
- `ForumWafRecoveryDelegate` when the forum enables its WAF challenge.

The package-owned session projection is reproducible and remains in memory.
The standard formhash provider checks that projection, then requests `profile`
and falls back to `forumindex`; password login deliberately requests
`forumindex` first, then `profile`. Formhash freshness has its own 30-minute
timestamp, so unrelated profile updates cannot extend an old token.
Authentication remains rooted in the Cookie store. Memory store
implementations are suitable for tests and short-lived tools only, not
production persistence.

The core treats HTTP 405 from a managed forum origin as the sole WAF evidence,
coordinates single-flight recovery, enforces cooldown, and permits at most one
replay after verified recovery. Response bodies are never inspected for WAF
signatures. It never mounts a WebView. Flutter applications should implement
`ForumWafRecoveryDelegate` in an optional host integration that owns the
WebView and application lifecycle, then pass it to `DioForumClientNetwork`.
The package intentionally does not depend on Flutter or a WebView plugin.

Y300 uses the same package through Host Adapters backed by its process-wide
`YamiboHttpGateway`, Cookie/session/formhash stores, WAF coordinator, and
document/snapshot cache. This keeps package reads and still-unmigrated writes
on one authenticated transport path.

## Protected image resources

The standard Dio runtime also implements `ForumResourceClient`. Image reads
share its Cookie store and WAF delegate, but expose a single-subscription byte
stream instead of buffering the full file:

```dart
final resolver = ForumResourceReferenceResolver(
  siteOrigin: config.siteOrigin,
);
final reference = resolver.resolve(
  '/data/attachment/forum/example.jpg',
  referer: config.siteOrigin.resolve('/forum.php?mod=viewthread&tid=1'),
);
if (reference != null) {
  final result = await client.resources.open(
    ForumResourceRequest(reference: reference),
  );
  switch (result) {
    case ForumResourceSuccess(:final content, :final contentType):
      // Consume the stream exactly once, or cancel the subscription. A host
      // may write it atomically into its own cache before decoding it.
    case ForumResourceError(:final failure):
      // Map the stable failure kind; never inspect transport payloads.
  }
}
```

Same-site resources receive the forum Cookie and invoke WAF recovery only for
HTTP 405. Connection/receive timeout, a pending request, and script-shaped HTTP
200 content are not WAF evidence. Verified recovery permits one replay before
any bytes are exposed. Third-party images never receive the Yamibo Cookie and
never invoke Yamibo WAF recovery; redirects are bounded and HTTPS downgrade is
rejected. Referer query data is retained for same-site images and stripped
before third-party requests.

The package validates image content and returns metadata such as ETag, expiry,
content length, and extension. It intentionally does not own a disk cache,
Flutter `ImageProvider`, decode sizing, preloading, retention policy, CBZ, or
reader retry workflows. Those remain host responsibilities. A custom host can
provide its own `ForumResourceClient` to `YamiboForumClientBuilder`; if neither
the explicit client nor the network implements that contract, resource reads
fail closed as `unsupported`.

## Current capability boundary

The package currently covers basic password authentication, authoritative
session/logout handling, forum/thread favorite target-state commands,
post-rating/comment, thread-creation/reply, and image-attachment preparation
and commands, the forum home document, forum/thread directories
and details, Tag, search, remote favorite directories, profiles/blogs,
notifications, private messages, stickers, full rating details, post location,
author-filtered post pages, comic episode discovery, reply-page reads, and
protected image transport. Login UI and remaining write operations—including
full post editing and voting—remain application-owned.

## Y300 parity and unmigrated APIs

This package is a forum client core, not a complete Discuz SDK. The following
forum protocol operations still live in Y300 and are not part of the package:

- post-edit form preparation and submission;
- non-image file attachments, attachment descriptions/read permissions/prices,
  attachment replacement, and batch deletion;
- notification state mutations and private-message sending.

The following responsibilities are intentionally application-owned even when
their network references are produced by the package:

- WebView login/browsing/fallback, platform Cookie synchronization, and
  lifecycle management;
- the Flutter WebView implementation of `ForumWafRecoveryDelegate`;
- image disk caching, decoding, preloading, presentation, and reader recovery;
- SQLite data, shelves, favorite ingestion, comic/novel synchronization, and
  reading progress;
- download queues, CBZ files, notifications, and page generation ownership;
- Quill, BBCode, localization, routing, and all user interface state.

See [MIGRATION.md](MIGRATION.md) before changing integration style and
[CHANGELOG.md](CHANGELOG.md) before upgrading.

A future optional `yamibo_forum_client_flutter` package may provide reusable
WebView WAF and lifecycle integration. It will depend on this package rather
than moving Flutter into the protocol core.
