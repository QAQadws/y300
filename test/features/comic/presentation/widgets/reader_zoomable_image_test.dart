import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_zoomable_image.dart';

Widget _hostZoomableImage({
  ReaderZoomBehavior behavior = ReaderZoomBehavior.bounded,
  Object? resetToken,
  ValueChanged<bool>? onZoomStateChanged,
  Widget? child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: ReaderZoomableImage(
            behavior: behavior,
            resetToken: resetToken,
            onZoomStateChanged: onZoomStateChanged,
            child: child ?? Container(color: Colors.blue),
          ),
        ),
      ),
    ),
  );
}

Widget _hostScrollableZoomableImage(
  ScrollController controller, {
  ReaderZoomBehavior behavior = ReaderZoomBehavior.bounded,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        controller: controller,
        children: [
          SizedBox(
            height: 720,
            child: ReaderZoomableImage(
              behavior: behavior,
              child: Container(color: Colors.blue),
            ),
          ),
          const SizedBox(height: 720),
        ],
      ),
    ),
  );
}

Transform _readBoundedTransform(WidgetTester tester) {
  return tester.widget<Transform>(
    find.byKey(const Key('reader-bounded-zoom-transform')),
  );
}

void main() {
  testWidgets('double tap toggles zoom state callback', (tester) async {
    final states = <bool>[];

    await tester.pumpWidget(_hostZoomableImage(onZoomStateChanged: states.add));

    final target = find.byType(ReaderZoomableImage);
    expect(target, findsOneWidget);

    await tester.tapAt(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();

    expect(states, containsAllInOrder(<bool>[true, false]));
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(
      _readBoundedTransform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1, 0.001),
    );
  });

  testWidgets('reset token returns a zoomed surface to resting state', (
    tester,
  ) async {
    final states = <bool>[];
    await tester.pumpWidget(
      _hostZoomableImage(
        resetToken: 'fit-width',
        onZoomStateChanged: states.add,
      ),
    );
    final target = find.byType(ReaderZoomableImage);

    await tester.tapAt(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();
    expect(_readBoundedTransform(tester).transform.getMaxScaleOnAxis(), 2);

    await tester.pumpWidget(
      _hostZoomableImage(
        resetToken: 'fit-height',
        onZoomStateChanged: states.add,
      ),
    );
    await tester.pump();

    expect(
      _readBoundedTransform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1, 0.001),
    );
    expect(states, <bool>[true, false]);
  });

  testWidgets('stable transform stays out of the gesture arena at rest', (
    tester,
  ) async {
    await tester.pumpWidget(_hostZoomableImage());
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(
      _readBoundedTransform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1, 0.001),
    );
    expect(
      find.descendant(
        of: find.byType(ReaderZoomableImage),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('single-finger drag on an image scrolls the parent list', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_hostScrollableZoomableImage(controller));

    final target = find.byType(ReaderZoomableImage);
    final start = tester.getCenter(target);
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final previousOffset = controller.offset;
      await tester.dragFrom(start, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(previousOffset));
    }
  });

  testWidgets('bounded surface pans after double-tap zoom-in', (tester) async {
    await tester.pumpWidget(_hostZoomableImage());
    final target = find.byType(ReaderZoomableImage);

    await tester.tapAt(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();

    final before = _readBoundedTransform(tester).transform.clone();
    expect(before.getMaxScaleOnAxis(), greaterThan(1));

    await tester.dragFrom(tester.getCenter(target), const Offset(-40, -30));
    await tester.pump();

    final after = _readBoundedTransform(tester).transform;
    expect(after.getTranslation().x, lessThan(before.getTranslation().x));
    expect(after.getTranslation().y, lessThan(before.getTranslation().y));
  });

  testWidgets('direct two-finger pinch activates the zoom surface', (
    tester,
  ) async {
    final states = <bool>[];
    await tester.pumpWidget(_hostZoomableImage(onZoomStateChanged: states.add));
    final target = find.byType(ReaderZoomableImage);
    final center = tester.getCenter(target);
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);

    await first.down(center - const Offset(24, 0));
    await second.down(center + const Offset(24, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(72, 0));
    await second.moveTo(center + const Offset(72, 0));
    await tester.pump();

    final transform = _readBoundedTransform(tester);
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));
    expect(states, <bool>[true]);

    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('continuous vertical pinch scales the whole transform', (
    tester,
  ) async {
    await tester.pumpWidget(
      _hostZoomableImage(behavior: ReaderZoomBehavior.continuousVertical),
    );
    final target = find.byType(ReaderZoomableImage);
    final center = tester.getCenter(target);
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);

    await first.down(center - const Offset(24, 0));
    await second.down(center + const Offset(24, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(72, 0));
    await second.moveTo(center + const Offset(72, 0));
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsNothing);
    final transform = tester.widget<Transform>(
      find.byKey(const Key('reader-continuous-zoom-transform')),
    );
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));

    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });

  testWidgets('continuous vertical zoom leaves parent scrolling available', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _hostScrollableZoomableImage(
        controller,
        behavior: ReaderZoomBehavior.continuousVertical,
      ),
    );
    final target = find.byType(ReaderZoomableImage);
    final center = tester.getCenter(target);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    final transform = tester.widget<Transform>(
      find.byKey(const Key('reader-continuous-zoom-transform')),
    );
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));

    await tester.dragFrom(center, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('zoom cycles preserve the image child identity', (tester) async {
    final provider = MemoryImage(Uint8List.fromList(_transparentImageBytes));
    final image = Image(image: provider);
    await tester.pumpWidget(_hostZoomableImage(child: image));
    final target = find.byType(ReaderZoomableImage);
    final initialElement = tester.element(find.byType(Image));

    for (var cycle = 0; cycle < 20; cycle += 1) {
      await tester.tapAt(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(tester.getCenter(target));
      await tester.pumpAndSettle();
    }

    expect(tester.element(find.byType(Image)), same(initialElement));
    expect(tester.widget<Image>(find.byType(Image)).image, same(provider));
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('paged swipe gate preserves image and provider identity', (
    tester,
  ) async {
    final blocked = ValueNotifier<bool>(false);
    addTearDown(blocked.dispose);
    final provider = MemoryImage(Uint8List.fromList(_transparentImageBytes));
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPagedSwipeGate(
          blockedListenable: blocked,
          child: Image(image: provider),
        ),
      ),
    );
    final initialElement = tester.element(find.byType(Image));

    blocked.value = true;
    await tester.pump();
    blocked.value = false;
    await tester.pump();

    expect(tester.element(find.byType(Image)), same(initialElement));
    expect(tester.widget<Image>(find.byType(Image)).image, same(provider));
  });
}

const List<int> _transparentImageBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0xf0,
  0x1f,
  0x00,
  0x05,
  0x00,
  0x01,
  0xff,
  0x89,
  0x99,
  0x3d,
  0x1d,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
