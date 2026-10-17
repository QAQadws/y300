import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  testWidgets(
    'failed images in nested tables settle after scrolling and rebinding',
    (tester) async {
      tester.view.devicePixelRatio = 4;
      tester.view.physicalSize = const Size(1440, 2560);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = ScrollController();
      ForumHtmlImageViewportCoordinator newViewport() =>
          ForumHtmlImageViewportCoordinator(
            maxVisibleFirstFrames: 4,
            maxConcurrentOptionalWork: 2,
            predecodePolicy: const ForumHtmlImagePredecodePolicy(
              maxDecodedBytesPerImage: 16 * 1024 * 1024,
              forwardImageCount: 3,
              decodeExtentFactor: 1.5,
              forwardDiskExtentFactor: 3,
            ),
          );
      final viewport = newViewport();
      addTearDown(controller.dispose);
      addTearDown(viewport.dispose);
      final documents = {
        for (final source in ['a', 'b'])
          source: prepareRenderTestDocument(
            _nestedTablesHtml(source),
            sourceId: 'nested-$source',
          ),
      };
      var bodyBuilds = 0;
      Widget page(
        _FailedImageHost host, {
        String source = 'a',
        ForumHtmlImageViewportCoordinator? coordinator,
      }) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 336,
              height: 540,
              child: SingleChildScrollView(
                controller: controller,
                child: ForumHtmlRenderer(
                  preparedDocument: documents[source]!,
                  theme: forumHtmlTestTheme,
                  options: renderTestOptions,
                  labels: renderTestLabels,
                  sourceId: 'nested-$source',
                  imageHost: host,
                  imageViewportCoordinator: coordinator ?? viewport,
                  buildAsync: false,
                  enableCaching: true,
                  onBodyBuilt: () => bodyBuilds++,
                ),
              ),
            ),
          ),
        ),
      );

      final firstHost = _FailedImageHost();
      await tester.pumpWidget(page(firstHost));
      await _settle(tester);
      expect(viewport.registeredImageCount, 8);
      expect(firstHost.mounts, inInclusiveRange(1, 8));
      expect(firstHost.failures, greaterThan(0));
      final initialBodyBuilds = bodyBuilds;

      for (final fraction in [
        0.2,
        0.4,
        0.6,
        0.8,
        1.0,
        0.8,
        0.6,
        0.4,
        0.2,
        0.0,
      ]) {
        final mountsBefore = firstHost.mounts;
        controller.jumpTo(controller.position.maxScrollExtent * fraction);
        await _settle(tester);
        // Each target may mount the eight independent slots, but a failed slot
        // must not repeatedly retire and remount while the viewport is stationary.
        expect(firstHost.mounts - mountsBefore, lessThanOrEqualTo(8));
        expect(viewport.registeredImageCount, 8);
        expect(firstHost.activeSlots.length, lessThanOrEqualTo(8));
      }
      expect(bodyBuilds, initialBodyBuilds);
      expect(firstHost.failures, lessThanOrEqualTo(firstHost.mounts));

      final secondHost = _FailedImageHost();
      await tester.pumpWidget(page(secondHost));
      await _settle(tester);
      expect(firstHost.activeSlots, isEmpty);
      expect(secondHost.mounts, inInclusiveRange(1, 8));
      expect(viewport.registeredImageCount, 8);

      final reboundViewport = newViewport();
      addTearDown(reboundViewport.dispose);
      await tester.pumpWidget(page(secondHost, coordinator: reboundViewport));
      await _settle(tester);
      expect(viewport.registeredImageCount, 0);
      expect(reboundViewport.registeredImageCount, 8);

      await tester.pumpWidget(
        page(secondHost, source: 'b', coordinator: reboundViewport),
      );
      await _settle(tester);
      expect(secondHost.activeSlots, isNotEmpty);
      expect(
        secondHost.activeSlots.values.every((url) => url.contains('/b/')),
        isTrue,
      );
      expect(reboundViewport.registeredImageCount, 8);

      final mountsBeforeRetry = secondHost.mounts;
      await tester.tap(find.byType(TextButton).first);
      await _settle(tester);
      expect(secondHost.mounts, greaterThan(mountsBeforeRetry));
      expect(secondHost.mounts - mountsBeforeRetry, lessThanOrEqualTo(8));
      expect(reboundViewport.registeredImageCount, 8);

      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      expect(viewport.registeredImageCount, 0);
      expect(reboundViewport.registeredImageCount, 0);
      expect(firstHost.activeSlots, isEmpty);
      expect(secondHost.activeSlots, isEmpty);
    },
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 16),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
  expect(tester.binding.hasScheduledFrame, isFalse);
  expect(tester.takeException(), isNull);
}

