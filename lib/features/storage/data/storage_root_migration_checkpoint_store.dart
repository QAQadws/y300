import 'dart:convert';

import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

final class StorageRootMigrationCheckpoint {
  const StorageRootMigrationCheckpoint({
    required this.phase,
    this.sourceRoot,
    this.targetRoot,
    this.failureCode,
  });

  static const int schemaVersion = 1;

  final StorageRootMigrationPhase phase;
  final String? sourceRoot;
  final String? targetRoot;
  final StorageRootMigrationFailureCode? failureCode;

  StorageRootMigrationCheckpoint copyWith({
    StorageRootMigrationPhase? phase,
    String? sourceRoot,
    String? targetRoot,
    StorageRootMigrationFailureCode? failureCode,
    bool clearFailure = false,
  }) {
    return StorageRootMigrationCheckpoint(
      phase: phase ?? this.phase,
      sourceRoot: sourceRoot ?? this.sourceRoot,
      targetRoot: targetRoot ?? this.targetRoot,
      failureCode: clearFailure ? null : (failureCode ?? this.failureCode),
    );
  }

  static const completed = StorageRootMigrationCheckpoint(
    phase: StorageRootMigrationPhase.completed,
  );

  @override
  bool operator ==(Object other) {
    return other is StorageRootMigrationCheckpoint &&
        other.phase == phase &&
        other.sourceRoot == sourceRoot &&
        other.targetRoot == targetRoot &&
        other.failureCode == failureCode;
  }

  @override
  int get hashCode => Object.hash(phase, sourceRoot, targetRoot, failureCode);
}

abstract interface class StorageRootMigrationCheckpointStore {
  Future<StorageRootMigrationCheckpoint?> read();

  Future<void> write(StorageRootMigrationCheckpoint checkpoint);

  Future<void> clear();
}

final class SharedPreferencesStorageRootMigrationCheckpointStore
    implements StorageRootMigrationCheckpointStore {
  SharedPreferencesStorageRootMigrationCheckpointStore({
    required PreferencesStore preferencesStore,
    StorageRootMigrationCheckpointCodec codec =
        const StorageRootMigrationCheckpointCodec(),
  }) : _preferencesStore = preferencesStore,
       _codec = codec;

  static const PreferenceKey<String> _key = PreferenceKey<String>(
    TechnicalStorageKeys.downloadStorageRootMigrationV1,
  );

  final PreferencesStore _preferencesStore;
  final StorageRootMigrationCheckpointCodec _codec;

  @override
  Future<StorageRootMigrationCheckpoint?> read() async {
    final encoded = await _preferencesStore.read(_key);
    if (encoded == null) {
      return null;
    }
    return _codec.decode(encoded);
  }

  @override
  Future<void> write(StorageRootMigrationCheckpoint checkpoint) {
    return _preferencesStore.write(_key, _codec.encode(checkpoint));
  }

  @override
  Future<void> clear() async {
    if (await _preferencesStore.contains(_key)) {
      await _preferencesStore.remove(_key);
    }
  }
}

final class StorageRootMigrationCheckpointCodec {
  const StorageRootMigrationCheckpointCodec();

  String encode(StorageRootMigrationCheckpoint checkpoint) {
    _validate(checkpoint);
    return jsonEncode(<String, Object?>{
      'schemaVersion': StorageRootMigrationCheckpoint.schemaVersion,
      'phase': checkpoint.phase.name,
      if (checkpoint.phase !=
          StorageRootMigrationPhase.completed) ...<String, Object?>{
        'sourceRoot': checkpoint.sourceRoot,
        'targetRoot': checkpoint.targetRoot,
      },
      if (checkpoint.failureCode != null)
        'lastErrorCode': checkpoint.failureCode!.name,
    });
  }

  StorageRootMigrationCheckpoint decode(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const StorageRootMigrationCheckpointFormatException();
      }
      final json = decoded.map((key, value) => MapEntry(key.toString(), value));
      if (json['schemaVersion'] !=
          StorageRootMigrationCheckpoint.schemaVersion) {
        throw const StorageRootMigrationCheckpointFormatException();
      }
      final phase = _enumByName(
        StorageRootMigrationPhase.values,
        json['phase'],
      );
      final failureValue = json['lastErrorCode'];
      final checkpoint = StorageRootMigrationCheckpoint(
        phase: phase,
        sourceRoot: _optionalTrimmedString(json['sourceRoot']),
        targetRoot: _optionalTrimmedString(json['targetRoot']),
        failureCode: failureValue == null
            ? null
            : _enumByName(StorageRootMigrationFailureCode.values, failureValue),
      );
      _validate(checkpoint);
      return checkpoint;
    } on StorageRootMigrationCheckpointFormatException {
      rethrow;
    } catch (_) {
      throw const StorageRootMigrationCheckpointFormatException();
    }
  }

  void _validate(StorageRootMigrationCheckpoint checkpoint) {
    final hasSource = checkpoint.sourceRoot?.trim().isNotEmpty == true;
    final hasTarget = checkpoint.targetRoot?.trim().isNotEmpty == true;
    if (checkpoint.phase == StorageRootMigrationPhase.completed) {
      if (hasSource || hasTarget || checkpoint.failureCode != null) {
        throw const StorageRootMigrationCheckpointFormatException();
      }
      return;
    }

    final isUnrecoverableCleanupState =
        checkpoint.phase == StorageRootMigrationPhase.cleanupPending &&
        checkpoint.failureCode == StorageRootMigrationFailureCode.stateCorrupt;
    if ((!hasSource || !hasTarget) && !isUnrecoverableCleanupState) {
      throw const StorageRootMigrationCheckpointFormatException();
    }
  }

  T _enumByName<T extends Enum>(List<T> values, Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const StorageRootMigrationCheckpointFormatException();
    }
    return values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw const StorageRootMigrationCheckpointFormatException(),
    );
  }

  String? _optionalTrimmedString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String || value.trim().isEmpty) {
      throw const StorageRootMigrationCheckpointFormatException();
    }
    return value.trim();
  }
}

final class StorageRootMigrationCheckpointFormatException implements Exception {
  const StorageRootMigrationCheckpointFormatException();
}
