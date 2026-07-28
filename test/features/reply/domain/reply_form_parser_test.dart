import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/domain/services/reply_form_parser.dart';

void main() {
  group('ReplyFormParser', () {
    const parser = ReplyFormParser();
    final sourceUri = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572063&repquote=41554317&mobile=2',
    );

    test('parses post form hidden inputs into preparation', () {
      final result = parser.parse(
        sourceUri: sourceUri,
        html: _formHtml(
          action: 'forum.php?mod=post&action=reply&fid=33&tid=572063',
        ),
      );

      expect(result.isSuccess, isTrue);
      final preparation = result.dataOrNull!;
      expect(preparation.target.fid, '33');
      expect(preparation.target.tid, '572063');
      expect(preparation.target.pid, '41554317');
      expect(preparation.reference.formHash, 'prepared-formhash');
      expect(preparation.reference.noticeAuthor, 'notice-token');
      expect(preparation.reference.noticeTrimStr, '[quote]引用[/quote]');
      expect(preparation.reference.noticeAuthorMsg, '引用正文');
      expect(preparation.reference.repPid, 'hidden-reppid');
      expect(preparation.reference.repPost, 'hidden-reppost');
    });

    test('reads fid tid from form action when source query omits them', () {
      final result = parser.parse(
        sourceUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=post&action=reply&repquote=41554317',
        ),
        html: _formHtml(
          action:
              'forum.php?mod=post&action=reply&fid=33&tid=572063&repquote=41554317',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.target.fid, '33');
      expect(result.dataOrNull?.target.tid, '572063');
    });

    test('pid falls back to reppost then reppid when repquote is missing', () {
      final result = parser.parse(
        sourceUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572063',
        ),
        html: _formHtml(
          action: 'forum.php?mod=post&action=reply',
          repPid: 'hidden-reppid',
          repPost: 'hidden-reppost',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.target.pid, 'hidden-reppost');
      expect(result.dataOrNull?.reference.repPost, 'hidden-reppost');
    });

    test('returns parse failure without post form', () {
      final result = parser.parse(sourceUri: sourceUri, html: '<html></html>');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.parse);
    });

    test('returns parse failure when required identifiers are missing', () {
      final result = parser.parse(
        sourceUri: Uri.parse('https://bbs.yamibo.com/forum.php'),
        html: _formHtml(action: 'forum.php?mod=post&action=reply'),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, 'reply_form_parameters_missing');
      expect(result.errorOrNull?.message, isEmpty);
    });
  });
}

String _formHtml({
  required String action,
  String repPid = 'hidden-reppid',
  String repPost = 'hidden-reppost',
}) {
  return '''
<form id="postform" action="$action">
  <input type="hidden" name="formhash" value="prepared-formhash">
  <input type="hidden" name="noticeauthor" value="notice-token">
  <input type="hidden" name="noticetrimstr" value="[quote]引用[/quote]">
  <input type="hidden" name="noticeauthormsg" value="引用正文">
  <input type="hidden" name="reppid" value="$repPid">
  <input type="hidden" name="reppost" value="$repPost">
  引用预览正文
</form>
''';
}
