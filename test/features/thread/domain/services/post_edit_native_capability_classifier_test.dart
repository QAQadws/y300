import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/services/post_edit_form_parser.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_native_capability_classifier.dart';

const _fixturePath =
    'test/fixtures/thread/post_edit/mobile_post_edit_form.html';

void main() {
  final target = PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=557857&pid=41587383&page=215',
    ),
    fid: '5',
    tid: '557857',
    pid: '41587383',
    page: 215,
    isFirstPost: false,
  );
  const classifier = PostEditNativeCapabilityClassifier();

  test('ordinary fixture is native supported', () {
    final snapshot = _parse(_readFixture(), target);
    final decision = classifier.classify(snapshot);

    expect(decision, isA<PostEditNativeSupported>());
  });

  test('special, sort, plugin, file and unknown controls fall back', () {
    final cases = <String, String>{
      'special': _readFixture().replaceFirst(
        '</form>',
        '<input type="hidden" name="special" value="1"></form>',
      ),
      'sort': _readFixture().replaceFirst(
        '</form>',
        '<input type="hidden" name="sortid" value="1"></form>',
      ),
      'plugin': _readFixture().replaceFirst(
        '</form>',
        '<input type="hidden" name="plugin_custom" value="1"></form>',
      ),
      'file': _readFixture().replaceFirst(
        '<ul id="attlist" class="post_attlist setbox cl"></ul>',
        '<ul id="attlist" class="post_attlist setbox cl"><li aid="99">file.zip</li></ul>',
      ),
      'unknown': _readFixture().replaceFirst(
        '</form>',
        '<input type="color" name="mystery" value="#fff"></form>',
      ),
    };

    for (final entry in cases.entries) {
      final decision = classifier.classify(_parse(entry.value, target));
      expect(decision, isA<PostEditWebViewOnly>(), reason: entry.key);
      final reason = (decision as PostEditWebViewOnly).reason;
      final expected = switch (entry.key) {
        'file' => PostEditFallbackReason.unsupportedRegularAttachment,
        'special' => PostEditFallbackReason.unsupportedSpecialThread,
        'sort' => PostEditFallbackReason.unsupportedThreadSort,
        'plugin' => PostEditFallbackReason.unsupportedPluginField,
        _ => PostEditFallbackReason.unknownSuccessfulControl,
      };
      expect(reason, expected, reason: entry.key);
    }
  });

  test('unsafe html mode is not native supported', () {
    final html = _readFixture().replaceFirst(
      'name="bbcodeoff" value="1">',
      'name="bbcodeoff" value="1" checked>',
    );
    final decision = classifier.classify(_parse(html, target));

    expect(decision, isA<PostEditWebViewOnly>());
    expect(
      (decision as PostEditWebViewOnly).reason,
      PostEditFallbackReason.unsupportedHtmlMode,
    );
  });
}

PostEditFormSnapshot _parse(String html, PostEditTarget target) {
  return const PostEditFormParser().parse(html, target: target).snapshot!;
}

String _readFixture() {
  return File(_fixturePath).readAsStringSync(encoding: utf8);
}
