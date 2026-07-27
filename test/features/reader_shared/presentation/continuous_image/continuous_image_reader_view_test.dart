import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';

void main() {
  testWidgets('ContinuousImageReaderView builds vertical image slots', (
    tester,
  ) async {
    final extents = <ContinuousImageExtent>[];
    await tester.pumpWidget(
      LocalizedTestApp(
        home: ContinuousImageReaderView(
          items: _items,
          mode: ContinuousImageReaderMode.vertical,
          onExtentResolved: extents.add,
          slotKeyPrefix: 'test-slot',
          itemBuilder: (context, item, index, {required paged}) {
            return ColoredBox(
              key: ValueKey<String>('image-${item.index}'),
              color: Colors.black,
              child: const SizedBox(height: 32, width: double.infinity),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('continuous-image-reader-list')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('test-slot-0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('image-0')), findsOneWidget);
    expect(extents, isNotEmpty);
  });

  testWidgets('ContinuousImageReaderView builds horizontal pages', (
    tester,
  ) async {
    final changed = <int>[];
    await tester.pumpWidget(
      LocalizedTestApp(
        home: ContinuousImageReaderView(
          items: _items,
          mode: ContinuousImageReaderMode.horizontal,
          pageController: PageController(),
          onExtentResolved: (_) {},
          onPageChanged: changed.add,
          itemBuilder: (context, item, index, {required paged}) {
            return ColoredBox(
              key: ValueKey<String>('page-${item.index}-$paged'),
              color: Colors.black,
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('continuous-image-reader-page-view')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('page-0-true')), findsOneWidget);
  });

  testWidgets('ContinuousImageReaderView appends horizontal tail and advance', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      LocalizedTestApp(
        home: ContinuousImageReaderView(
          items: _items,
          mode: ContinuousImageReaderMode.horizontal,
          pageController: controller,
          onExtentResolved: (_) {},
          horizontalTrailingBuilder: (context) => const ColoredBox(
            key: Key('reader-test-tail'),
            color: Colors.blue,
          ),
          horizontalAdvanceBuilder: (context) => const ColoredBox(
            key: Key('reader-test-advance'),
            color: Colors.green,
          ),
          itemBuilder: (context, item, index, {required paged}) {
            return ColoredBox(
              key: ValueKey<String>('page-${item.index}-$paged'),
              color: Colors.black,
            );
          },
        ),
      ),
    );
    await tester.pump();

    controller.jumpToPage(2);
    await tester.pump();
    expect(find.byKey(const Key('reader-test-tail')), findsOneWidget);

    controller.jumpToPage(3);
    await tester.pump();
    expect(find.byKey(const Key('reader-test-advance')), findsOneWidget);
  });

  testWidgets('ContinuousImageReaderView appends vertical trailing content', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: ContinuousImageReaderView(
          items: _items,
          mode: ContinuousImageReaderMode.vertical,
          onExtentResolved: (_) {},
          verticalTrailingBuilder: (context) =>
              const SizedBox(key: Key('reader-test-vertical-tail'), height: 80),
          itemBuilder: (context, item, index, {required paged}) {
            return const SizedBox(height: 32, width: double.infinity);
          },
        ),
      ),
    );
    await tester.pump();

    final list = tester.widget<ListView>(
      find.byKey(const Key('continuous-image-reader-list')),
    );
    final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, _items.length + 1);
  });
}

const _items = <ContinuousImageItem>[
  ContinuousImageItem(
    ownerId: 'owner',
    id: 'image-0',
    url: 'https://img.test/0.jpg',
    cacheKey: 'image-0',
    index: 0,
    sourceKind: ContinuousImageSourceKind.threadImageReader,
    knownWidth: 100,
    knownHeight: 200,
    spacingAfter: 10,
  ),
  ContinuousImageItem(
    ownerId: 'owner',
    id: 'image-1',
    url: 'https://img.test/1.jpg',
    cacheKey: 'image-1',
    index: 1,
    sourceKind: ContinuousImageSourceKind.threadImageReader,
    knownWidth: 100,
    knownHeight: 100,
  ),
];
