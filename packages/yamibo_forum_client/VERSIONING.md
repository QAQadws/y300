# Versioning policy

`yamibo_forum_client` follows Semantic Versioning. The package remains below
`1.0.0`, but supported APIs receive stronger guarantees than ordinary
experimental `0.x` code.

## Supported APIs

The supported surface is listed in [API_STABILITY.md](API_STABILITY.md).

- Patch releases contain fixes, documentation, and backward-compatible
  additions. They do not intentionally break supported or experimental APIs.
- Breaking a supported API requires a minor version increase and an entry in
  [MIGRATION.md](MIGRATION.md).
- A supported declaration is deprecated for at least one minor release before
  removal unless retaining it would preserve a security or data-loss defect.
- Source-neutral result, identity, capability, and failure semantics are part
  of compatibility, not merely their Dart method signatures.

## Experimental APIs

Experimental APIs may change in a minor release without a deprecation cycle.
Such changes must still be documented in the changelog and migration guide.
Patch releases do not intentionally break them.

The package remains Git/path-only while `publish_to: none` is present. A
version bump documents compatibility for those consumers and does not imply a
pub.dev release, Git tag, or GitHub release.

## Reaching 1.0

The package will be considered for `1.0.0` after the supported contracts have
been used by an independent host, at least one alternative source adapter has
validated the replacement boundaries, and Cookie, cache, resource streaming,
and WAF Host ports have remained stable through a full minor cycle.

The package version is independent of the Y300 application version.
