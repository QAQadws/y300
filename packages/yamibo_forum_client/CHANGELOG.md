# Changelog

All notable changes to `yamibo_forum_client` are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow the policy in [VERSIONING.md](VERSIONING.md).

## Unreleased

### Added

- Reserved for changes made after `0.2.0`.

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
