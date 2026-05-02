import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/more/data/more_settings_repository.dart';
import 'package:y300/features/more/presentation/cache_settings_controller.dart';
import 'package:y300/features/more/presentation/cache_settings_page.dart';

void main() {
  testWidgets('CacheSettingsPage renders default and effective directory', (tester) async {
    final repo = _FakeMoreSettingsRepository(
      defaultDir: '/tmp/default',
      customDir: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moreSettingsRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: CacheSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cache-settings-default-directory')), findsOneWidget);
    expect(find.text('/tmp/default'), findsNWidgets(2));
    expect(find.byKey(const Key('cache-settings-custom-directory')), findsNothing);
  });

  testWidgets('CacheSettingsPage chooses custom directory and shows hint', (tester) async {
    final repo = _FakeMoreSettingsRepository(
      defaultDir: '/tmp/default',
      customDir: null,
      pickedDir: '/mnt/comic-cache',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moreSettingsRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: CacheSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cache-settings-choose-directory-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cache-settings-custom-directory')), findsOneWidget);
    expect(find.text('/mnt/comic-cache'), findsNWidgets(2));
    expect(find.text('缓存目录已更新'), findsOneWidget);
  });

  testWidgets('CacheSettingsPage restores default directory', (tester) async {
    final repo = _FakeMoreSettingsRepository(
      defaultDir: '/tmp/default',
      customDir: '/mnt/comic-cache',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moreSettingsRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: CacheSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cache-settings-restore-default-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cache-settings-custom-directory')), findsNothing);
    expect(find.text('已恢复默认目录'), findsOneWidget);
    expect(find.text('/tmp/default'), findsNWidgets(2));
  });
}

class _FakeMoreSettingsRepository implements MoreSettingsRepository {
  _FakeMoreSettingsRepository({
    required String defaultDir,
    required String? customDir,
    this.pickedDir,
  })  : _defaultDir = defaultDir,
        _customDir = customDir;

  final String _defaultDir;
  String? _customDir;
  final String? pickedDir;

  @override
  Future<String> getDefaultCacheDirectory() async => _defaultDir;

  @override
  Future<String?> getCustomCacheDirectory() async => _customDir;

  @override
  Future<String?> pickDirectory() async => pickedDir;

  @override
  Future<void> setCustomCacheDirectory(String? path) async {
    _customDir = path;
  }
}
