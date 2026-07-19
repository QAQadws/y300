import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_comment_diagnostics.dart';

void main() {
  test('tid diagnostics use a stable non-reversible summary', () {
    final first = comicCommentTidHash('570140');
    final second = comicCommentTidHash('570140');

    expect(first, second);
    expect(first, isNot('570140'));
    expect(first, hasLength(16));
  });

  test('diagnostic fields contain counters but no comment content', () {
    const event = ComicCommentDiagnosticEvent(
      sourceTidHash: '0123456789abcdef',
      event: 'success',
      page: 0,
      expectedPages: 2,
      postCount: 40,
      filteredFirstCount: 1,
      deduplicatedCount: 39,
      duration: Duration(milliseconds: 12),
      errorCode: null,
    );

    final fields = event.toLogFields();

    expect(fields, contains('posts=40'));
    expect(fields, contains('filteredFirst=1'));
    expect(fields, contains('deduplicated=39'));
    expect(fields, isNot(contains('正文')));
    expect(fields, isNot(contains('Cookie')));
  });
}
