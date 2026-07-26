import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';

void main() {
  testWidgets('roomy box shows message and retry button', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 400,
              child: ImageRetryPlaceholder(
                onRetry: () => retries += 1,
                retryButtonKey: const Key('retry'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('图片加载失败'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry')));
    expect(retries, 1);
  });

  testWidgets('short box degrades to a single compact row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 72,
              child: ImageRetryPlaceholder(onRetry: _noop),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('图片加载失败'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('very short box degrades to a tappable icon only', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 28,
              child: ImageRetryPlaceholder(
                onRetry: () => retries += 1,
                retryButtonKey: const Key('retry'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('图片加载失败'), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry')));
    expect(retries, 1);
  });

  testWidgets('narrow box degrades to a tappable icon only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 96,
              height: 400,
              child: ImageRetryPlaceholder(onRetry: _noop),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('图片加载失败'), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('unbounded height keeps the full panel', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImageRetryPlaceholder(onRetry: _noop),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
  });
}

void _noop() {}
