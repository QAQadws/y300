# yamibo_forum_client

`yamibo_forum_client` is the pure-Dart read client used by Y300 for Yamibo
forum data. It owns request descriptions, Discuz/HTML adapters, parsing,
source-neutral models, capabilities, cache codecs, transport error mapping,
and the protocol side of WAF recovery.

The package is currently private (`publish_to: none`) and its public API is
still in the `0.1.x` compatibility period. It can be consumed through a local
path or a Git dependency that points to this monorepo subdirectory.

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
final cookies = MemoryForumCookieStore();
final network = DioForumClientNetwork(config: config, cookies: cookies);
final client = YamiboForumClientBuilder(
  config: config,
  network: network,
  sessionStore: MemoryForumSessionStore(),
  documentStore: MemoryForumDocumentStore(),
  snapshotStore: MemoryForumSnapshotStore(),
).buildStandardReads();

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

See [`example/basic_read.dart`](example/basic_read.dart) for a complete
standalone example. The example performs a public read only when run manually;
package tests never contact the live forum.

## Standard read-source matrix

`YamiboForumClientBuilder.buildStandardReads()` installs the source choices
currently verified by Y300:

| Capability | Source |
| --- | --- |
| Forum directory, forum display, thread detail | HTML-first |
| Tag directory, public profile, user blogs | HTML |
| Favorites and current-user profile | Discuz API |
| Comic catalog, discovery, replies, ingestion detail | Discuz v4 API |
| Search | HTML, only when a `ForumFormhashProvider` is supplied |

If no formhash provider is supplied, only search is left uninstalled and its
facade methods fail closed with `DataReadFailureKind.unsupported`. Advanced
hosts can import the adapters barrel and build a custom `ForumClientSourcePlan`
for individual contracts; there is deliberately no global HTML/API switch.

Novel body reads are not part of the standard client. Y300 keeps their
`version=1` contract in the novel feature because it has different content and
lifecycle requirements.

## Host responsibilities

The memory Cookie, session, document, and snapshot stores are suitable for
examples and tests only. A production application should provide persistent
implementations of the corresponding ports and must protect authentication
material according to its platform security model.

The core detects WAF evidence, coordinates single-flight recovery, enforces
cooldown, and permits at most one replay after verified recovery. It never
mounts a WebView. Flutter applications should implement
`ForumWafRecoveryDelegate` in an optional host integration that owns the
WebView and application lifecycle, then pass it to `DioForumClientNetwork`.
The package intentionally does not depend on Flutter or a WebView plugin.

Y300 uses the same package through Host Adapters backed by its process-wide
`YamiboHttpGateway`, Cookie/session/formhash stores, WAF coordinator, and
document/snapshot cache. This keeps package reads and still-unmigrated writes
on one authenticated transport path.

## Current capability boundary

The package currently covers forum/thread directories and details, Tag,
search, remote favorite directories, profiles/blogs, comic episode discovery,
and reply-page reads. Login UI and write operations—including posting,
replying, editing, favorite mutations, ratings, comments, polls, and uploads—
remain application-owned and are not represented as read results.

A future optional `yamibo_forum_client_flutter` package may provide reusable
WebView WAF and lifecycle integration. It will depend on this package rather
than moving Flutter into the protocol core.
