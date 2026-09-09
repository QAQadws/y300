import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_scroll_controller.dart';

void main() {
  testWidgets('restoration corrects layout without ballistic scrolling', (
    tester,
  ) async {
    final controller = NovelReaderScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          physics: const BouncingScrollPhysics(),
          itemCount: 80,
          itemBuilder: (_, index) =>
              SizedBox(height: index < 8 ? 24 : 100, child: Text('$index')),
        ),
      ),
    );
    var complete = false;
    final future = controller
        .restore((metrics) => metrics.maxScrollExtent)
        .then((value) => complete = value);
    expect(complete, isFalse);
    await tester.pumpAndSettle();
    await future;
    expect(complete, isTrue);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(controller.position.isScrollingNotifier.value, isFalse);
    final offset = controller.offset;
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, offset);
  });

  testWidgets('cancelled and detached restoration cannot complete as applied', (
    tester,
  ) async {
    final controller = NovelReaderScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: const [SizedBox(height: 5000)],
        ),
      ),
    );
    final cancelled = controller.restore((metrics) => 300);
    controller.cancelRestore();
    expect(await cancelled, isFalse);
    final disposed = controller.restore((metrics) => 400);
    await tester.pumpWidget(const SizedBox());
    expect(await disposed, isFalse);
    expect(await controller.restore((_) => 10), isFalse);
  });
}
