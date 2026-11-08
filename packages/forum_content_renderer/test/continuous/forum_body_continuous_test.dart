import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/experimental_continuous.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle reader() => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    color: Colors.black,
  ),
  fontRevision: 'test-ahem',
  linkColor: Colors.blue,
  paragraphAfter: 0,
);
ForumBodyDocument document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'continuous',
  conversionIdentity: 'none',
);
Widget scene(
  ForumBodyDocument body,
  ForumBodyContinuousController controller, {
  double width = 150,
  TextScaler scaler = TextScaler.noScaling,
  ValueChanged<ForumBodyContinuousHit>? onTap,
  VoidCallback? onLongPress,
  GlobalKey? boundary,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: RepaintBoundary(
            key: boundary,
            child: GestureDetector(
              onLongPress: onLongPress,
              child: ForumBodyContinuous(
                document: body,
                reader: reader(),
                textScaler: scaler,
                controller: controller,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  testWidgets(
    'first layout paints shared styles without a page source or deferred frame',
    (tester) async {
      final controller = ForumBodyContinuousController(),
          boundary = GlobalKey();
      await tester.pumpWidget(
        scene(
          document('<p style="color:red">FIRST</p>'),
          controller,
          boundary: boundary,
        ),
      );
      expect(controller.isReady, isTrue);
      expect(controller.layoutCount, 1);
      expect(controller.copyText, 'FIRST');
      expect(controller.paragraphCount, 1);
      expect(find.byType(ForumBodyFlowBox), findsNothing);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final red = await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var red = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) > 240 &&
              data.getUint8(i + 1) < 20 &&
              data.getUint8(i + 2) < 20 &&
              data.getUint8(i + 3) > 240) {
            red++;
          }
        }
        image.dispose();
        return red;
      });
      expect(red, greaterThan(100));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.isReady, isFalse);
      expect(controller.copyText, isNull);
    },
  );
  testWidgets('BR windows keep line height without duplicating terminal rows', (
    tester,
  ) async {
    final c = ForumBodyContinuousController();
    await tester.pumpWidget(scene(document('<div>a<br><br>b<br>c</div>'), c));
    expect(c.copyText, 'a\n\nb\nc');
    expect(c.size!.height, closeTo(40, .01));
    expect(c.hitTest(const Offset(2, 22))!.source.sourceRune, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('actual layout supplies source hit and styled link coordinates', (
    tester,
  ) async {
    final c = ForumBodyContinuousController();
    ForumBodyContinuousHit? tapped;
    final body = document(
      '<div>前<a href="https://example.invalid/path">链接</a>后</div>',
    );
    await tester.pumpWidget(scene(body, c, onTap: (hit) => tapped = hit));
    final hit = c.hitTest(const Offset(15, 5))!;
    expect(hit.identity, body.identity);
    expect(hit.path, '0/1/0');
    expect(hit.source.sourceRune, 1);
    expect(hit.link, 'https://example.invalid/path');
    await tester.tapAt(const Offset(15, 5));
    expect(tapped?.link, hit.link);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.hitTest(const Offset(15, 5)), isNull);
  });
  testWidgets(
    'reader-equivalent rebuild and callback change keep native layout',
    (tester) async {
      final c = ForumBodyContinuousController(),
          body = document('<div>text</div>');
      await tester.pumpWidget(scene(body, c));
      final count = c.layoutCount;
      await tester.pumpWidget(scene(body, c, onTap: (_) {}));
      expect(c.layoutCount, count);
      await tester.pumpWidget(scene(body, c, width: 100));
      expect(c.layoutCount, count + 1);
      await tester.pumpWidget(
        scene(body, c, width: 100, scaler: const TextScaler.linear(2)),
      );
      expect(c.size!.height, closeTo(20, .01));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('BR continuation does not repeat authored first-line indent', (
    tester,
  ) async {
    final c = ForumBodyContinuousController();
    await tester.pumpWidget(
      scene(document('<p style="text-indent:20px">a<br>b</p>'), c),
    );
    expect(c.copyText, 'a\nb');
    expect(c.hitTest(const Offset(5, 5)), isNull);
    expect(c.hitTest(const Offset(25, 5))!.source.sourceRune, 0);
    expect(c.hitTest(const Offset(5, 15))!.source.sourceRune, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'shared signed margin collapse participates in continuous height',
    (tester) async {
      final c = ForumBodyContinuousController();
      await tester.pumpWidget(
        scene(
          document(
            '<p style="margin:0 0 20px">a</p><p style="margin:-5px 0 0">b</p>',
          ),
          c,
        ),
      );
      expect(c.size!.height, closeTo(35, .01));
      expect(c.copyText, 'a\nb');
      expect(c.hitTest(const Offset(5, 26))!.source.sourceRune, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('list marker uses the shared structural counter', (tester) async {
    final c = ForumBodyContinuousController();
    await tester.pumpWidget(
      scene(document('<ol start="8"><li>a</li><li>b</li></ol>'), c),
    );
    expect(c.copyText, 'a\nb');
    expect(c.paragraphCount, 2);
    expect(c.size!.height, closeTo(20, .01));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('unbroken 20k text is not admitted as a 16k page input', (
    tester,
  ) async {
    final c = ForumBodyContinuousController(), text = 'a' * 20000;
    await tester.pumpWidget(scene(document('<p>$text</p>'), c, width: 200));
    expect(c.copyText, text);
    expect(c.paragraphCount, 1);
    expect(c.size!.height, greaterThan(1000));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('content replacement retires the active pointer', (tester) async {
    final c = ForumBodyContinuousController();
    var taps = 0;
    await tester.pumpWidget(
      scene(document('<div>old</div>'), c, onTap: (_) => taps++),
    );
    final gesture = await tester.startGesture(const Offset(5, 5));
    await tester.pumpWidget(
      scene(document('<div>new</div>'), c, onTap: (_) => taps++),
    );
    await gesture.up();
    expect(taps, 0);
    expect(c.copyText, 'new');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('long press wins the arena without activating a link', (
    tester,
  ) async {
    final c = ForumBodyContinuousController();
    var taps = 0, longPresses = 0;
    await tester.pumpWidget(
      scene(
        document('<a href="https://example.invalid/">link</a>'),
        c,
        onTap: (_) => taps++,
        onLongPress: () => longPresses++,
      ),
    );
    await tester.longPressAt(const Offset(5, 5));
    expect(longPresses, 1);
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('constraint reflow retires a pointer from the previous layout', (
    tester,
  ) async {
    final c = ForumBodyContinuousController(),
        body = document('<div>text</div>');
    var taps = 0;
    await tester.pumpWidget(scene(body, c, onTap: (_) => taps++));
    final gesture = await tester.startGesture(const Offset(5, 5));
    await tester.pumpWidget(scene(body, c, width: 100, onTap: (_) => taps++));
    await gesture.up();
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final html in [
    '<ruby>base<rt>note</rt></ruby>',
    '<table><tr><td>cell</td></tr></table>',
    '<img src="https://example.invalid/a.png">',
  ]) {
    testWidgets('unsupported prototype input is explicit: $html', (
      tester,
    ) async {
      final c = ForumBodyContinuousController();
      await tester.pumpWidget(scene(document(html), c));
      expect(tester.takeException(), isA<ForumBodyContinuousUnsupported>());
      expect(c.isReady, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
