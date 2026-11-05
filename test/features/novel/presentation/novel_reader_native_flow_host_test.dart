import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_owner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_flow_host.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/native_reader_image_test_host.dart';

void main() {
  testWidgets(
    'flow readiness follows current mounted image frames and failure',
    (tester) async {
      const html = '<p>before</p><img src="https://x/tall.png"><p>after</p>';
      final document =
          const DiscuzNovelReaderDocumentParser(captureSourceProvenance: true)
              .parse(
                episodeId: 'chapter',
                rawHtml: html,
                fallbackParagraphs: const [],
              );
      final owner = NovelReaderNativeOwner();
      final scroll = ScrollController();
      final host = NativeReaderImageTestHost(aspectRatio: .1);
      addTearDown(owner.dispose);
      addTearDown(scroll.dispose);
      final readiness = <bool>[];
      var ready = false;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Align(
            child: SizedBox(
              width: 200,
              height: 160,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  NovelReaderNativeFlowHost(
                    owner: owner,
                    readingAuthority: 'read',
                    sourceId: 'chapter',
                    rawHtml: html,
                    document: document,
                    preferences: NovelReaderPreferences.defaults().copyWith(
                      flowMode: NovelReaderFlowMode.vertical,
                    ),
                    resolvedFont: ResolvedFont.system,
                    converter: const IdentityTextConverter(),
                    preparationService:
                        const DefaultNovelReaderNativePreparationService(),
                    width: 200,
                    scrollController: scroll,
                    imageHost: host,
                    imagePolicy: host,
                    threadId: null,
                    idleScheduler: () async {},
                    onContentReady: () => ready = true,
                    onContentTerminal: () => fail('Native flow terminated'),
                    onImagesReadyChanged: readiness.add,
                    onInteraction: () {},
                    onImageTap: (_) {},
                    onTextSelection: (_) {},
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 150 && !ready; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(ready, isTrue);
      expect(readiness.last, isFalse);
      final first = host.callback(0);
      first.frame!();
      await tester.pumpAndSettle();
      expect(readiness.last, isTrue);
      first.failed!();
      await tester.pumpAndSettle();
      expect(readiness.last, isFalse);

      final flow = tester.widget<ForumBodyFlowSliver>(
        find.byType(ForumBodyFlowSliver),
      );
      final imageEnd = flow.prefix
          .take(2)
          .fold<double>(0, (sum, page) => sum + page.usedHeight);
      scroll.jumpTo(imageEnd);
      await tester.pumpAndSettle();
      expect(find.byType(ForumHtmlImageView), findsNothing);
      expect(readiness.last, isTrue);

      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(readiness.last, isFalse);
      first.frame!();
      await tester.pumpAndSettle();
      expect(readiness.last, isFalse);
      host.callback(0).frame!();
      await tester.pumpAndSettle();
      expect(readiness.last, isTrue);
      host.completeDimensions();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owner.activeCacheHandles, 0);
    },
  );
}
