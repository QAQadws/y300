import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/thread/data/services/thread_detail_document_decoder.dart';

const _fixtureRoot = 'test/fixtures/thread/post_edit';
const _manifestPath = '$_fixtureRoot/manifest.json';
const _mobileThreadPath = '$_fixtureRoot/mobile_thread_with_edit_links.html';
const _mobileEditFormPath = '$_fixtureRoot/mobile_post_edit_form.html';

void main() {
  group('post edit Phase 0 fixtures', () {
    test('manifest records provenance, pairing, and the submit gate', () {
      final manifest = _readJsonObject(_manifestPath);
      final fixtures = _asStringMap(manifest['fixtures']);
      final thread = _asStringMap(fixtures['mobileThread']);
      final editForm = _asStringMap(fixtures['mobileEditForm']);
      final threadTarget = _asStringMap(thread['target']);
      final editTarget = _asStringMap(editForm['target']);

      expect(manifest['schemaVersion'], 1);
      expect(manifest['nativeSubmitEvidenceComplete'], isFalse);
      expect(thread['sanitized'], isTrue);
      expect(editForm['sanitized'], isTrue);
      expect(thread['sourceSha256'], matches(RegExp(r'^[A-F0-9]{64}$')));
      expect(editForm['sourceSha256'], matches(RegExp(r'^[A-F0-9]{64}$')));
      expect(threadTarget['fid'], editTarget['fid']);
      expect(threadTarget['tid'], editTarget['tid']);
      expect(threadTarget['pairedPid'], editTarget['pid']);
      expect(threadTarget['additionalObservedEditablePids'], <String>[
        '41588620',
      ]);
    });

    test('thread edit link and edit form describe the same target', () {
      final decoder = ThreadDetailDocumentDecoder(
        createY300ThreadDetailHtmlDecoder(),
      );
      final detail = decoder.decode(
        _readUtf8(_mobileThreadPath),
        fallbackTid: '557857',
        fallbackPage: 215,
      );
      final post = detail.posts.singleWhere(
        (candidate) => candidate.pid == '41587383',
      );
      final editUri = Uri.parse(post.editUrl!);
      final document = html_parser.parse(_readUtf8(_mobileEditFormPath));

      expect(_inputValue(document, 'fid'), editUri.queryParameters['fid']);
      expect(_inputValue(document, 'tid'), editUri.queryParameters['tid']);
      expect(_inputValue(document, 'pid'), editUri.queryParameters['pid']);
      expect(_inputValue(document, 'page'), editUri.queryParameters['page']);
    });

    test('edit form preserves the observed safe DOM contract', () {
      final document = html_parser.parse(_readUtf8(_mobileEditFormPath));
      final forms = document.querySelectorAll('form#postform');

      expect(forms, hasLength(1));
      final form = forms.single;
      expect(form.attributes['method']?.toLowerCase(), 'post');
      expect(form.attributes['enctype']?.toLowerCase(), 'multipart/form-data');
      final submitUri = Uri.parse(form.attributes['action']!);
      expect(submitUri.path, 'forum.php');
      expect(submitUri.queryParameters['mod'], 'post');
      expect(submitUri.queryParameters['action'], 'edit');
      expect(submitUri.queryParameters['editsubmit'], 'yes');
      expect(_inputValue(document, 'formhash'), 'fixture-formhash');
      expect(_inputValue(document, 'editsubmit'), 'yes');
      expect(
        document.querySelector('textarea#needmessage[name="message"]')?.text,
        contains('[attachimg]1624572[/attachimg]'),
      );
      expect(
        document.querySelector('#imglist span.del[aid="1624572"]'),
        isNotNull,
      );
      expect(document.querySelector('#attlist')?.children, isEmpty);
      expect(document.querySelector('.post_btn #postsubmit'), isNotNull);
    });

    test('HTML fixtures contain no captured session bootstrap', () {
      for (final path in <String>[
        _mobileThreadPath,
        _mobileEditFormPath,
        '$_fixtureRoot/desktop_thread_with_edit_links.html',
      ]) {
        final html = _readUtf8(path);
        expect(html, isNot(contains('discuz_uid')));
        expect(html, isNot(contains('cookiepre')));
        expect(html, isNot(contains('REPORTURL')));
        expect(html, isNot(contains('<script')));
        expect(html, isNot(contains('uc_server/data/avatar')));
      }
    });
  });
}

String _readUtf8(String path) {
  return File(path).readAsStringSync(encoding: utf8);
}

Map<String, dynamic> _readJsonObject(String path) {
  final decoded = jsonDecode(_readUtf8(path));
  if (decoded is! Map) {
    throw FormatException('Fixture root must be a JSON object: $path');
  }
  return _asStringMap(decoded);
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is! Map) {
    return <String, dynamic>{};
  }
  return value.map(
    (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
  );
}

String? _inputValue(html_dom.Document document, String name) {
  for (final input in document.querySelectorAll('input[name]')) {
    if (input.attributes['name'] == name) {
      return input.attributes['value'] ?? '';
    }
  }
  return null;
}
