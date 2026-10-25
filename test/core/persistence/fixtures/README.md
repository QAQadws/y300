# Published database schemas

These fixtures freeze the complete fresh-database creation path of every tagged
release. They do not call today's schema builder, remove current columns to
imitate an old version, or execute Git commands while tests run.

| Database version | Release tags | Tables |
| --- | --- | ---: |
| 27 | v1.0.0 | 28 |
| 36 | v1.0.2 | 31 |
| 38 | v1.1.0, v1.1.1, v1.1.2 | 31 |
| 40 | v1.1.3, v1.1.4, v1.1.5, v1.2.0, v1.2.1 | 35 |
| 41 | v1.3.0 | 35 |
| 42 | v1.3.1 | 35 |
| 43 | v1.3.2 | 35 |

The JSON files contain the released creation statements in their original order,
including indexes, triggers and default inserts. Only the clock-generated
`created_at` values of default categories are fixed to `1` for deterministic
comparison. Default category IDs/names and the `grid_column_count` setting retain
their released values. Caller tests set the old `user_version` and enable foreign
keys before invoking `createReleasedDatabaseFixture` in `onCreate`.

For versions 27 through 41, the source is the tag's
`lib/features/comic/data/local/comic_local_db.dart` and its `_createTables` call
closure. Versions 42 and 43 use the tag's
`lib/core/persistence/app_database_schema.dart` and the called schema functions.
Each JSON file records the representative tag's creation-source Git blob IDs.
Table-name constants were resolved from that tag, not the current branch.

All thirteen tags were extracted separately and their executed SQLite table,
index, trigger definitions and default rows compared. Tags sharing a database
version produced identical results; their fixture is shared only after that
comparison. Each extracted creation sequence was also checked using SQLite
`foreign_key_check` and `integrity_check`.

Keep these files frozen when production migrations change. New release versions
get a new fixture from that release's real creation path; correcting a historical
fixture requires checking its recorded tag source. Runtime databases and user
data must never be copied into this directory.
