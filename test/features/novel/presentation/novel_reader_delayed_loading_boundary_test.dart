import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_delayed_loading_boundary.dart';

void main() {
  testWidgets('delays the neutral loading surface', (tester) async {
    await tester.pumpWidget(
      _host(
        identity: 'chapter-1',
        isLoading: true,
        child: const Text('old chapter'),
      ),
    );

    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 299));
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 1));
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsOneWidget,
    );
    final surface = tester.widget<ColoredBox>(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
    );
    expect(surface.color, const Color(0xFFF4EAD7));
  });

  testWidgets('keeps one timer across preparation phases', (tester) async {
    await tester.pumpWidget(
      _host(
        identity: 'chapter-1',
        isLoading: true,
        child: const Text('preparing'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    await tester.pumpWidget(
      _host(
        identity: 'chapter-1',
        isLoading: true,
        child: const Text('calculating'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 49));
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 1));
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('mounts only the new child while a new identity loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        identity: 'chapter-1',
        isLoading: false,
        child: const Text('chapter one'),
      ),
    );

    await tester.pumpWidget(
      _host(
        identity: 'chapter-2',
        isLoading: true,
        child: const Text('chapter two'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 299));

    expect(find.text('chapter one'), findsNothing);
    expect(find.text('chapter two'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('chapter one'), findsNothing);
    expect(find.text('chapter two'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _host(
        identity: 'chapter-2',
        isLoading: false,
        child: const Text('chapter two'),
      ),
    );
    await tester.pump();
    expect(find.text('chapter one'), findsNothing);
    expect(find.text('chapter two'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );
  });

  testWidgets('fast completion cancels the delayed indicator', (tester) async {
    await tester.pumpWidget(
      _host(
        identity: 'chapter-1',
        isLoading: true,
        child: const Text('old chapter'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      _host(
        identity: 'chapter-1',
        isLoading: false,
        child: const Text('new chapter'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const Key('novel-reader-delayed-loading-indicator')),
      findsNothing,
    );
    expect(find.text('new chapter'), findsOneWidget);
  });

  testWidgets('blocks input while a chapter is loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        identity: 'chapter-1',
        isLoading: true,
        child: GestureDetector(
          onTap: () => taps += 1,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );

    await tester.tapAt(const Offset(50, 50));
    expect(taps, 0);
  });
}

Widget _host({
  required Object identity,
  required bool isLoading,
  required Widget child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: NovelReaderDelayedLoadingBoundary(
        identity: identity,
        isLoading: isLoading,
        backgroundColor: const Color(0xFFF4EAD7),
        child: child,
      ),
    ),
  );
}
