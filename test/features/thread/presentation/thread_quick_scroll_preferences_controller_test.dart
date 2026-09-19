import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/thread/data/providers/thread_quick_scroll_preferences_providers.dart';
import 'package:y300/features/thread/data/repositories/shared_preferences_thread_quick_scroll_repository.dart';
import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';
import 'package:y300/features/thread/domain/repositories/thread_quick_scroll_preferences_repository.dart';
import 'package:y300/features/thread/presentation/thread_quick_scroll_preferences_controller.dart';

const _left = ThreadQuickScrollDockSide.left;
const _right = ThreadQuickScrollDockSide.right;
final _provider = threadQuickScrollPreferencesControllerProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final raw in <Object?>[null, 'broken', 17, 'right', 'left']) {
    test('stored side $raw loads with a safe default', () async {
      SharedPreferences.setMockInitialValues({
        PreferenceKeys.threadQuickScrollDockSide.name: ?raw,
      });
      final repository = SharedPreferencesThreadQuickScrollRepository(
        SharedPreferencesStore(),
      );
      expect(await repository.loadSide(), raw == 'left' ? _left : _right);
    });
  }

  test('a new provider container restores the saved side', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    expect(await first.read(_provider.future), _right);
    expect(await first.read(_provider.notifier).setSide(_left), isTrue);
    first.dispose();
    final second = ProviderContainer();
    addTearDown(second.dispose);
    expect(await second.read(_provider.future), _left);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {
      PreferenceKeys.threadQuickScrollDockSide.name,
    });
    expect(
      preferences.getString(PreferenceKeys.threadQuickScrollDockSide.name),
      'left',
    );
  });

  test('read failure falls back to right', () async {
    final repository = _Repository()..failRead = true;
    final container = _container(repository);
    expect(await container.read(_provider.future), _right);
  });

  test('unchanged side does not write', () async {
    final repository = _Repository();
    final container = _container(repository);
    await container.read(_provider.future);
    await container.read(_provider.notifier).setSide(_right);
    expect(repository.writes, isEmpty);
  });

  test('rapid choices update immediately but writes run in order', () async {
    final repository = _Repository();
    final container = _container(repository);
    await container.read(_provider.future);
    final controller = container.read(_provider.notifier);
    final first = controller.setSide(_left);
    final second = controller.setSide(_right);
    final third = controller.setSide(_left);
    expect(container.read(_provider).requireValue, _left);
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes, [_left]);
    repository.pending[0].complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes, [_left, _right]);
    repository.pending[1].complete();
    await second;
    await Future<void>.delayed(Duration.zero);
    expect(repository.writes, [_left, _right, _left]);
    repository.pending[2].complete();
    expect(await third, isTrue);
    expect(container.read(_provider).requireValue, _left);
  });

  test('stale failure cannot roll back a newer optimistic choice', () async {
    final repository = _Repository();
    final container = _container(repository);
    await container.read(_provider.future);
    final controller = container.read(_provider.notifier);
    final first = controller.setSide(_left);
    final second = controller.setSide(_right);
    await Future<void>.delayed(Duration.zero);
    repository.pending[0].completeError(StateError('write failed'));
    expect(await first, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(_provider).requireValue, _right);
    repository.pending[1].complete();
    expect(await second, isTrue);
  });

  test(
    'latest failure rolls back to the last successful queued write',
    () async {
      final repository = _Repository();
      final container = _container(repository);
      await container.read(_provider.future);
      final controller = container.read(_provider.notifier);
      final first = controller.setSide(_left);
      final second = controller.setSide(_right);
      await Future<void>.delayed(Duration.zero);
      repository.pending[0].complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      repository.pending[1].completeError(StateError('write failed'));
      expect(await second, isFalse);
      expect(container.read(_provider).requireValue, _left);
    },
  );

  test(
    'finishing a failed save after disposal does not update state',
    () async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          threadQuickScrollPreferencesRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      await container.read(_provider.future);
      final save = container.read(_provider.notifier).setSide(_left);
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      repository.pending.single.completeError(StateError('write failed'));
      expect(await save, isTrue);
    },
  );
}

ProviderContainer _container(_Repository repository) {
  final container = ProviderContainer(
    overrides: [
      threadQuickScrollPreferencesRepositoryProvider.overrideWithValue(
        repository,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _Repository implements ThreadQuickScrollPreferencesRepository {
  bool failRead = false;
  final writes = <ThreadQuickScrollDockSide>[];
  final pending = <Completer<void>>[];

  @override
  Future<ThreadQuickScrollDockSide> loadSide() async {
    if (failRead) throw StateError('read failed');
    return _right;
  }

  @override
  Future<void> saveSide(ThreadQuickScrollDockSide side) {
    writes.add(side);
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  }
}
