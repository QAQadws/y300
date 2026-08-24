# yamibo_forum_client

Private, pure-Dart protocol client for Yamibo forum reads.

Public boundaries are intentionally split:

- `yamibo_forum_client.dart`: facade, runtime ports, and client configuration;
- `yamibo_forum_client_contracts.dart`: source-neutral contracts, models,
  capabilities, read results, and stable reference/image helpers;
- `yamibo_forum_client_adapters.dart`: adapter factory and source parsers for
  composition roots and package tests only.

The package can use its standalone Dio runtime, memory session stores, and WAF
delegates. Y300 instead injects Host Adapters backed by its process-wide
`YamiboHttpGateway`, Cookie/session/formhash stores, WAF recovery coordinator,
and document/snapshot cache. This deliberately keeps reads and still-unmigrated
writes on one authenticated transport path.

Application domain and presentation code must depend only on the contracts
barrel. The package has no Flutter, Riverpod, SQLite, or Y300 dependency and is
still private (`publish_to: none`).
