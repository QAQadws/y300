import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_surface.dart';

void main() {
  testWidgets('feedback states expose stable semantics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicCommentFeedbackSurface(
            kind: ComicCommentFeedbackKind.unavailable,
            onAction: () {},
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(
      find.text(ComicCommentCopy.unavailable),
    );
    expect(semantics.label, ComicCommentCopy.unavailable);
    expect(find.text(ComicCommentCopy.retry), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComicCommentFeedbackSurface(
            kind: ComicCommentFeedbackKind.loading,
          ),
        ),
      ),
    );
    final loadingSemantics = tester.getSemantics(
      find.byType(ComicCommentFeedbackSurface),
    );
    expect(loadingSemantics.label, ComicCommentCopy.loading);
  });

  testWidgets('consolidated feedback states keep a local visual baseline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() async {
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: Scaffold(
          body: ListView(
            children: [
              const ComicCommentFeedbackSurface(
                kind: ComicCommentFeedbackKind.loading,
                compact: true,
              ),
              const ComicCommentFeedbackSurface(
                kind: ComicCommentFeedbackKind.empty,
                compact: true,
              ),
              ComicCommentFeedbackSurface(
                kind: ComicCommentFeedbackKind.unavailable,
                onAction: () {},
                compact: true,
              ),
              ComicCommentFeedbackSurface(
                kind: ComicCommentFeedbackKind.open,
                onAction: () {},
                compact: true,
              ),
              const ComicCommentFeedbackSurface(
                kind: ComicCommentFeedbackKind.advance,
                nextEpisodeTitle: '第 2 话',
                compact: true,
              ),
              const ComicCommentFeedbackSurface(
                kind: ComicCommentFeedbackKind.lastChapter,
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/comic_comment_feedback_surface.png'),
    );
  });
}
