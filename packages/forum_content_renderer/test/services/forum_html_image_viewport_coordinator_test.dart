import 'package:flutter/material.dart';
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
