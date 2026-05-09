import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
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
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
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
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
        child: const MaterialApp(home: CacheSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    final chooseButton = find.byKey(const Key('cache-settings-choose-directory-button'));
    await tester.scrollUntilVisible(
      chooseButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(chooseButton);
    await _tapVisibleCenter(tester, chooseButton);
    await tester.pumpAndSettle();

    final customDirectory = find.byKey(const Key('cache-settings-custom-directory'));
    await tester.scrollUntilVisible(
      customDirectory,
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(customDirectory, findsOneWidget);
    expect(find.text('/mnt/comic-cache'), findsAtLeastNWidgets(1));

    await tester.scrollUntilVisible(
      find.byKey(const Key('cache-settings-hint-text')),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('存储位置已更新'), findsOneWidget);
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
          imageCacheServiceProvider.overrideWithValue(_FakeImageCacheService()),
        ],
        child: const MaterialApp(home: CacheSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    final restoreButton = find.byKey(const Key('cache-settings-restore-default-button'));
    await tester.scrollUntilVisible(
      restoreButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(restoreButton);
    await _tapVisibleCenter(tester, restoreButton);
    await tester.pumpAndSettle();
    expect(repo.customDir, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('cache-settings-default-directory')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('cache-settings-custom-directory')), findsNothing);
    expect(find.text('/tmp/default'), findsAtLeastNWidgets(1));

    await tester.scrollUntilVisible(
      find.byKey(const Key('cache-settings-hint-text')),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('cache-settings-custom-directory')), findsNothing);
    expect(find.text('已恢复默认存储位置'), findsOneWidget);
  });
}

Future<void> _tapVisibleCenter(WidgetTester tester, Finder finder) async {
  final renderBox = tester.renderObject<RenderBox>(finder);
  final topLeft = renderBox.localToGlobal(Offset.zero);
  final bottomRight = renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero));
  final rootSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  final visibleLeft = topLeft.dx.clamp(0.0, rootSize.width).toDouble();
  final visibleTop = topLeft.dy.clamp(0.0, rootSize.height).toDouble();
  final visibleRight = bottomRight.dx.clamp(0.0, rootSize.width).toDouble();
  final visibleBottom = bottomRight.dy.clamp(0.0, rootSize.height).toDouble();
  await tester.tapAt(
    Offset(
      (visibleLeft + visibleRight) / 2,
      (visibleTop + visibleBottom) / 2,
    ),
  );
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
  int _maxBytes = 512 * 1024 * 1024;

  String? get customDir => _customDir;

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

  @override
  Future<int> getImageCacheMaxBytes() async => _maxBytes;

  @override
  Future<void> setImageCacheMaxBytes(int bytes) async {
    _maxBytes = bytes;
  }
}

class _FakeImageCacheService implements ImageCacheService {
  int usageBytes = 0;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: 'memory://${request.cacheKey}',
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
      fromCache: true,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async {
    return usageBytes;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {
    if (usageBytes > maxBytes) {
      usageBytes = maxBytes;
    }
  }

  @override
  Future<void> clearUnprotected() async {
    usageBytes = 0;
  }
}
