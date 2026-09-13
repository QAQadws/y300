# CI/CD maintenance

The `Y300` workflow checks one immutable commit across all jobs. PRs check GitHub's merge commit; pushes and manual runs check the event SHA. All required jobs must succeed before the fixed `CI` status succeeds. No workflow-level path filters, test retries, production credentials or distributable APKs are used for PRs.

## Toolchain and checks

- Flutter comes from `.flutter-version` (3.44.4), with Ubuntu 24.04 and Temurin JDK 17. Actions use reviewed full commit SHAs; actionlint 1.7.12 is checked against its pinned SHA-256.
- App and protocol-package lockfiles are independent. Both use pub.dev and `--enforce-lockfile`. Changing a dependency or SDK is a reviewed source change. The package remains pure Dart and its lockfile fixes its development/test resolution, not downstream consumers' dependencies.
- `quality` checks workflow scripts, changed Dart formatting, generated localizations and app analysis. `package-tests` separately analyzes and tests the package; `app-tests` uses both native Flutter shards. `android-check` compiles an arm64 release APK using an ephemeral debug signer and discards it.
- Formatting uses PR merge-base, push `before`, or the previous reachable stable tag for manual/tag runs; deleted files are excluded and paths are passed as separate process arguments. Existing unrelated Dart files are not reformatted.
- Pub/Flutter cache writes are limited to trusted main runs. PRs can restore pub dependencies but never save them. Gradle caches only dependency modules and wrapper distributions; release only reads that cache. No build output, signing files, configuration cache or real forum data is cached.
- Each analysis/test/build command reports its exit status and duration. Failed commands preserve their exit code; no automatic test retries hide regressions. Generated or untracked source files fail the cleanliness check, and untranslated localization entries fail quality.

Run script tests with Python 3.11 or newer:

```bash
python3 -m unittest discover -s tool/ci/tests -v
```

## Repository controls

After a real PR run establishes a successful `CI` check, enable the main ruleset: require PRs, require `CI` from GitHub Actions with strict up-to-date checks, block deletion and force pushes, and require zero additional reviewers. Administrators retain an explicit emergency bypass. The `v*` tag ruleset limits creation to maintainers and prohibits ordinary updates/deletions.

The `android-release` Environment allows only tag names matching `v*` (a tag rule, not a branch rule). Its four Secrets are `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.

Migrate the existing signer, verify its certificate against `release-baseline.json`, check the Environment Secret names, then remove duplicate repository-level Secrets. GitHub does not reveal old Secret values; use the existing local signing files to restore them, never a new keystore. Ordinary PRs cannot use this Environment. The tag is the maintainer's build request; making the draft public is a separate manual action, so no additional Environment review is required.

The Gradle properties `y300RequireReleaseSigning`, `y300SigningProperties`, and `y300UseDebugSigning` control only build-time signing. Distribution builds require a complete signing configuration and an existing key; debug fallback is forbidden when the release guard is enabled. The CI signing script restores a private directory under `RUNNER_TEMP`, writes Java Properties safely, and removes it even after build failure. Signing passwords are never command-line arguments.

## Release contract and recovery

`pubspec.yaml` must contain one stable `X.Y.Z+positiveBuildNumber`. The tag must be exactly `vX.Y.Z`; its peeled remote commit must equal the workflow SHA and belong to current main. These checks run before CI builds, again before secrets, and before packaging/upload. The version name and code must exceed the verified published baseline and subsequent stable releases/drafts. An interrupted draft reserves its version code via its identity marker; a published post-baseline release must contain a manifest.

`release-baseline.json` records public metadata obtained by verifying the same v1.1.5 APK from GitHub and Gitee: actual version code 43 and its signing certificate. It is not derived from a possibly inaccurate tag pubspec. Do not change this trust baseline simply to bypass a failed signature check; signer rotation needs its own migration design.

After signature verification, Android SDK tools and the APK ZIP contents must confirm `com.adws.y300`, the pubspec version/code and only arm64 native libraries. There is no ABI split and no Dart obfuscation. Distribution files are:

1. `y300-vX.Y.Z-android-arm64-v8a-release.apk`
2. The same name plus `.sha256`, containing exactly `hexadecimal-sha256`, two spaces, the APK basename, and a newline.
3. `release-manifest.json`, schema 1: tag, full commit SHA, version name/code, application ID, ABIs, certificate SHA-256, APK filename/hash/size, Flutter/Dart versions, UTC build time, and workflow run URL.

The workflow serializes active release jobs and never cancels an active release build. GitHub concurrency retains only a bounded pending queue; do not push multiple release tags in a batch. Re-run a superseded pending release explicitly when appropriate.

Release creation uses the existing tag (`--verify-tag`) and exact target SHA. Its HTML comment binds tag, commit and version code. Keep that marker while editing release notes. Retry only an unpublished draft with that identity; published releases, unknown manual drafts, and conflicting identities fail closed. Uploads may replace this draft's assets; the manifest is uploaded last, and all three assets are downloaded and compared to the local verified bytes before reporting success. A partial draft remains unpublished and can be repaired by rerunning `mode=release` on the same tag. Inspect conflicts manually instead of deleting or moving tags automatically.

Artifacts last 30 days. They and public-repository workflow logs are not private storage. No symbols or signing material are uploaded. Review the APK and notes, publish GitHub manually, then copy those identical files to Gitee without rebuilding. An APK build is a compile/package check, not a device installation or forum interaction test. The first real signed release through Actions is validated when the maintainer chooses the next version; CI setup does not manufacture a release tag.