String _nestedTablesHtml(String source) {
  String image(int index, {bool fixedWidth = false}) {
    final width = fixedWidth ? ' width="300"' : '';
    final image =
        '<img src="https://example.invalid/$source/$index.png"$width>';
    return fixedWidth ? image : '<div align="center">$image</div>';
  }

  String text(String section) =>
      '<font face="微软雅黑"><font size="2">$section</font></font>'
      '<br>测试资料用于验证窄列排版<br>这里还有一行独立说明<br>';
  String table(List<List<String>> rows) =>
      '<table>'
      '${rows.map((cells) => '<tr>${cells.map((cell) => '<td>$cell</td>').join()}</tr>').join()}'
      '</table>';
  String center(String child) => '<div align="center">$child</div>';

  // Real columns matter: the nested right-hand image is measured first with
  // the available table width and then with its narrower final column width.
  final cast = table([
    [
      image(1, fixedWidth: true),
      table([
        [
          '<font size="1">NAME:</font><font face="微软雅黑">示例驾驶员甲</font>（测试称呼）<br><font size="1">CV:</font><font face="微软雅黑">示例声优</font>',
        ],
        [
          '<font size="1">DATA:</font><br><strong><font face="微软雅黑">这是一名测试学生。<br>正在进行模拟训练。<br>驾驶一台示例机体。</font></strong>',
        ],
      ]),
    ],
    [
      image(2, fixedWidth: true),
      table([
        ['<font size="1">MOBILE UNIT:</font><font>示例机体</font>'],
        [image(3, fixedWidth: true)],
      ]),
    ],
  ]);
  final secondCast = table([
    [
      image(4, fixedWidth: true),
      table([
        [
          '<font size="1">NAME:</font><font face="微软雅黑">示例驾驶员乙</font>（测试称呼）<br><font size="1">CV:</font><font face="微软雅黑">其他声优</font>',
        ],
        [
          '<font size="1">DATA:</font><br><strong><font face="微软雅黑">另一名模拟驾驶员。<br>正在测试新的装备。<br>这是一段合成介绍。</font></strong>',
        ],
      ]),
    ],
    ['Back view', '<br>'],
  ]);
  final staff = table([
    [center('<font size="5">Production</font>')],
    [text('Planning: Test studio / Direction: Sample director')],
    [
      center(
        table([
          [
            for (var column = 0; column < 3; column++)
              [
                for (var row = 0; row < 8; row++)
                  '<font size="1">Department $column-$row</font><br>'
                      '<font>Example contributor</font><br><br>',
              ].join(),
          ],
        ]),
      ),
    ],
    [text('Production: Synthetic sample partners')],
  ]);
  return [
    '<div align="center">${image(6)}</div><br>',
    center(
      table([
        ['${text('Introduction')}${image(0)}'],
      ]),
    ),
    center(
      table([
        [center('<font size="5">Characters</font>')],
        [center('$cast<br>$secondCast')],
      ]),
    ),
    center(staff),
    center(
      table([
        [image(5)],
      ]),
    ),
    '<div align="center">${image(7)}</div><br>',
  ].join();
}

final class _FailedImageHost implements ForumHtmlImageHost {
  final activeSlots = <Object, String>{};
  var mounts = 0;
  var failures = 0;

  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _FailedImage(url.toString(), isSticker, htmlSize);

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async => null;

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => _FailedSlot(
    key: ValueKey((this, image.identity, retryToken)),
    host: this,
    url: image.sourceUrl,
    onFailure: onImageFailed,
    onRetry: onRetry,
  );
}

final class _FailedImage implements ForumHtmlDisplayImage {
  const _FailedImage(this.sourceUrl, this.isSticker, this.htmlSize);

  @override
  final String sourceUrl;
  @override
  final bool isSticker;
  @override
  final Size? htmlSize;
  @override
  String get cacheKey => sourceUrl;
  @override
  Object get identity => (sourceUrl, isSticker, htmlSize);
  @override
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(isFallback: true, aspectRatio: 0.7);
}

class _FailedSlot extends StatefulWidget {
  const _FailedSlot({
    super.key,
    required this.host,
    required this.url,
    this.onFailure,
    this.onRetry,
  });

  final _FailedImageHost host;
  final String url;
  final VoidCallback? onFailure;
  final VoidCallback? onRetry;

  @override
  State<_FailedSlot> createState() => _FailedSlotState();
}

class _FailedSlotState extends State<_FailedSlot> {
  @override
  void initState() {
    super.initState();
    widget.host.mounts++;
    widget.host.activeSlots[this] = widget.url;
    final onFailure = widget.onFailure;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.host.failures++;
      onFailure?.call();
    });
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
  );

  @override
  void dispose() {
    widget.host.activeSlots.remove(this);
    super.dispose();
  }
}
