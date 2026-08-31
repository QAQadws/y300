# Release checklist

The package is currently distributed through Git or path dependencies. This checklist prepares a versioned package state; it does not authorize publishing, tagging, pushing, or creating a GitHub release.

## Version and governance

1. Choose the version according to [VERSIONING.md](VERSIONING.md).
2. Update `pubspec.yaml`, [CHANGELOG.md](CHANGELOG.md), [MIGRATION.md](MIGRATION.md), [API_STABILITY.md](API_STABILITY.md), and both README files.
3. Confirm removed supported APIs completed the documented deprecation cycle.
4. Confirm the adapters barrel matches its governance-test allowlist.
5. Keep `publish_to: none` unless a separate release decision explicitly approves pub.dev publication.

## Quality gate

Run from `packages/yamibo_forum_client`:

```text
dart pub get
dart format <changed Dart files>
dart analyze
dart test
dart doc
dart pub publish --dry-run
```

Then run the Y300 integration gate from the repository root:

```text
flutter pub get
flutter analyze
flutter test test/architecture
flutter test test/core/network
flutter test test/features/forum
flutter test test/features/thread
flutter test test/features/comic
flutter test test/features/novel
flutter test
git diff --check
```

Verify that forum/thread remain HTML-first, ingestion and comic reads remain Discuz v4, author-filtered novel posts remain `version=1`, and Y300 still uses its single Host transport for Cookie, formhash, WAF, resources, and commands.

## Packaging inspection

Inspect the dry-run file list. It must not include `pubspec.lock`, generated API docs, private fixtures, local diagnostics, Cookie data, or Y300 application sources. Confirm that the example imports only public package entry points.

Only after all checks pass should a maintainer decide separately whether to commit, tag, push, or publish.
