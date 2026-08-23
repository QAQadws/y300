# yamibo_forum_client

Private protocol client boundary for the Y300 Yamibo forum client.

The package owns transport, cookies, session/formhash state, and WAF recovery
coordination. Feature repositories and application orchestration remain in
Y300. The package has no Flutter, Riverpod, SQLite, or Y300 dependency.

This package is intentionally private (`publish_to: none`) while adapter
migration is evaluated in a later phase.
