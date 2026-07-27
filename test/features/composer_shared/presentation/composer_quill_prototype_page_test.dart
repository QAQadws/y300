import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_sticker_image_cache_loader.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_page.dart';

void main() {
  testWidgets('ComposerQuillPrototypePage switches source and quill', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-prototype-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-source-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-bbcode-output')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('composer-quill-prototype-source-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-prototype-source-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-source-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-preview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-quill-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-quill-source-sticker-button')),
      findsOneWidget,
    );
    var sourceField = tester.widget<TextField>(
      find.byKey(const Key('composer-quill-prototype-source-input')),
    );
    final sourceDecoration = sourceField.decoration;
    expect(sourceDecoration?.border, InputBorder.none);
    expect(sourceDecoration?.enabledBorder, InputBorder.none);
    expect(sourceDecoration?.focusedBorder, InputBorder.none);
    expect(sourceDecoration?.disabledBorder, InputBorder.none);
    expect(sourceDecoration?.filled, isFalse);
    expect(sourceDecoration?.fillColor, isNull);

    await tester.enterText(
      find.byKey(const Key('composer-quill-prototype-source-input')),
      '[b]源码[/b]',
    );
    await tester.tap(
      find.byKey(const Key('composer-quill-prototype-quill-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-prototype-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-source-input')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-preview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('composer-quill-prototype-source-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('composer-quill-prototype-source-button')),
    );
    await tester.pumpAndSettle();

    sourceField = tester.widget<TextField>(
      find.byKey(const Key('composer-quill-prototype-source-input')),
    );
    expect(sourceField.controller?.text, '[b]源码[/b]');
  });
}

Widget _buildPage() {
  return ProviderScope(
    overrides: [
      stickerGroupsProvider.overrideWith((_) async => [_group()]),
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
      composerStickerImageCacheLoaderProvider.overrideWithValue(
        ComposerStickerImageCacheLoader(
          imageCacheService: _FailingImageCacheService(),
          networkGap: Duration.zero,
          delay: (_) async {},
        ),
      ),
    ],
    child: LocalizedTestApp(
      theme: AppTheme.light(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: const ComposerQuillPrototypePage(),
    ),
  );
}

StickerGroup _group() {
  return StickerGroup(id: 'bugcat', title: '貓貓蟲', stickers: [_sticker()]);
}

StickerItem _sticker() {
  return const StickerItem(
    code: '{:9_656:}',
    rawCodePattern: '{:9_656:}',
    imagePath: 'bugcat/Capoo16.gif',
    imageUrl: 'https://bbs.yamibo.com/static/image/smiley/bugcat/Capoo16.gif',
    cacheKey: 'remote-smiley:bugcat/Capoo16.gif',
  );
}

class _FailingImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    return null;
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async {
    return 0;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }
}
