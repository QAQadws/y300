import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/storage/data/storage_root_migration_checkpoint_store.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StorageRootMigrationCheckpointCodec();

  test('checkpoint codec round-trips every active phase', () {
    for (final phase in <StorageRootMigrationPhase>[
      StorageRootMigrationPhase.copying,
      StorageRootMigrationPhase.readyToSwitch,
      StorageRootMigrationPhase.cleanupPending,
      StorageRootMigrationPhase.blocked,
    ]) {
      final checkpoint = StorageRootMigrationCheckpoint(
        phase: phase,
        sourceRoot: 'fixture-source',
        targetRoot: 'fixture-target',
        failureCode: phase == StorageRootMigrationPhase.blocked
            ? StorageRootMigrationFailureCode.targetConflict
            : null,
      );

      final decoded = codec.decode(codec.encode(checkpoint));

      expect(decoded.phase, phase);
      expect(decoded.sourceRoot, 'fixture-source');
      expect(decoded.targetRoot, 'fixture-target');
      expect(decoded.failureCode, checkpoint.failureCode);
    }
  });

  test('completed checkpoint does not retain storage paths', () {
    final encoded = codec.encode(StorageRootMigrationCheckpoint.completed);
    final decoded = codec.decode(encoded);

    expect(encoded, isNot(contains('sourceRoot')));
    expect(encoded, isNot(contains('targetRoot')));
    expect(decoded.phase, StorageRootMigrationPhase.completed);
    expect(decoded.sourceRoot, isNull);
    expect(decoded.targetRoot, isNull);
  });

  test('codec rejects unknown versions, phases, and missing active roots', () {
    expect(
      () => codec.decode(
        '{"schemaVersion":2,"phase":"copying",'
        '"sourceRoot":"source","targetRoot":"target"}',
      ),
      throwsA(isA<StorageRootMigrationCheckpointFormatException>()),
    );
    expect(
      () => codec.decode(
        '{"schemaVersion":1,"phase":"future",'
        '"sourceRoot":"source","targetRoot":"target"}',
      ),
      throwsA(isA<StorageRootMigrationCheckpointFormatException>()),
    );
    expect(
      () => codec.decode('{"schemaVersion":1,"phase":"copying"}'),
      throwsA(isA<StorageRootMigrationCheckpointFormatException>()),
    );
  });

  test('state-corrupt cleanup checkpoint may omit unrecoverable paths', () {
    const checkpoint = StorageRootMigrationCheckpoint(
      phase: StorageRootMigrationPhase.cleanupPending,
      failureCode: StorageRootMigrationFailureCode.stateCorrupt,
    );

    final decoded = codec.decode(codec.encode(checkpoint));

    expect(decoded.phase, StorageRootMigrationPhase.cleanupPending);
    expect(decoded.sourceRoot, isNull);
    expect(decoded.targetRoot, isNull);
    expect(decoded.failureCode, StorageRootMigrationFailureCode.stateCorrupt);
  });

  test('SharedPreferences store uses one versioned technical key', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesStorageRootMigrationCheckpointStore(
      preferencesStore: SharedPreferencesStore(loader: () async => preferences),
    );
    const checkpoint = StorageRootMigrationCheckpoint(
      phase: StorageRootMigrationPhase.copying,
      sourceRoot: 'fixture-source',
      targetRoot: 'fixture-target',
    );

    await store.write(checkpoint);

    expect(
      preferences.containsKey('storage.download_root_migration.v1'),
      isTrue,
    );
    expect((await store.read())?.phase, StorageRootMigrationPhase.copying);

    await store.clear();
    expect(await store.read(), isNull);
  });
}
