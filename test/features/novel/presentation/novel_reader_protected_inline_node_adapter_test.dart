import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_flowability_inspector.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_protected_inline_node_adapter.dart';

void main() {
  const adapter = DefaultNovelReaderProtectedInlineNodeAdapter();

  test('accepts an explicitly sized forum smiley', () {
    final element = html_parser
        .parseFragment(
          '<img src="static/image/smiley/gexing/008.gif" '
          'width="36" height="28">',
        )
        .querySelector('img')!;

    final assessment = adapter.assess(element);

    expect(assessment.isStable, isTrue);
    expect(assessment.kind, NovelReaderProtectedInlineNodeKind.forumSmiley);
    expect(assessment.width, 36);
    expect(assessment.height, 28);
  });

  test('rejects an unsized smiley because decode could reflow the page', () {
    final element = html_parser
        .parseFragment(
          '<img smilieid="354" src="static/image/smiley/gexing/008.gif">',
        )
        .querySelector('img')!;

    final assessment = adapter.assess(element);

    expect(assessment.isCandidate, isTrue);
    expect(assessment.isStable, isFalse);
    expect(
      assessment.failure,
      NovelReaderProtectedInlineNodeFailure.missingStableDimensions,
    );
  });

  test('requires an explicit registration for non-smiley inline images', () {
    final ordinary = html_parser
        .parseFragment('<img src="cover.jpg" width="24" height="24">')
        .querySelector('img')!;
    final registered = html_parser
        .parseFragment(
          '<img data-y300-protected-inline="1" src="badge.png" '
          'width="18" height="18">',
        )
        .querySelector('img')!;

    expect(adapter.assess(ordinary).isCandidate, isFalse);
    expect(adapter.assess(registered).isStable, isTrue);
    expect(
      adapter.assess(registered).kind,
      NovelReaderProtectedInlineNodeKind.declaredInlineImage,
    );
  });

  test('flowability admits only stable protected inline nodes', () {
    const inspector = DefaultNovelReaderComplexHtmlFlowabilityInspector();

    final stable = inspector.inspect(
      '<p>前<img src="static/image/smiley/gexing/008.gif" '
      'width="36" height="28">后</p>',
    );
    final unstable = inspector.inspect(
      '<p>前<img src="static/image/smiley/gexing/008.gif">后</p>',
    );

    expect(stable.isFlowable, isTrue);
    expect(stable.hasProtectedInlineNodes, isTrue);
    expect(unstable.isFlowable, isFalse);
    expect(
      unstable.failure,
      NovelReaderComplexHtmlFlowabilityFailure.containsAtomicWidget,
    );
  });
}
