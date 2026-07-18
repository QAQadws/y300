import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/composer_shared/data/local/composer_draft_local_db.dart';

typedef ComposerDraftDatabaseOpener =
    Future<Database> Function(String databaseName);

class ComposerDraftDatabaseManager {
  ComposerDraftDatabaseManager({
    required this.databaseName,
    ComposerDraftDatabaseOpener opener = _openComposerDraftDatabase,
  }) : _opener = opener;

  final String databaseName;
  final ComposerDraftDatabaseOpener _opener;

  Future<Database>? _database;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  Future<Database> open() async {
    if (_disposed) {
      throw StateError('ComposerDraftDatabaseManager has been disposed');
    }
    final current = _database;
    if (current != null) {
      final db = await current;
      if (db.isOpen) {
        return db;
      }
      if (identical(_database, current)) {
        _database = null;
      }
    }

    final next = _opener(databaseName);
    _database = next;
    try {
      final db = await next;
      if (_disposed) {
        if (db.isOpen) {
          await db.close();
        }
        throw StateError('ComposerDraftDatabaseManager has been disposed');
      }
      return db;
    } catch (_) {
      if (identical(_database, next)) {
        _database = null;
      }
      rethrow;
    }
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    final operation = _dispose();
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _dispose() async {
    final current = _database;
    _database = null;
    if (current == null) {
      return;
    }
    try {
      final db = await current;
      if (db.isOpen) {
        await db.close();
      }
    } catch (_) {
      // Provider disposal must not surface a second asynchronous open error.
    }
  }
}

Future<Database> _openComposerDraftDatabase(String databaseName) {
  return ComposerDraftLocalDb.open(databaseName: databaseName);
}
