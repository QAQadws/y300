import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  for (final (css, position, first, next) in [
    (
      'alternate',
      ForumBodyRubyPosition.alternate,
      ForumBodyRubySide.over,
      ForumBodyRubySide.under,
    ),
    (
      'alternate over',
      ForumBodyRubyPosition.alternateOver,
      ForumBodyRubySide.over,
      ForumBodyRubySide.under,
    ),
    (
      'under alternate',
      ForumBodyRubyPosition.alternateUnder,
      ForumBodyRubySide.under,
      ForumBodyRubySide.over,
    ),
    (
      'over',
      ForumBodyRubyPosition.over,
      ForumBodyRubySide.over,
      ForumBodyRubySide.over,
    ),
    (
      'under',
      ForumBodyRubyPosition.under,
      ForumBodyRubySide.under,
      ForumBodyRubySide.under,
    ),
    ('inter-character', ForumBodyRubyPosition.interCharacter, null, null),
  ]) {
    test('ruby-position resolves inherited value and level side: $css', () {
      final document = const ForumBodyParser().parse(
        html: '<ruby style="ruby-position:$css">A<rtc><rt>x</rt></rtc></ruby>',
        sourceId: 'ruby-position',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontSize: 20),
          fontRevision: 'test',
          linkColor: const Color(0xff0000ff),
        ),
      );
      expect(styles.issues, isEmpty);
      for (final node in document.descendants.whereType<ForumBodyElement>()) {
        expect(styles.byPath[node.path]!.rubyPosition, position);
      }
      expect(position.sideAfter(null), first);
      expect(position.sideAfter(first), next);
      expect(position.sideAfter(next), first);
      expect(ForumBodyRubyPosition.tryParse(css.toUpperCase()), position);
    });
  }

  test('global keywords and role override restoration retain ruby position', () {
    final document = const ForumBodyParser().parse(
      html:
          '<div style="ruby-position:under;font-size:30px"><ruby>A<rtc style="ruby-position:inherit"><rt>x</rt></rtc></ruby><ruby style="ruby-position:initial">B</ruby><ruby style="ruby-position:unset">C</ruby></div>',
      sourceId: 'ruby-position',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: 20),
        fontRevision: 'test',
        linkColor: const Color(0xff0000ff),
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
        }),
      ),
    );
    final elements = document.descendants
        .whereType<ForumBodyElement>()
        .toList();
    final rt = elements.singleWhere((node) => node.tag == 'rt');
    expect(styles.byPath[rt.path]!.rubyPosition, ForumBodyRubyPosition.under);
    expect(styles.byPath[rt.path]!.textStyle.fontSize, 15);
    final rubies = elements.where((node) => node.tag == 'ruby').toList();
    expect(
      styles.byPath[rubies[1].path]!.rubyPosition,
      ForumBodyRubyPosition.alternate,
    );
    expect(
      styles.byPath[rubies[2].path]!.rubyPosition,
      ForumBodyRubyPosition.under,
    );
  });

  for (final invalid in ['over under', 'alternate alternate', 'under extra']) {
    test(
      'invalid ruby-position preserves inherited value as a whole: $invalid',
      () {
        final document = const ForumBodyParser().parse(
          html:
              '<div style="ruby-position:under"><ruby style="ruby-position:$invalid">A<rt>x</rt></ruby></div>',
          sourceId: 'ruby-position',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          ForumBodyReaderStyle(
            textStyle: const TextStyle(fontSize: 20),
            fontRevision: 'test',
            linkColor: const Color(0xff0000ff),
          ),
        );
        final ruby = document.descendants
            .whereType<ForumBodyElement>()
            .singleWhere((node) => node.tag == 'ruby');
        expect(
          styles.byPath[ruby.path]!.rubyPosition,
          ForumBodyRubyPosition.under,
        );
        expect(
          styles.issues.any((issue) => issue.property == 'ruby-position'),
          isTrue,
        );
      },
    );
  }
}
