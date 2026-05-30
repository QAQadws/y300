import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

void main() {
  group('DefaultLibraryTaskProgressHub', () {
    test('forwards single-module progress', () {
      final hub = DefaultLibraryTaskProgressHub();
      final source = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(message: 'sync'),
      );
      final registration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        progress: source,
      );
      addTearDown(source.dispose);
      addTearDown(registration.dispose);
      addTearDown(hub.dispose);

      expect(hub.progressFor(LibraryModuleKey.favorite).value?.message, 'sync');
      expect(hub.progressFor(LibraryModuleKey.comic).value, isNull);
    });

    test('higher priority source wins', () {
      final hub = DefaultLibraryTaskProgressHub();
      final low = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(message: 'low'),
      );
      final high = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(message: 'high'),
      );
      final lowRegistration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        progress: low,
        priority: LibraryTaskProgressPriority.low,
      );
      final highRegistration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        progress: high,
        priority: LibraryTaskProgressPriority.high,
      );
      addTearDown(low.dispose);
      addTearDown(high.dispose);
      addTearDown(lowRegistration.dispose);
      addTearDown(highRegistration.dispose);
      addTearDown(hub.dispose);

      expect(hub.progressFor(LibraryModuleKey.favorite).value?.message, 'high');
    });

    test('later registration wins when priority ties', () {
      final hub = DefaultLibraryTaskProgressHub();
      final first = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(message: 'first'),
      );
      final second = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(message: 'second'),
      );
      final firstRegistration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        progress: first,
      );
      final secondRegistration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        progress: second,
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(firstRegistration.dispose);
      addTearDown(secondRegistration.dispose);
      addTearDown(hub.dispose);

      expect(hub.progressFor(LibraryModuleKey.comic).value?.message, 'second');
    });

    test('disposing winning source falls back to remaining source', () {
      final hub = DefaultLibraryTaskProgressHub();
      final first = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(message: 'first'),
      );
      final second = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(message: 'second'),
      );
      final firstRegistration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        progress: first,
      );
      final secondRegistration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
        progress: second,
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(firstRegistration.dispose);
      addTearDown(hub.dispose);

      secondRegistration.dispose();

      expect(hub.progressFor(LibraryModuleKey.favorite).value?.message, 'first');
    });

    test('source can drive multiple modules', () {
      final hub = DefaultLibraryTaskProgressHub();
      final source = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(
          message: 'queue',
          source: LibraryMutationSource.comicSearchQueue,
        ),
      );
      final registration = hub.registerSource(
        modules: const <LibraryModuleKey>{
          LibraryModuleKey.comic,
          LibraryModuleKey.favorite,
        },
        progress: source,
      );
      addTearDown(source.dispose);
      addTearDown(registration.dispose);
      addTearDown(hub.dispose);

      expect(hub.progressFor(LibraryModuleKey.comic).value?.message, 'queue');
      expect(
        hub.progressFor(LibraryModuleKey.favorite).value?.source,
        LibraryMutationSource.comicSearchQueue,
      );
    });

    test('active hidden progress still flows through hub', () {
      final hub = DefaultLibraryTaskProgressHub();
      final source = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(
          message: 'warming',
          source: LibraryMutationSource.coverWarmup,
          visible: false,
        ),
      );
      final registration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        progress: source,
      );
      addTearDown(source.dispose);
      addTearDown(registration.dispose);
      addTearDown(hub.dispose);

      final progress = hub.progressFor(LibraryModuleKey.comic).value;
      expect(progress?.message, 'warming');
      expect(progress?.source, LibraryMutationSource.coverWarmup);
      expect(progress?.visible, isFalse);
    });

    test('inactive progress is ignored even when hidden', () {
      final hub = DefaultLibraryTaskProgressHub();
      final source = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(
          message: 'warming',
          source: LibraryMutationSource.coverWarmup,
          visible: false,
          active: false,
        ),
      );
      final registration = hub.registerSource(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        progress: source,
      );
      addTearDown(source.dispose);
      addTearDown(registration.dispose);
      addTearDown(hub.dispose);

      expect(hub.progressFor(LibraryModuleKey.comic).value, isNull);
    });
  });
}
