import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  testWidgets('prioritizes visible images and pauses when route is inactive', (
    tester,
  ) async {
    final coordinator = ForumHtmlImageViewportCoordinator();
    addTearDown(coordinator.dispose);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final handles = List<ForumHtmlImageViewportHandle>.generate(
      5,
      (_) => coordinator.register(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView(
              controller: controller,
              children: [
                for (final handle in handles)
                  _BoundImage(handle: handle, height: 200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      handles.where(
        (handle) => handle.value == ForumHtmlImageViewportMode.display,
      ),
      hasLength(2),
    );
    expect(
      handles.where(
        (handle) => handle.value == ForumHtmlImageViewportMode.prefetch,
      ),
      isEmpty,
    );

    handles.first.reportFirstFrameSettled();
    await tester.pump();
    await tester.pump();
    expect(
      handles.where(
        (handle) => handle.value == ForumHtmlImageViewportMode.prefetch,
      ),
      hasLength(1),
    );

    final prefetch = handles.singleWhere(
      (handle) => handle.value == ForumHtmlImageViewportMode.prefetch,
    );
    final transitions = <ForumHtmlImageViewportMode>[];
    prefetch.addListener(() => transitions.add(prefetch.value));
    for (var i = 1; i <= 30; i++) {
      controller.jumpTo(i.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(prefetch.value, ForumHtmlImageViewportMode.prefetch);
    expect(
      transitions,
      isEmpty,
      reason: 'The same prefetch must remain stable during scrolling.',
    );

    handles.first.reportLoadStarted();
    await tester.pump();
    await tester.pump();
    expect(
      handles.where(
        (handle) => handle.value == ForumHtmlImageViewportMode.prefetch,
      ),
      isEmpty,
    );

    controller.jumpTo(500);
    await tester.pump();
    await tester.pump();

    expect(handles.first.value, ForumHtmlImageViewportMode.dormant);
    expect(
      handles.where(
        (handle) => handle.value == ForumHtmlImageViewportMode.display,
      ),
      isNotEmpty,
    );

    coordinator.setActive(false);
    await tester.pump();
    expect(
      handles.every(
        (handle) => handle.value == ForumHtmlImageViewportMode.dormant,
      ),
      isTrue,
    );
  });

  for (final outerIsList in [true, false]) {
    testWidgets(
      'nested horizontal images follow the outer ${outerIsList ? 'ListView' : 'SingleChildScrollView'}',
      (tester) async {
        final coordinator = ForumHtmlImageViewportCoordinator();
        final vertical = ScrollController();
        final horizontal = ScrollController();
        addTearDown(() {
          coordinator.dispose();
          vertical.dispose();
          horizontal.dispose();
        });
        final head = coordinator.register();
        final tableUpper = coordinator.register();
        final tableLower = coordinator.register();
        final afterTable = coordinator.register();
        final children = <Widget>[
          _BoundImage(handle: head, height: 100),
          const SizedBox(height: 100),
          SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 500),
                  _BoundImage(handle: tableUpper, height: 100),
                  const SizedBox(height: 200),
                  _BoundImage(handle: tableLower, height: 100),
                ],
              ),
            ),
          ),
          _BoundImage(handle: afterTable, height: 100),
          const SizedBox(height: 500),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  height: 300,
                  child: outerIsList
                      ? ListView(
                          controller: vertical,
                          padding: EdgeInsets.zero,
                          // Keep the same handles mounted as real HTML table
                          // descendants; this is a placement/scheduling test.
                          scrollCacheExtent: const ScrollCacheExtent.pixels(
                            2000,
                          ),
                          children: children,
                        )
                      : SingleChildScrollView(
                          controller: vertical,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(head.value, ForumHtmlImageViewportMode.display);
        expect(tableUpper.value, ForumHtmlImageViewportMode.dormant);
        expect(tableLower.value, ForumHtmlImageViewportMode.dormant);
        expect(afterTable.value, ForumHtmlImageViewportMode.dormant);

        // The lower table image lies 800px into the horizontal viewport. Its
        // outer vertical placement, together with the following ordinary image,
        // becomes visible here despite exceeding that viewport's 320px width.
        vertical.jumpTo(950);
        await tester.pump();
        await tester.pump();
        expect(head.value, ForumHtmlImageViewportMode.dormant);
        expect(tableLower.value, ForumHtmlImageViewportMode.display);
        expect(afterTable.value, ForumHtmlImageViewportMode.display);

        horizontal.jumpTo(160);
        await tester.pump();
        await tester.pump();
        expect(vertical.offset, 950);
        expect(tableLower.value, ForumHtmlImageViewportMode.display);
        expect(afterTable.value, ForumHtmlImageViewportMode.display);

        vertical.jumpTo(0);
        await tester.pump();
        await tester.pump();
        expect(head.value, ForumHtmlImageViewportMode.display);
        expect(tableUpper.value, ForumHtmlImageViewportMode.dormant);
        expect(tableLower.value, ForumHtmlImageViewportMode.dormant);
        expect(afterTable.value, ForumHtmlImageViewportMode.dormant);

        horizontal.jumpTo(240);
        await tester.pump();
        vertical.jumpTo(650);
        await tester.pump();
        await tester.pump();
        expect(tableUpper.value, ForumHtmlImageViewportMode.display);
        expect(head.value, ForumHtmlImageViewportMode.dormant);
        expect(afterTable.value, isNot(ForumHtmlImageViewportMode.display));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _BoundImage extends StatelessWidget {
  const _BoundImage({required this.handle, required this.height});

  final ForumHtmlImageViewportHandle handle;
  final double height;

  @override
  Widget build(BuildContext context) {
    handle.bind(context);
    return SizedBox(height: height);
  }
}
