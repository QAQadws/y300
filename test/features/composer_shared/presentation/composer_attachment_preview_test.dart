import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_preview_models.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_attachment_preview.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';
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
  });

  testWidgets('canonicalizes Discuz attachment URL before AppImage requests it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _build(
        const ComposerAttachmentResolution(
          aid: '1624572',
          availability: ComposerAttachmentAvailability.available,
          preview: ComposerRemoteImagePreview(
            url:
                'https://bbs.yamibo.com/data/attachment//forum/202607/23/145701yziurruujso97oud.jpg',
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
  });
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
            return SizedBox(key: const Key('local-preview'));
          },
        ),
      ),
    ),
  );
}
