import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';

typedef HistoryDatabaseOpener = Future<Database> Function(String databaseName);
typedef HistoryDatabaseDeleter = Future<void> Function(String databaseName);

class HistoryDatabaseManager {
  HistoryDatabaseManager({
    required this.databaseName,
    HistoryDatabaseOpener opener = _openHistoryDatabase,
    HistoryDatabaseDeleter deleter = deleteDatabase,
  }) : _opener = opener,
       _deleter = deleter;

  final String databaseName;
  final HistoryDatabaseOpener _opener;
  final HistoryDatabaseDeleter _deleter;

  Future<Database>? _database;
  Completer<void>? _resetCompleter;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  bool get isInitialized => _database != null;
  bool get isDisposed => _disposed;

  Future<Database> open() async {
    final reset = _resetCompleter?.future;
    if (reset != null) {
      await reset;
    }
    if (_disposed) {
      throw StateError('HistoryDatabaseManager has been disposed');
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
        throw StateError('HistoryDatabaseManager has been disposed');
      }
      return db;
    } catch (_) {
      if (identical(_database, next)) {
        _database = null;
      }
      rethrow;
    }
  }

  Future<void> deleteAllData() {
    if (_disposed) {
      return Future<void>.error(
        StateError('HistoryDatabaseManager has been disposed'),
      );
    }
    final pending = _resetCompleter;
    if (pending != null) {
      return pending.future;
    }

    final completer = Completer<void>();
    _resetCompleter = completer;
    unawaited(_deleteAllData(completer));
    return completer.future;
  }

  Future<void> _deleteAllData(Completer<void> completer) async {
    try {
      await _closeCurrent();
      await _deleter(databaseName);
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      if (identical(_resetCompleter, completer)) {
        _resetCompleter = null;
      }
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
    final reset = _resetCompleter?.future;
    if (reset != null) {
      try {
        await reset;
      } catch (_) {
        // Disposal still closes any surviving connection after a reset error.
      }
    }
    try {
      await _closeCurrent();
    } catch (_) {
      // Provider disposal must not surface a second asynchronous error when
      // opening the database already failed for a consumer.
    }
  }

  Future<void> _closeCurrent() async {
    final current = _database;
    _database = null;
    if (current == null) {
      return;
    }
    final db = await current;
    if (db.isOpen) {
      await db.close();
    }
  }
}

Future<Database> _openHistoryDatabase(String databaseName) {
  return HistoryLocalDb.open(databaseName: databaseName);
}
