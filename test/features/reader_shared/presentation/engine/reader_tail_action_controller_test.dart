import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_action_controller.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';

void main() {
  testWidgets(
    'mode switch notifies the retained surface that its old viewport exited',
    (tester) async {
      final controller = ReaderTailActionController();
      final surface = _Surface();
      addTearDown(controller.dispose);
      controller.configure(
        identity: 'ltr',
        surface: surface,
        vertical: false,
        pagedVisible: true,
      );
      await tester.pumpWidget(const SizedBox());
      expect(surface.changes, [true]);
      controller.configure(
        identity: 'vertical',
        surface: surface,
        vertical: true,
        pagedVisible: false,
      );
      await tester.pumpWidget(const SizedBox(key: ValueKey('new-mode')));
      expect(surface.changes, [true, false]);
      expect(controller.visible, isFalse);
    },
  );

  testWidgets(
    'real viewport intersection survives recycling a long lazy tail',
    (tester) async {
      final controller = ReaderTailActionController();
      final scroll = ScrollController()..addListener(controller.schedule);
      final surface = _Surface();
      addTearDown(controller.dispose);
      addTearDown(scroll.dispose);
      controller.configure(
        identity: 'chapter',
        surface: surface,
        vertical: true,
        pagedVisible: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: ListView.builder(
                controller: scroll,
                padding: EdgeInsets.zero,
                itemCount: 101,
                scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                itemBuilder: (_, index) => index == 0
                    ? const SizedBox(height: 400)
                    : ReaderTailVisibilityItem(
                        controller: controller,
                        identity: 'chapter',
                        child: SizedBox(height: 120, child: Text('$index')),
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ReaderTailVisibilityItem, skipOffstage: false),
        findsWidgets,
      );
      expect(controller.visible, isFalse);
      scroll.jumpTo(250);
      await tester.pumpAndSettle();
      expect(controller.visible, isTrue);
      scroll.jumpTo(8000);
      await tester.pumpAndSettle();
      expect(controller.visible, isTrue);
      expect(
        find.byType(ReaderTailVisibilityItem).evaluate().length,
        lessThan(15),
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(controller.visible, isFalse);
      expect(surface.changes, [true, false]);
    },
  );

  testWidgets(
    'layout changes update visibility without scrolling and old owners cannot activate it',
    (tester) async {
      final controller = ReaderTailActionController();
      final surface = _Surface();
      addTearDown(controller.dispose);
      controller.configure(
        identity: 'chapter',
        surface: surface,
        vertical: true,
        pagedVisible: false,
      );
      var height = 400.0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      SizedBox(height: height),
                      ReaderTailVisibilityItem(
                        controller: controller,
                        identity: 'chapter',
                        child: const SizedBox(height: 300),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.visible, isFalse);
      update(() => height = 150);
      await tester.pumpAndSettle();
      expect(controller.visible, isTrue);
      update(() => height = 400);
      await tester.pumpAndSettle();
      expect(controller.visible, isFalse);
      controller.configure(
        identity: 'new-chapter',
        surface: surface,
        vertical: true,
        pagedVisible: false,
      );
      update(() => height = 150);
      await tester.pumpAndSettle();
      expect(controller.visible, isFalse);
    },
  );
}

class _Surface implements ReaderTailActionSurface {
  final changes = <bool>[];
  @override
  Widget buildActionBar(BuildContext context) => const SizedBox();
  @override
  void onVisibilityChanged(bool visible) => changes.add(visible);
}
