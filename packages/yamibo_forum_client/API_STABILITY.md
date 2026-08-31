# API stability

The public entry point determines the compatibility level of an API. Importing
files below `lib/src` is unsupported, even when Dart makes such paths visible
inside a monorepo.

## Supported within 0.x

The following APIs are covered by the compatibility policy in
[VERSIONING.md](VERSIONING.md):

- `yamibo_forum_client_contracts.dart`: source-neutral queries, data models,
  repository contracts, capabilities, `DataReadResult`, `DataCommandResult`,
  authentication/session, favorite-command, post-rating, post-comment,
  thread-creation, thread-reply, thread-poll-vote, thread-post-edit, and image-attachment
  preparation/command contracts, cache policy, cancellation, resource
  contracts, and reference/image helpers;
- `yamibo_forum_client.dart`: `YamiboForumClient`,
  `YamiboForumClientBuilder`, `ForumClientConfig`, verified browser identities,
  the standard and ephemeral Dio runtimes,
  Cookie/session/formhash/cache/WAF/network/resource ports, and logging ports;
- in-memory store implementations, for tests and ephemeral development use;
- `ForumClientCachePorts`, `YamiboForumClientBuilder.standardDio`, and
  `YamiboForumClientBuilder.ephemeralDio` as supported third-party composition
  paths, with the ephemeral path explicitly excluded from persistence
  guarantees.

Command outcome categories, favorite target-state requests/receipts,
rating/comment/thread-creation/thread-reply/thread-poll-vote/thread-post-edit/image-attachment
preparation and receipts, and their fail-closed meanings are supported within
`0.x`. Concrete Discuz authentication, favorite, rating, comment, creation,
reply, poll-vote, post-edit, and attachment endpoint parsing remains experimental.

Supported does not mean that every source provides every capability. Callers
must still gate behavior on the returned capability set and treat `unknown` or
`unsupported` as unavailable.

## Experimental

The following composition APIs are public for advanced integrations but remain
experimental:

- the allowlisted `yamibo_forum_client_adapters.dart` entry point;
- `ForumClientSourcePlan` and direct construction of concrete source plans;
- `ForumClientAdapterFactory`, `ThreadDetailHtmlParser`,
  `ThreadDetailApiMapper`, and `DataParseException`;
- concrete Discuz/HTML parsers, mappers, repositories, and snapshot codecs
  used internally by the factory;
- direct multipart runtime composition through `ForumMultipartClient`;
- source-specific behavior that has not yet been validated by a second
  production adapter.

Experimental APIs may change in a minor pre-1.0 release. Application domain and
presentation layers should depend on the contracts entry point instead.

## Internal

Everything under `lib/src` is internal unless it is re-exported by one of the
three documented public entry points. Direct `src` imports receive no
compatibility guarantee.
