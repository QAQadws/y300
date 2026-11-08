import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'render_test_support.dart';

void main() {
  const html =
      '<div><p>短段</p><p>较长段落，保留正文测量与段间距。</p>'
      '<blockquote><p>引用甲</p><p>引用乙</p></blockquote>'
      '<table><tr><td><p>表格</p></td></tr></table>'
      '<div class="showcollapse"><div class="showcollapse_title">折叠</div>'
      '<div class="showcollapse_content"><p>折叠正文</p></div></div>'
      '<div style="border:1px solid red;padding:4px"><p>框甲</p><p>框乙</p></div>'
      '<hr><img width="10" height="10" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==">尾部</div>';
  final document = prepareRenderTestDocument(html);
  Widget app(ForumHtmlBlockDecorator? decorator) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ForumHtmlRenderer(
          preparedDocument: document,
          theme: forumHtmlTestTheme,
          options: renderTestOptions,
          labels: renderTestLabels,
          buildAsync: false,
          blockDecorator: decorator,
        ),
      ),
    ),
  );
  Finder text(String value) => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText() == value,
  );

  testWidgets('decoration preserves layout and groups protected blocks once', (
    tester,
  ) async {
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();
    final baseline = {
      for (final value in ['短段', '较长段落，保留正文测量与段间距。', '引用甲', '引用乙', '表格', '尾部'])
        value: tester.getRect(text(value)),
    };
    await tester.pumpWidget(app((_, child) => _Marker(child: child)));
    await tester.pumpAndSettle();
    expect(find.byType(_Marker), findsNWidgets(9));
    for (final element in find.byType(_Marker).evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(_Marker),
        ),
        findsNothing,
      );
    }
    for (final entry in baseline.entries) {
      expect(tester.getRect(text(entry.key)), entry.value);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing a paint decorator retains the body', (tester) async {
    await tester.pumpWidget(app((_, child) => _Marker(child: child)));
    await tester.pumpAndSettle();
    final retained = tester.element(text('短段'));
    await tester.pumpWidget(
      app((_, child) => _Marker(revision: 2, child: child)),
    );
    await tester.pumpAndSettle();
    expect(tester.element(text('短段')), same(retained));
    expect(
      tester
          .widgetList<_Marker>(find.byType(_Marker))
          .every((w) => w.revision == 2),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

class _Marker extends StatelessWidget {
  const _Marker({required this.child, this.revision = 1});
  final Widget child;
  final int revision;
  @override
  Widget build(BuildContext context) => child;
}
