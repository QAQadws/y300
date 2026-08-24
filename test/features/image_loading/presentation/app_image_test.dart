import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/image_loading/data/app_image_cache_manager.dart';
import 'package:y300/features/image_loading/data/app_image_providers.dart';
import 'package:y300/features/image_loading/domain/app_image_source.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  Widget wrap(
    Widget child, {
    Future<AppImageCacheManager>? cacheManager,
    AsyncValue<AppImageCacheManager>? cacheManagerValue,
  }) {
    return ProviderScope(
      overrides: [
        if (cacheManager != null)
          appImageCacheManagerProvider.overrideWith((ref) => cacheManager),
        if (cacheManagerValue != null)
          appImageCacheManagerProvider.overrideWithValue(cacheManagerValue),
      ],
      child: LocalizedTestApp(home: child),
    );
  }

  testWidgets('shows placeholder when no local file and no network source', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const AppImage(
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('waits for the shared cache manager without falling back', (
    tester,
  ) async {
    final pendingManager = Completer<AppImageCacheManager>();
    await tester.pumpWidget(
      wrap(
        AppImage(
          localPath: 'E:/synthetic/missing-cover.jpg',
          networkSource: NetworkAppImageSource(
            url: 'https://bbs.yamibo.com/data/attachment/cover.jpg',
            referer: 'https://bbs.yamibo.com/thread-1-1-1.html',
          ),
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
        cacheManager: pendingManager.future,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('default avatar urls resolve to error placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AppImage(
          networkSource: NetworkAppImageSource(
            url: 'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
          ),
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          errorPlaceholder: const SizedBox(key: Key('error')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('error')), findsOneWidget);
  });

  test('network source retains only cache identity and referer', () {
    final source = NetworkAppImageSource(
      url: 'data/attachment/forum/image.jpg',
      cacheKey: 'thread-image-1',
      referer: 'https://bbs.yamibo.com/thread-1-1-1.html',
    );

    expect(
      source.resolvedUrl,
      'https://bbs.yamibo.com/data/attachment/forum/image.jpg',
    );
    expect(source.cacheKey, 'thread-image-1');
    expect(source.referer, 'https://bbs.yamibo.com/thread-1-1-1.html');
  });

  testWidgets('cache manager failure fails closed', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppImage(
          networkSource: NetworkAppImageSource(
            url: 'https://bbs.yamibo.com/data/attachment/protected.jpg',
          ),
          fit: BoxFit.contain,
          placeholder: const SizedBox(key: Key('placeholder')),
          errorPlaceholder: const SizedBox(key: Key('error')),
        ),
        cacheManagerValue: AsyncValue<AppImageCacheManager>.error(
          StateError('synthetic cache manager failure'),
          StackTrace.empty,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('error')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
