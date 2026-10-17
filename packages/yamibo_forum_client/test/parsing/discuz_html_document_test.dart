import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/parsing/discuz_html_document.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  test('one response owns one context and one lazily decoded DOM', () {
    final source = _document('<p id="body">Fixture</p>');
    final response = _response(source);
    final context = DiscuzHtmlDocument.forResponse(response);
    final document = context.document;

    expect(context.source, same(source));
    expect(DiscuzHtmlDocument.forResponse(response), same(context));
    expect(DiscuzHtmlDocument.forResponse(response).document, same(document));
    expect(context.isCompleteDocument, isTrue);
    expect(context.hasUnexpectedEof, isFalse);
    expect(context.document, same(document));
    expect(document.querySelector('#body')!.text, 'Fixture');
    expect(response.body, same(source));
  });

  test('equal URLs and source text in different responses never share DOM', () {
    final source = _document('<p id="body">Fixture</p>');
    final first = DiscuzHtmlDocument.forResponse(_response(source));
    final second = DiscuzHtmlDocument.forResponse(_response(source));
    expect(first, isNot(same(second)));
    expect(first.document, isNot(same(second.document)));
  });

  test('cached source contexts remain independent from network responses', () {
    final source = _document('<p>Fixture</p>');
    final response = DiscuzHtmlDocument.forResponse(_response(source));
    final first = DiscuzHtmlDocument.fromSource(source);
    final second = DiscuzHtmlDocument.fromSource(source);
    expect(first.document, isNot(same(response.document)));
    expect(first.document, isNot(same(second.document)));
    expect(first.isCompleteDocument, isTrue);
    expect(first.hasUnexpectedEof, isFalse);
  });

  test('a nontext response is rejected without decoding a guessed source', () {
    for (final body in <Object?>[
      null,
      <int>[1, 2],
      <String, String>{},
    ]) {
      expect(
        () => DiscuzHtmlDocument.forResponse(_response(body)),
        throwsArgumentError,
      );
    }
  });

  test('closed raw text and comments cannot supply extra shell boundaries', () {
    final context = DiscuzHtmlDocument.fromSource(
      _document('''
<script>var text = '<html><head></head><body></body></html>';</script>
<style>/* <html><body></body></html> */</style>
<!-- <html><head></head><body></body></html> -->
<textarea><html><head></head><body></body></html></textarea>
<p>Fixture</p>
'''),
    );
    expect(context.isCompleteDocument, isTrue);
    expect(context.hasUnexpectedEof, isFalse);
  });

  for (final source in <String>[
    '<p>Fragment</p>',
    '<html><head></head><body>Truncated',
    '<html><head></head><body></body></html>trailer',
    '<html><head></head><body></body></html><html></html>',
    '<html><head></head><body><body></body></html>',
  ]) {
    test('repaired DOM cannot prove a complete source shell: $source', () {
      final context = DiscuzHtmlDocument.fromSource(source);
      expect(context.isCompleteDocument, isFalse);
      final document = context.document;
      expect(document.body, isNotNull);
      expect(context.document, same(document));
    });
  }

  for (final trailer in <String>[
    '<script>var trailer = "</body></html>',
    '<style>/* </body></html>',
    '<textarea></body></html>',
    '<!-- </body></html>',
  ]) {
    test('EOF evidence survives source-like raw closing tags: $trailer', () {
      final context = DiscuzHtmlDocument.fromSource(
        '<html><head></head><body>$trailer',
      );
      // These literal closing tags pass the lexical shell check, but belong
      // to an unterminated raw-text/comment token in the actual parser.
      expect(context.isCompleteDocument, isTrue);
      expect(context.hasUnexpectedEof, isTrue);
      final document = context.document;
      expect(context.hasUnexpectedEof, isTrue);
      expect(context.document, same(document));
    });
  }
}

String _document(String body) =>
    '<!DOCTYPE html><html><head></head><body>$body</body></html>';

ForumResponse<Object?> _response(Object? body) => ForumResponse<Object?>(
  uri: Uri.parse('https://forum.example.test/forum.php'),
  statusCode: 200,
  headers: const {},
  body: body,
);
