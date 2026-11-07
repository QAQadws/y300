import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/clipboard/clipboard_text_writer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../test_support/localized_test_app.dart';

final _theme = const ForumHtmlRenderThemeFactory().fromMaterialTheme(
  theme: ThemeData.light(),
  surface: Colors.white,
);

ForumHtmlPreparedRenderDocument _prepare(String html) =>
    const DefaultForumHtmlRenderPreparer().prepare(
      html: html,
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: _theme,
      sourceId: 'body',
      threadId: '100',
      imageCacheOwnerId: '100',
    );

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'Native image geometry did not become ready');
}

Widget _scene(
  ForumHtmlPreparedRenderDocument prepared,
  _Images host,
  ForumHtmlBodyPresentation presentation, {
  bool shown = true,
  ScrollController? scroll,
  ForumHtmlImageAnchorController? anchors,
  ForumNativeBodyCache? cache,
}) => LocalizedTestApp(
  home: Scaffold(
    body: SingleChildScrollView(
      controller: scroll,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: shown
              ? ForumNativeBodyFlow(
                  cache: cache,
                  prepared: prepared,
                  preferences: ForumHtmlReaderPreferences.defaults(),
                  theme: _theme,
                  textStyle: const TextStyle(fontSize: 16, color: Colors.black),
                  fontRevision: 'fixed',
                  imageHost: host,
                  imageAnchorController: anchors,
                  expansion: presentation.collapseExpansion,
                  callbacks: const ForumHtmlRenderCallbacks(),
                  bodyPresentation: presentation,
                  clipboardTextWriter: _Clipboard(),
                  errorBuilder: (_) => const SizedBox(),
                )
              : const SizedBox(),
        ),
      ),
    ),
  ),
);

ForumBodyFlowBox? _flow(WidgetTester tester) => tester
    .widgetList<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
    .firstOrNull;
double _height(WidgetTester tester) =>
    tester.getSize(find.byType(ForumBodyFlowBox)).height;
Future<void> _ready(WidgetTester tester, [_Images? host]) => _until(
  tester,
  () =>
      _flow(tester)?.prefix.isComplete == true &&
      _flow(tester)?.isCurrentLayout == true &&
      (host == null || host.jobs.isNotEmpty),
);

