# Contributing

`yamibo_forum_client` is a pure-Dart protocol package. Changes must preserve its source-neutral contracts, fail-closed semantics, and independence from Y300 and Flutter.

## Before changing a protocol

1. Identify the business capability and its current public contract.
2. Record protocol evidence from a committed, sanitized fixture or upstream Discuz source. Browser observations alone are not sufficient for stronger guarantees.
3. Keep request construction and source-specific parsing inside an adapter. Do not expose HTML, JSON DTOs, formhash values, Cookies, or server text through contracts.
4. Distinguish an explicit empty result from unsupported capability and malformed evidence.
5. For commands, prove the postcondition before returning `DataCommandApplied`. Never automatically repeat an ambiguous mutation.

## Fixtures and privacy

- Tests must not contact the live forum.
- Fixtures must be minimal, synthetic, UTF-8, and committed under `test/fixtures` when a file is necessary.
- Use identities such as `tid=10001`, `pid=20001`, `uid=30001`, `fixture-user`, and `fixture-formhash`.
- Never commit a Cookie header, password, real formhash, attachment key, username, private post body, complete browser export, or private `docs/` sample.
- Assertions should verify stable codes and structured results, not localized server text.

## Public API

- Application code should use `yamibo_forum_client.dart` or `yamibo_forum_client_contracts.dart`.
- Keep `yamibo_forum_client_adapters.dart` within its explicit export allowlist.
- Do not import `lib/src` from another package.
- Add Dartdoc for every new public declaration. Explain identity requirements, empty/unsupported behavior, command uncertainty, and sensitive-data boundaries where relevant.
- A breaking supported-API change requires a pre-1.0 minor version, a changelog entry, and migration instructions.

## Verification

Run from this directory:

```text
dart format <changed Dart files>
dart analyze
dart test
dart doc
dart pub publish --dry-run
```

Formatting must be limited to files changed by the contribution. The dry run is a packaging check; this package remains `publish_to: none` until maintainers explicitly change its distribution policy.
