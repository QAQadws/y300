# Changelog

All notable changes to `yamibo_forum_client` are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow the policy in [VERSIONING.md](VERSIONING.md).

## Unreleased

### Added

- Reserved for changes made after `0.10.0`.

## 0.10.0 - 2026-08-31

### Added

- Verified Yamibo origins and browser identities through
  `ForumClientConfig.yamibo()` and `ForumBrowserUserAgents`.
- `YamiboForumClientBuilder.ephemeralDio()` and
  `ForumClientCachePorts.memory()` for evaluation, tests, and short-lived
  tools.
- Conservative per-contract source overlays for the standard client.
- Chinese onboarding, contribution, and release-check documentation.

### Changed

- The adapters entry point now exports only the adapter factory, the two
  thread-detail decoders required by composition roots, and the safe parse
  exception.
- Multi-role adapter factory methods return named records of source-neutral
  contracts instead of concrete Discuz types.
- `html` was updated to `0.15.7`; the package lockfile is no longer tracked for
  this unpublished library.

### Removed

- Deprecated `buildStandardReads()`.
- Deprecated poll transport fields `ThreadPoll.actionUrl` and
  `ThreadPoll.formHash`.
- Deprecated `ThreadDetailCapability.pollVoteAction`; poll mutation capability
  belongs to `ThreadPollVoteCommand`.

## 0.9.0 - 2026-08-30

### Added

- Source-neutral preparation and command contracts for editing ordinary thread
  first posts and ordinary replies.
- A strict Discuz HTML adapter that preserves successful form controls in
  order, keeps dynamic fields opaque, and submits replay-safe scalar multipart
  bodies.
- One-read edit confirmation for ambiguous submissions without repeating the
  mutation request.

### Changed

- Mobile edit forms use the mobile request identity and desktop edit forms use
  the desktop identity; submission preserves the preparation mode and Referer.
- Complex or unproved edit forms fail closed instead of leaking Discuz form
  details into the host application.
- Edit receipts and failures no longer expose HTML, formhash, server text, or
  raw callback payloads.

## 0.8.0 - 2026-08-30

### Added

- A source-neutral thread poll-vote command with fail-closed capability and
  structured command outcomes.
- Ordered URL-encoded form fields for protocols that require duplicate field
  names such as repeated `pollanswers[]` values.
- A Discuz `pollvote` v2 adapter with exact response-version and message-code
  validation.

### Changed

- Thread poll submission no longer depends on HTML action URLs or formhash
  values embedded in cached thread documents.
- Only exact `thread_poll_succeed` evidence produces an applied receipt;
  explicit Discuz rejections remain structured and all unproved sent outcomes
  remain unknown without automatic retry.
- Poll receipts no longer expose response text, HTML, or JSON payloads.

## 0.7.0 - 2026-08-29

### Added

- Source-neutral preparation and command contracts for image attachment
  upload, unused-image directory reads, unused-image deletion, and post-bound
  image deletion.
- A replay-safe streaming multipart Host port with progress and cooperative
  cancellation.
- Discuz adapters for `checkpost` v1, `forumupload` v4, `imagelist`, and
  `deleteattach`, including stable mappings for upload statuses `-1..-13`.

### Changed

- Multipart WAF recovery reconstructs the complete form and opens a fresh file
  stream for the single verified HTTP 405 replay.
- Unused-image deletion requires an opaque directory proof and performs one
  read-back when the direct deletion count is inconclusive.
- Upload and deletion results no longer expose upload hashes, formhash values,
  response bodies, or source-specific result models.

## 0.6.0 - 2026-08-29

### Added

- Independent source-neutral preparation and command contracts for thread
  creation, ordinary replies, and prepared post replies.
- Discuz v4 adapters for current Y300 ordinary-thread, poll, tag, attachment,
  signature, notification, and reply fields.
- Minimum read-access submission in the inclusive `0..255` range, with
  optional v4 thread read-back evidence for non-zero values.

### Changed

- Creation and reply receipts expose only stable identities, moderation state,
  and structured read-access evidence; raw server messages are no longer
  returned to applications.
- Prepared post-reply HTML requests keep the mobile request identity used by
  their `mobile=2` endpoint instead of switching to the desktop profile.
- Post-reply quote previews prefer Discuz's dedicated `noticeauthormsg` value,
  preserving the quoted body without surrounding form title and author chrome.
- Composer rejection handling now preserves the exact Discuz `messageval`,
  recognizes optional `mobile:` and `//1` wrappers, and distinguishes input,
  authentication, and permission failures instead of treating unknown codes as
  permission failures.
- A sent command whose final effect cannot be proved now returns
  `DataCommandOutcomeUnknown` and is never retried by the adapter.

## 0.5.0 - 2026-08-28

### Added

- Independent source-neutral preparation and command contracts for post
  ratings and post comments.
- Discuz HTML/AJAX adapters that validate dynamic forms, preserve opaque
  submission state, and support all server-provided rating dimensions.
- Structured rating/comment receipts and explicit rejected, not-sent, and
  outcome-unknown results that never expose response bodies or server text.

### Changed

- Rating and comment success now requires a stable JSON message code or the
  matching Discuz AJAX success callback; visible localized text and empty
  responses are no longer treated as proof.
- The standard builder installs rating/comment preparation and command slots.

## 0.4.0 - 2026-08-27

### Added

- Source-neutral target-state commands for forum and thread favorites.
- Discuz v4 favorite adapters with formhash preparation and authoritative
  favorite-directory read-back confirmation.
- Structured receipts distinguishing a changed state from an already-applied
  state without exposing server messages or transport payloads.

### Changed

- Forum removal now resolves and verifies `fid → favid`; thread removal remains
  keyed by stable `tid`.
- Accepted mutations whose final state cannot be read back now return
  `DataCommandOutcomeUnknown` and are never retried by the command adapter.

## 0.3.0 - 2026-08-26

### Added

- Source-neutral command outcomes that distinguish applied, rejected,
  not-sent, outcome-unknown, and unsupported operations.
- Password login, authoritative session resolution, and standard logout
  contracts with a verified Discuz v4 adapter.
- A Host Cookie port in the advanced builder and a canonical formhash provider
  exposed by the client facade for commands still migrating from Y300.

### Changed

- The standard composition entry point is now `buildStandardClient()`;
  `buildStandardReads()` remains deprecated for source compatibility.
- Formhash freshness now has an independent timestamp and is no longer
  extended by unrelated identity updates.
- Logout no longer attempts the legacy `mlogout/hash` fallback protocol.

## 0.2.0 - 2026-08-24

### Added

- A supported standard Dio builder requiring only host Cookie, WAF, and cache
  ports.
- Package-owned session projection and standard `profile`/`forumindex`
  formhash discovery.
- Protected image streaming through the same Cookie and WAF boundary.
- Forum home, notifications, private messages, stickers, ratings, post
  location, and author-filtered post reads.
- License, versioning, migration, and API stability documentation.

### Changed

- The package is now documented as a third-party-readable client core rather
  than a private Y300 implementation detail.
- Public read contracts and Host ports have an explicit pre-1.0 compatibility
  policy.

## 0.1.0 - 2026-08-23

### Added

- Initial extraction of Y300's source-neutral read contracts, HTML/Discuz
  adapters, standard source plan, cache codecs, and contract tests.
