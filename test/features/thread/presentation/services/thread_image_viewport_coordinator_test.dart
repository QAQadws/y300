import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_image_viewport_coordinator.dart';

void main() {
  testWidgets('prioritizes visible images and pauses when route is inactive', (
    tester,
  ) async {
    final coordinator = ThreadImageViewportCoordinator();
    addTearDown(coordinator.dispose);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final handles = List<ThreadImageViewportHandle>.generate(
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
        (handle) => handle.value == ThreadImageViewportMode.display,
      ),
      hasLength(2),
    );
    expect(
      handles.where(
        (handle) => handle.value == ThreadImageViewportMode.prefetch,
      ),
      isEmpty,
    );

    handles.first.reportFirstFrameSettled();
    await tester.pump();
    await tester.pump();
    expect(
      handles.where(
        (handle) => handle.value == ThreadImageViewportMode.prefetch,
      ),
      hasLength(1),
    );

    handles.first.reportLoadStarted();
    await tester.pump();
    await tester.pump();
    expect(
      handles.where(
        (handle) => handle.value == ThreadImageViewportMode.prefetch,
      ),
      isEmpty,
    );

    controller.jumpTo(500);
    await tester.pump();
    await tester.pump();

    expect(handles.first.value, ThreadImageViewportMode.dormant);
    expect(
      handles.where(
        (handle) => handle.value == ThreadImageViewportMode.display,
      ),
      isNotEmpty,
    );

    coordinator.setActive(false);
    await tester.pump();
    expect(
      handles.every(
        (handle) => handle.value == ThreadImageViewportMode.dormant,
      ),
      isTrue,
    );
  });
}

class _BoundImage extends StatelessWidget {
  const _BoundImage({required this.handle, required this.height});

  final ThreadImageViewportHandle handle;
  final double height;

  @override
  Widget build(BuildContext context) {
    handle.bind(context);
    return SizedBox(height: height);
  }
}