void main() {
  testWidgets(
    'warm body publishes in its start frame without an extra queue frame',
    (tester) async {
      final prepared = _prepare('<p>warm body</p>');
      final host = _Images(prepared);
      final presentation = ForumHtmlBodyPresentation();
      final cache = ForumNativeBodyCache();
      addTearDown(presentation.dispose);
      addTearDown(cache.close);
      await tester.pumpWidget(
        _scene(prepared, host, presentation, cache: cache),
      );
      await tester.pumpAndSettle();
      final old = _flow(tester)!.session;
      final layouts = cache.paragraphs.layoutBuildCount;
      await tester.pumpWidget(
        _scene(prepared, host, presentation, shown: false, cache: cache),
      );
      expect(old.isClosed, isTrue);
      await tester.pumpWidget(
        _scene(prepared, host, presentation, cache: cache),
      );
      await tester.pump();
      expect(_flow(tester)?.prefix.isNotEmpty, isTrue);
      expect(cache.paragraphs.layoutBuildCount, layouts);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(cache.paragraphs.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, html) in [
    (
      'inline',
      '<img style="display:inline-block" src="https://example.test/same.png">',
    ),
    ('float', '<img style="float:left" src="https://example.test/same.png">'),
    (
      'table',
      '<table><tr><td><img src="https://example.test/same.png"></td></tr></table>',
    ),
    (
      'nested table',
      '<table><tr><td><div><table><tr><td>'
          '<img src="https://example.test/same.png">'
          '</td></tr></table></div></td></tr></table>',
    ),
  ]) {
    testWidgets('$name image geometry survives native remount', (tester) async {
      final prepared = _prepare(html);
      final host = _Images(prepared);
      final presentation = ForumHtmlBodyPresentation();
      addTearDown(presentation.dispose);
      await tester.pumpWidget(_scene(prepared, host, presentation));
      await _ready(tester, host);
      final initial = _height(tester);
      host.jobs.first.complete((
        size: const Size(200, 100),
        layout: const ForumHtmlImageLayout(
          aspectRatio: 2,
          displaySize: Size(200, 100),
        ),
      ));
      await _until(
        tester,
        () =>
            _flow(tester)?.prefix.isComplete == true &&
            _flow(tester)?.isCurrentLayout == true &&
            (_height(tester) - initial).abs() > .5,
      );
      final measured = _height(tester);
      final old = _flow(tester)!.session;
      await tester.pumpWidget(
        _scene(prepared, host, presentation, shown: false),
      );
      expect(old.isClosed, isTrue);
      await tester.pumpWidget(_scene(prepared, host, presentation));
      await _ready(tester);
      expect(_height(tester), closeTo(measured, .01));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final retire in [false, true]) {
    testWidgets(
      retire
          ? 'post-frame image preparation stops when the body is retired'
          : 'post-frame image preparation requests its next frame',
      (tester) async {
        final prepared = _prepare(
          '<p><img src="https://example.test/first.png"></p>'
          '<p><img src="https://example.test/second.png"></p>',
        );
        final host = _Images(prepared);
        final presentation = ForumHtmlBodyPresentation();
        addTearDown(presentation.dispose);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
        await tester.pumpWidget(_scene(prepared, host, presentation));
        await _ready(tester, host);
        await tester.pumpAndSettle();
        final previous = _flow(tester)!.session;
        final height = _height(tester);
        final resolved = host.resolveCount;
        expect(tester.binding.hasScheduledFrame, isFalse);
        host.beforeResolve = () {
          // Exhaust the setup slice before its second image. The assertion
          // below must run before pumpAndSettle supplies a frame on its own.
          final clock = Stopwatch()..start();
          while (clock.elapsedMicroseconds < 5000) {}
        };
        host.callbacks.last(const Size(200, 100));
        for (var i = 0; i < 20 && host.resolveCount == resolved; i++) {
          await tester.idle();
          if (!tester.binding.hasScheduledFrame) break;
          await tester.pump();
        }
        expect(host.resolveCount, greaterThan(resolved));
        expect(_flow(tester)?.isCurrentLayout, isFalse);
        if (retire) {
          final waiting = host.resolveCount;
          expect(
            tester.binding.hasScheduledFrame,
            isTrue,
            reason: 'Preparation started after a frame must request the frame it awaits.',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(host.resolveCount, waiting);
        } else {
          // Pump only frames requested by the application. An unconditional
          // pump would wake the stalled preparation and hide the regression.
          for (
            var i = 0;
            i < 40 && _flow(tester)?.isCurrentLayout != true;
            i++
          ) {
            await tester.idle();
            if (!tester.binding.hasScheduledFrame) break;
            await tester.pump();
          }
          expect(_flow(tester)?.isCurrentLayout, isTrue);
          expect(_flow(tester)?.prefix.isComplete, isTrue);
          expect(_height(tester), isNot(closeTo(height, .01)));
          expect(_flow(tester)!.session, isNot(same(previous)));
          await tester.pumpWidget(const SizedBox.shrink());
        }
        expect(previous.isClosed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'fractional nested image heights preserve the exact measured surface size',
    (tester) async {
      final prepared = _prepare(
        '<table><tr><td><table><tr>'
        '<td style="padding-top:500.6px"><img src="https://example.test/same.png">'
        '</td></tr></table></td></tr></table>',
      );
      final host = _Images(prepared, initialRatio: 675 / 277);
      final presentation = ForumHtmlBodyPresentation();
      final scroll = ScrollController();
      addTearDown(presentation.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _scene(prepared, host, presentation, scroll: scroll),
      );
      await _ready(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byType(ForumHtmlImageView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'offscreen nested table reveals the selected repeated image occurrence',
    (tester) async {
      final prepared = _prepare(
        '<div style="padding-top:1200px"><table><tr><td><table><tr><td>'
        '<img width="100" height="100" src="https://example.test/same.png">'
        '<p>between</p><img width="100" height="100" src="https://example.test/same.png">'
        '</td></tr></table></td></tr></table></div><div style="padding-bottom:1000px">end</div>',
      );
      final host = _Images(prepared);
      final presentation = ForumHtmlBodyPresentation();
      final scroll = ScrollController();
      final anchors = ForumHtmlImageAnchorController();
      addTearDown(presentation.dispose);
      addTearDown(scroll.dispose);
      addTearDown(anchors.dispose);
      await tester.pumpWidget(
        _scene(prepared, host, presentation, scroll: scroll, anchors: anchors),
      );
      await _ready(tester);
      expect(find.byType(ForumHtmlImageView), findsNothing);
      final entry = prepared.sequence.entries.last;
      bool? revealed;
      anchors
          .revealImage(
            index: entry.index,
            cacheKey: entry.cacheKey,
            url: entry.url,
            scrollController: scroll,
            isCurrent: () => true,
          )
          .then((value) => revealed = value);
      await _until(tester, () => revealed != null);
      expect(revealed, isTrue);
      final target = find.byKey(
        ValueKey(('native-readable-image', 'body', entry.index)),
      );
      expect(tester.getTopLeft(target).dy, closeTo(0, 1));
      expect(scroll.offset, greaterThan(1200));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'learned image ratio survives a native remount before metadata returns',
    (tester) async {
      final prepared = _prepare('<img src="https://example.test/same.png">');
      final host = _Images(prepared);
      final presentation = ForumHtmlBodyPresentation();
      addTearDown(presentation.dispose);
      Widget scene(bool shown) =>
          _scene(prepared, host, presentation, shown: shown);
      ForumBodyFlowBox? flow() => tester
          .widgetList<ForumBodyFlowBox>(find.byType(ForumBodyFlowBox))
          .firstOrNull;
      double height() => tester.getSize(find.byType(ForumBodyFlowBox)).height;
      await tester.pumpWidget(scene(true));
      await _until(
        tester,
        () => flow()?.prefix.isComplete == true && host.jobs.isNotEmpty,
      );
      expect(height(), closeTo(300, .01));
      host.jobs.first.complete((
        size: const Size(200, 100),
        layout: const ForumHtmlImageLayout(aspectRatio: 2),
      ));
      await _until(
        tester,
        () => flow()?.prefix.isComplete == true && (height() - 150).abs() < .01,
      );
      final old = flow()!.session;
      await tester.pumpWidget(scene(false));
      expect(old.isClosed, isTrue);
      expect(old.activeIssuedFragments, 0);
      await tester.pumpWidget(scene(true));
      await _until(tester, () => flow()?.prefix.isComplete == true);
      expect(height(), closeTo(150, .01));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed ratio is retained even when it matched the old fallback estimate',
    (tester) async {
      final prepared = _prepare('<img src="https://example.test/same.png">');
      final host = _Images(prepared, initialRatio: 2);
      final presentation = ForumHtmlBodyPresentation();
      addTearDown(presentation.dispose);
      await tester.pumpWidget(_scene(prepared, host, presentation));
      await _ready(tester, host);
      expect(_height(tester), closeTo(150, .01));
      host.jobs.first.complete((
        size: const Size(200, 100),
        layout: const ForumHtmlImageLayout(aspectRatio: 2),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(
        _scene(prepared, host, presentation, shown: false),
      );
      // The Host's estimate may change after learning from other thread images.
      final changedEstimate = _Images(prepared, initialRatio: 4);
      await tester.pumpWidget(_scene(prepared, changedEstimate, presentation));
      await _ready(tester, changedEstimate);
      expect(_height(tester), closeTo(150, .01));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a new display binding misses old geometry and rejects the old image callback',
    (tester) async {
      final prepared = _prepare('<img src="https://example.test/same.png">');
      final first = _Images(prepared);
      final presentation = ForumHtmlBodyPresentation();
      addTearDown(presentation.dispose);
      await tester.pumpWidget(_scene(prepared, first, presentation));
      await _ready(tester, first);
      first.jobs.first.complete((
        size: const Size(200, 100),
        layout: const ForumHtmlImageLayout(aspectRatio: 2),
      ));
      await _until(
        tester,
        () =>
            _flow(tester)?.prefix.isComplete == true &&
            (_height(tester) - 150).abs() < .01,
      );
      final late = first.callbacks.last;
      final second = _Images(prepared, binding: 'two');
      await tester.pumpWidget(_scene(prepared, second, presentation));
      await _ready(tester, second);
      expect(_height(tester), closeTo(300, .01));
      late(const Size(200, 800));
      await tester.pump();
      expect(_height(tester), closeTo(300, .01));
      second.jobs.first.complete((
        size: const Size(400, 100),
        layout: const ForumHtmlImageLayout(aspectRatio: 4),
      ));
      await _until(
        tester,
        () =>
            _flow(tester)?.prefix.isComplete == true &&
            (_height(tester) - 75).abs() < .01,
      );
      final sameFirstBinding = _Images(prepared);
      await tester.pumpWidget(_scene(prepared, sameFirstBinding, presentation));
      await _ready(tester, sameFirstBinding);
      expect(_height(tester), closeTo(150, .01));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a replaced presentation owner retires learned geometry and old callbacks',
    (tester) async {
      final prepared = _prepare('<img src="https://example.test/same.png">');
      final host = _Images(prepared);
      final first = ForumHtmlBodyPresentation();
      final second = ForumHtmlBodyPresentation();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(_scene(prepared, host, first));
      await _ready(tester, host);
      host.jobs.first.complete((
        size: const Size(200, 100),
        layout: const ForumHtmlImageLayout(aspectRatio: 2),
      ));
      await _until(
        tester,
        () =>
            _flow(tester)?.isCurrentLayout == true &&
            (_height(tester) - 150).abs() < .01,
      );
      final retired = _flow(tester)!.session;
      final late = host.callbacks.last;
      final jobCount = host.jobs.length;
      first.dispose();
      await tester.pumpWidget(_scene(prepared, host, second));
      await _until(
        tester,
        () =>
            _flow(tester)?.prefix.isComplete == true &&
            _flow(tester)?.isCurrentLayout == true &&
            host.jobs.length > jobCount,
      );
      expect(retired.isClosed, isTrue);
      expect(retired.activeIssuedFragments, 0);
      expect(_height(tester), closeTo(300, .01));
      late(const Size(200, 800));
      await tester.pump();
      expect(_height(tester), closeTo(300, .01));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edited document does not reuse geometry just because its URL and node path match',
    (tester) async {
      final prepared = _prepare('<img src="https://example.test/same.png">');
      final host = _Images(prepared);
      final presentation = ForumHtmlBodyPresentation();
      addTearDown(presentation.dispose);
      await tester.pumpWidget(_scene(prepared, host, presentation));
      await _ready(tester, host);
      host.jobs.first.complete((
        size: const Size(200, 100),
        layout: const ForumHtmlImageLayout(aspectRatio: 2),
      ));
      await _until(
        tester,
        () =>
            _flow(tester)?.prefix.isComplete == true &&
            (_height(tester) - 150).abs() < .01,
      );
      final edited = _prepare(
        '<img alt="changed" src="https://example.test/same.png">',
      );
      final editedHost = _Images(edited);
      await tester.pumpWidget(_scene(edited, editedHost, presentation));
      await _ready(tester, editedHost);
      expect(_height(tester), closeTo(300, .01));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Images implements ForumHtmlImageHost {
  _Images(this.prepared, {this.binding = 'one', this.initialRatio = 1});
  final ForumHtmlPreparedRenderDocument prepared;
  final String binding;
  final double initialRatio;
  final jobs = <Completer<({Size size, ForumHtmlImageLayout layout})?>>[];
  final callbacks = <ValueChanged<Size>>[];
  VoidCallback? beforeResolve;
  var resolveCount = 0;
  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) {
    resolveCount++;
    beforeResolve?.call();
    return _Image(
      url.toString(),
      prepared.sequence.entryAt(imageIndex!)!.cacheKey,
      binding,
      htmlSize,
      initialRatio,
    );
  }

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) {
    final result = Completer<({Size size, ForumHtmlImageLayout layout})?>();
    jobs.add(result);
    return result.future;
  }

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
  }) {
    if (onImageResolved != null) callbacks.add(onImageResolved);
    return _Frame(key: ValueKey(image.identity), onFrame: onFirstFrameRendered);
  }
}

final class _Image implements ForumHtmlDisplayImage {
  const _Image(
    this.sourceUrl,
    this.cacheKey,
    this.binding,
    this.htmlSize,
    this.initialRatio,
  );
  @override
  final String sourceUrl;
  @override
  final String cacheKey;
  final String binding;
  final double initialRatio;
  @override
  final Size? htmlSize;
  @override
  bool get isSticker => false;
  @override
  Object get identity => (cacheKey, binding);
  @override
  ForumHtmlImageLayout get initialLayout =>
      ForumHtmlImageLayout(isFallback: true, aspectRatio: initialRatio);
}

class _Frame extends StatefulWidget {
  const _Frame({super.key, this.onFrame});
  final VoidCallback? onFrame;
  @override
  State<_Frame> createState() => _FrameState();
}

class _FrameState extends State<_Frame> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFrame?.call();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.blue, child: SizedBox.expand());
}

final class _Clipboard implements ClipboardTextWriter {
  @override
  Future<void> writeText(String text) async {}
}
