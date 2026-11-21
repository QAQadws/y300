import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_attachment_preview.dart';
import 'package:y300/features/image_loading/data/app_image_cache_manager.dart';
import 'package:y300/features/image_loading/data/app_image_providers.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';
import 'package:y300/shared/widgets/forum_media_loading_style.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('renders a local resolver source with the injected builder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _build(
        const ComposerAttachmentResolution(
          aid: '123',
          availability: ComposerAttachmentAvailability.available,
          preview: ComposerLocalImagePreview('/tmp/123.jpg'),
        ),
        localFileExists: (_) => true,
      ),
    );

    expect(find.byKey(const Key('local-preview')), findsOneWidget);
    expect(find.byType(AppImage), findsNothing);
  });

  testWidgets('renders a remote resolver source with AppImage', (tester) async {
    await tester.pumpWidget(
      _build(
        const ComposerAttachmentResolution(
          aid: '123',
          availability: ComposerAttachmentAvailability.available,
          preview: ComposerRemoteImagePreview(
            url: 'https://bbs.yamibo.com/data/attachment/123.jpg',
            referer: 'https://bbs.yamibo.com/forum.php?mod=post',
          ),
        ),
      ),
    );

    final image = tester.widget<AppImage>(find.byType(AppImage));
    expect(
      image.networkSource?.resolvedUrl,
      'https://bbs.yamibo.com/data/attachment/123.jpg',
    );
    expect(
      image.networkSource?.referer,
      'https://bbs.yamibo.com/forum.php?mod=post',
    );
    expect(image.fadeInDuration, Duration.zero);
  });

  testWidgets('a fixed attachment slot keeps its geometry on load failure', (
    tester,
  ) async {
    final manager = Completer<AppImageCacheManager>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appImageCacheManagerProvider.overrideWith((_) => manager.future),
        ],
        child: const LocalizedTestApp(
          home: Center(
            child: ComposerAttachmentPreviewImage.thumbnail(
              resolution: ComposerAttachmentResolution(
                aid: '123',
                availability: ComposerAttachmentAvailability.available,
                preview: ComposerRemoteImagePreview(
                  url: 'https://bbs.yamibo.com/data/attachment/123.jpg',
                  referer: 'https://bbs.yamibo.com/forum.php?mod=post',
                ),
              ),
              width: 96,
              height: 88,
            ),
          ),
        ),
      ),
    );

    final image = find.byType(AppImage);
    final slot = tester.getRect(image);
    expect(slot.size, const Size(96, 88));
    expect(
      tester.widget<AppImage>(image).fadeInDuration,
      ForumMediaLoadingStyle.fadeInDuration,
    );
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    manager.completeError(StateError('fixture cache manager failure'));
    await tester.pumpAndSettle();
    expect(tester.getRect(image), slot);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.broken_image_outlined)),
      slot.center,
    );
  });

  testWidgets(
    'canonicalizes Discuz attachment URL before AppImage requests it',
    (tester) async {
      await tester.pumpWidget(
        _build(
          const ComposerAttachmentResolution(
            aid: '1624572',
            availability: ComposerAttachmentAvailability.available,
            preview: ComposerRemoteImagePreview(
              url: 'https://bbs.yamibo.com/data/attachment//forum/202607/23/145701yziurruujso97oud.jpg',
              referer: 'https://bbs.yamibo.com/forum.php?mod=post',
            ),
          ),
        ),
      );

      final image = tester.widget<AppImage>(find.byType(AppImage));
      expect(
        image.networkSource?.resolvedUrl,
        'https://bbs.yamibo.com/data/attachment/forum/202607/23/145701yziurruujso97oud.jpg',
      );
      expect(
        image.networkSource?.referer,
        'https://bbs.yamibo.com/forum.php?mod=post',
      );
    },
  );
}

Widget _build(
  ComposerAttachmentResolution resolution, {
  ComposerLocalFileExists? localFileExists,
}) {
  return ProviderScope(
    child: LocalizedTestApp(
      home: Scaffold(
        body: ComposerAttachmentPreviewImage(
          resolution: resolution,
          maxWidth: 320,
          localFileExists: localFileExists ?? (_) => false,
          localImageBuilder: (File _, Key key) {
            return const SizedBox(key: Key('local-preview'));
          },
        ),
      ),
    ),
  );
}
