import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

class LibraryShelfRefreshSignal {
  const LibraryShelfRefreshSignal({
    required this.sequence,
    required this.modules,
    required this.reason,
    required this.createdAt,
  });

  final int sequence;
  final Set<LibraryModuleKey> modules;
  final String reason;
  final DateTime createdAt;
}

/// Small shared event bus for background shelf mutations.
///
/// Background services emit these signals after module data changes. UI phases
/// can subscribe and refresh the relevant shelf controllers without making
/// comic/favorite services know about pages.
class LibraryShelfRefreshBus {
  final ValueNotifier<LibraryShelfRefreshSignal?> _signal =
      ValueNotifier<LibraryShelfRefreshSignal?>(null);

  int _sequence = 0;

  ValueListenable<LibraryShelfRefreshSignal?> get signal => _signal;

  void notify({
    required Set<LibraryModuleKey> modules,
    required String reason,
  }) {
    if (modules.isEmpty) {
      return;
    }
    _sequence += 1;
    _signal.value = LibraryShelfRefreshSignal(
      sequence: _sequence,
      modules: Set<LibraryModuleKey>.unmodifiable(modules),
      reason: reason,
      createdAt: DateTime.now(),
    );
  }

  void dispose() {
    _signal.dispose();
  }
}

final libraryShelfRefreshBusProvider = Provider<LibraryShelfRefreshBus>((ref) {
  final bus = LibraryShelfRefreshBus();
  ref.onDispose(bus.dispose);
  return bus;
});
