import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

enum LibraryTaskProgressPriority {
  low,
  normal,
  high,
}

abstract class LibraryTaskProgressRegistration {
  void dispose();
}

abstract class LibraryTaskProgressHub {
  ValueListenable<LibraryShelfTaskProgress?> progressFor(
    LibraryModuleKey module,
  );

  LibraryTaskProgressRegistration registerSource({
    required Set<LibraryModuleKey> modules,
    required ValueListenable<LibraryShelfTaskProgress?> progress,
    LibraryTaskProgressPriority priority = LibraryTaskProgressPriority.normal,
  });
}

class DefaultLibraryTaskProgressHub implements LibraryTaskProgressHub {
  DefaultLibraryTaskProgressHub()
      : _progressByModule = <LibraryModuleKey, ValueNotifier<LibraryShelfTaskProgress?>>{
          for (final module in LibraryModuleKey.values)
            module: ValueNotifier<LibraryShelfTaskProgress?>(null),
        };

  final Map<LibraryModuleKey, ValueNotifier<LibraryShelfTaskProgress?>>
      _progressByModule;
  final List<_RegisteredProgressSource> _sources = <_RegisteredProgressSource>[];
  var _nextSequence = 0;

  @override
  ValueListenable<LibraryShelfTaskProgress?> progressFor(
    LibraryModuleKey module,
  ) {
    return _progressByModule.putIfAbsent(
      module,
      () => ValueNotifier<LibraryShelfTaskProgress?>(null),
    );
  }

  @override
  LibraryTaskProgressRegistration registerSource({
    required Set<LibraryModuleKey> modules,
    required ValueListenable<LibraryShelfTaskProgress?> progress,
    LibraryTaskProgressPriority priority = LibraryTaskProgressPriority.normal,
  }) {
    final normalizedModules = Set<LibraryModuleKey>.unmodifiable(modules);
    final source = _RegisteredProgressSource(
      modules: normalizedModules,
      progress: progress,
      priority: priority,
      registrationSequence: ++_nextSequence,
    );
    void handleProgressChanged() {
      _refreshModules(source.modules);
    }

    source.listener = handleProgressChanged;
    progress.addListener(handleProgressChanged);
    _sources.add(source);
    _refreshModules(source.modules);
    return _LibraryTaskProgressRegistration(() {
      final removed = _sources.remove(source);
      if (!removed) {
        return;
      }
      progress.removeListener(handleProgressChanged);
      _refreshModules(source.modules);
    });
  }

  void dispose() {
    for (final source in _sources) {
      final listener = source.listener;
      if (listener != null) {
        source.progress.removeListener(listener);
      }
    }
    _sources.clear();
    for (final notifier in _progressByModule.values) {
      notifier.dispose();
    }
    _progressByModule.clear();
  }

  void _refreshModules(Set<LibraryModuleKey> modules) {
    for (final module in modules) {
      final notifier = _progressByModule[module];
      if (notifier == null) {
        continue;
      }
      notifier.value = _selectProgress(module);
    }
  }

  LibraryShelfTaskProgress? _selectProgress(LibraryModuleKey module) {
    _RegisteredProgressSource? winner;
    LibraryShelfTaskProgress? winningProgress;
    for (final source in _sources) {
      if (!source.modules.contains(module)) {
        continue;
      }
      final progress = source.progress.value;
      if (progress == null || !progress.active) {
        continue;
      }
      if (winner == null ||
          source.priority.index > winner.priority.index ||
          (source.priority == winner.priority &&
              source.registrationSequence > winner.registrationSequence)) {
        winner = source;
        winningProgress = progress;
      }
    }
    return winningProgress;
  }
}

class _LibraryTaskProgressRegistration
    implements LibraryTaskProgressRegistration {
  _LibraryTaskProgressRegistration(this._disposeCallback);

  VoidCallback? _disposeCallback;

  @override
  void dispose() {
    final callback = _disposeCallback;
    if (callback == null) {
      return;
    }
    _disposeCallback = null;
    callback();
  }
}

class _RegisteredProgressSource {
  _RegisteredProgressSource({
    required this.modules,
    required this.progress,
    required this.priority,
    required this.registrationSequence,
  });

  final Set<LibraryModuleKey> modules;
  final ValueListenable<LibraryShelfTaskProgress?> progress;
  final LibraryTaskProgressPriority priority;
  final int registrationSequence;
  VoidCallback? listener;
}
