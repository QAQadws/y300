import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  // Render values can be constructed without Host preferences or conversion
  // types. Host projection is covered by the App's preference tests.
  const options = ForumHtmlRenderOptions(
    fontScale: 1.25,
    lineHeightScale: 1.8,
    paragraphSpacing: 18,
    preserveAuthorFontSize: false,
  );

  test('equal render options share value and hash identity', () {
    final equal = ForumHtmlRenderOptions(
      fontScale: options.fontScale,
      lineHeightScale: options.lineHeightScale,
      paragraphSpacing: options.paragraphSpacing,
      preserveAuthorFontSize: options.preserveAuthorFontSize,
    );

    expect(equal, options);
    expect(equal.hashCode, options.hashCode);
    expect(options.copyWith(), options);
    expect({options, equal}, hasLength(1));
  });

  test('copyWith preserves omitted values and includes all four fields', () {
    final updated = options.copyWith(
      fontScale: 1.4,
      lineHeightScale: 2,
      paragraphSpacing: 24,
      preserveAuthorFontSize: true,
    );

    expect(
      updated,
      const ForumHtmlRenderOptions(
        fontScale: 1.4,
        lineHeightScale: 2,
        paragraphSpacing: 24,
        preserveAuthorFontSize: true,
      ),
    );
    final fontOnly = options.copyWith(fontScale: 1.4);
    expect(fontOnly.fontScale, 1.4);
    expect(fontOnly.lineHeightScale, options.lineHeightScale);
    expect(fontOnly.paragraphSpacing, options.paragraphSpacing);
    expect(fontOnly.preserveAuthorFontSize, options.preserveAuthorFontSize);
    expect({
      options,
      fontOnly,
      options.copyWith(lineHeightScale: 2),
      options.copyWith(paragraphSpacing: 24),
      options.copyWith(preserveAuthorFontSize: true),
    }, hasLength(5));
    expect(
      options
          .copyWith(lineHeightScale: 2)
          .copyWith(lineHeightScale: options.lineHeightScale),
      options,
    );
    expect(
      options
          .copyWith(paragraphSpacing: 24)
          .copyWith(paragraphSpacing: options.paragraphSpacing),
      options,
    );
    expect(
      options
          .copyWith(preserveAuthorFontSize: true)
          .copyWith(preserveAuthorFontSize: options.preserveAuthorFontSize),
      options,
    );
    expect(options.fontScale, 1.25);
  });

  test('collapse labels compare all localized values', () {
    const labels = ForumHtmlCollapseLabels(
      fallbackTitle: 'section',
      expandedSemanticsLabel: 'opened',
      collapsedSemanticsLabel: 'closed',
    );
    final equal = ForumHtmlCollapseLabels(
      fallbackTitle: labels.fallbackTitle,
      expandedSemanticsLabel: labels.expandedSemanticsLabel,
      collapsedSemanticsLabel: labels.collapsedSemanticsLabel,
    );

    expect(equal, labels);
    expect(equal.hashCode, labels.hashCode);
    expect({labels, equal}, hasLength(1));
    for (final changed in const [
      ForumHtmlCollapseLabels(
        fallbackTitle: 'other section',
        expandedSemanticsLabel: 'opened',
        collapsedSemanticsLabel: 'closed',
      ),
      ForumHtmlCollapseLabels(
        fallbackTitle: 'section',
        expandedSemanticsLabel: 'other opened',
        collapsedSemanticsLabel: 'closed',
      ),
      ForumHtmlCollapseLabels(
        fallbackTitle: 'section',
        expandedSemanticsLabel: 'opened',
        collapsedSemanticsLabel: 'other closed',
      ),
    ]) {
      expect(changed, isNot(labels));
    }
  });
}
