import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_paged_image_fit_surface.dart';

void main() {
  testWidgets('width fit gives tall images a vertical scroll extent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _hostSurface(pageFit: ReaderPageFitPreference.fitWidth, aspectRatio: 0.5),
    );
    await tester.pump();

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.vertical);
    expect(scroll.controller!.offset, 0);
    expect(scroll.controller!.position.maxScrollExtent, closeTo(200, 0.01));
    expect(
      tester.getSize(find.byKey(const Key('reader-paged-width-fit-content'))),
      const Size(300, 600),
    );
  });

  testWidgets('width fit centers images shorter than the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _hostSurface(pageFit: ReaderPageFitPreference.fitWidth, aspectRatio: 1),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    final content = find.byKey(const Key('reader-paged-width-fit-content'));
    expect(tester.getTopLeft(content).dy, closeTo(50, 0.01));
    expect(tester.getSize(content), const Size(300, 300));
  });

  testWidgets('height fit gives wide images a horizontal scroll extent', (
    tester,
  ) async {
    final overflow = <bool>[];
    await tester.pumpWidget(
      _hostSurface(
        pageFit: ReaderPageFitPreference.fitHeight,
        aspectRatio: 2,
        onHorizontalOverflowChanged: overflow.add,
      ),
    );
    await tester.pump();

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(scroll.controller!.offset, 0);
    expect(scroll.controller!.position.maxScrollExtent, closeTo(500, 0.01));
    expect(overflow, <bool>[true]);
  });

  testWidgets('RTL height fit starts wide images at the physical right edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _hostSurface(
        pageFit: ReaderPageFitPreference.fitHeight,
        readerMode: ReaderModePreference.rtl,
        aspectRatio: 2,
      ),
    );
    await tester.pump();

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.controller!.offset, closeTo(500, 0.01));
  });

  testWidgets('contain creates no baseline scroll surface', (tester) async {
    final overflow = <bool>[];
    await tester.pumpWidget(
      _hostSurface(
        pageFit: ReaderPageFitPreference.contain,
        aspectRatio: 4,
        onHorizontalOverflowChanged: overflow.add,
      ),
    );
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(overflow, <bool>[false]);
  });

  testWidgets('fit changes report cleared horizontal overflow', (tester) async {
    final overflow = <bool>[];
    var pageFit = ReaderPageFitPreference.fitHeight;
    late StateSetter rebuild;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox(
                width: 300,
                height: 400,
                child: ReaderPagedImageFitSurface(
                  ownerId: 'owner',
                  itemId: 'item',
                  pageIndex: 0,
                  pageFit: pageFit,
                  readerMode: ReaderModePreference.ltr,
                  aspectRatio: 2,
                  onHorizontalOverflowChanged: overflow.add,
                  onEdgeTurnRequested: (_) {},
                  child: const ColoredBox(color: Colors.blue),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    rebuild(() => pageFit = ReaderPageFitPreference.contain);
    await tester.pump();
    await tester.pump();

    expect(overflow, <bool>[true, false]);
  });

  testWidgets('edge overscroll below threshold does not request a turn', (
    tester,
  ) async {
    final turns = <ReaderPageTurnIntent>[];
    await tester.pumpWidget(
      _hostSurface(
        pageFit: ReaderPageFitPreference.fitHeight,
        aspectRatio: 2,
        onEdgeTurnRequested: turns.add,
      ),
    );
    await tester.pump();
    final scroll = find.byType(SingleChildScrollView);
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);

    await tester.drag(scroll, const Offset(-30, 0));
    await tester.pump();

    expect(turns, isEmpty);
  });

  testWidgets('LTR edge overscroll maps to one logical turn per gesture', (
    tester,
  ) async {
    final turns = <ReaderPageTurnIntent>[];
    await tester.pumpWidget(
      _hostSurface(
        pageFit: ReaderPageFitPreference.fitHeight,
        aspectRatio: 2,
        onEdgeTurnRequested: turns.add,
      ),
    );
    await tester.pump();
    final scroll = find.byType(SingleChildScrollView);
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    final gesture = await tester.startGesture(tester.getCenter(scroll));

    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pump();

    expect(turns, <ReaderPageTurnIntent>[ReaderPageTurnIntent.next]);
  });

  testWidgets('RTL physical edge gestures map to logical next and previous', (
    tester,
  ) async {
    final turns = <ReaderPageTurnIntent>[];
    await tester.pumpWidget(
      _hostSurface(
        pageFit: ReaderPageFitPreference.fitHeight,
        readerMode: ReaderModePreference.rtl,
        aspectRatio: 2,
        onEdgeTurnRequested: turns.add,
      ),
    );
    await tester.pump();
    final scroll = find.byType(SingleChildScrollView);
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;

    controller.jumpTo(controller.position.minScrollExtent);
    await tester.drag(scroll, const Offset(60, 0));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.drag(scroll, const Offset(-60, 0));
    await tester.pump();

    expect(turns, <ReaderPageTurnIntent>[
      ReaderPageTurnIntent.next,
      ReaderPageTurnIntent.previous,
    ]);
  });
}

Widget _hostSurface({
  required ReaderPageFitPreference pageFit,
  required double aspectRatio,
  ReaderModePreference readerMode = ReaderModePreference.ltr,
  ValueChanged<bool>? onHorizontalOverflowChanged,
  ValueChanged<ReaderPageTurnIntent>? onEdgeTurnRequested,
}) {
  return LocalizedTestApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 400,
          child: ReaderPagedImageFitSurface(
            ownerId: 'owner',
            itemId: 'item',
            pageIndex: 0,
            pageFit: pageFit,
            readerMode: readerMode,
            aspectRatio: aspectRatio,
            onHorizontalOverflowChanged: onHorizontalOverflowChanged ?? (_) {},
            onEdgeTurnRequested: onEdgeTurnRequested ?? (_) {},
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    ),
  );
}
