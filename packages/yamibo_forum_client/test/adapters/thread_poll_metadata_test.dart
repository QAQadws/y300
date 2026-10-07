import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:yamibo_forum_client/src/adapters/thread_detail_snapshot_codec.dart';

void main() {
  for (final mobile in [true, false]) {
    final source = mobile ? 'mobile' : 'desktop';
    for (final sample in [
      ('单选投票 , 投票后结果可见, 共有 15 人参与投票', 15, '单选投票 , 投票后结果可见'),
      ('多选投票: ( 最多可选 2 项 ), 共有 10 人参与投票', 10, '多选投票: ( 最多可选 2 项 )'),
      ('单选投票，共有 0 人参与投票', 0, '单选投票'),
      ('單選投票，投票後結果可見，共有 21 人參與投票', 21, '單選投票，投票後結果可見'),
      ('共有 0 人参与投票', 0, ''),
    ]) {
      test('$source separates voters from rules: ${sample.$1}', () {
        final poll = _detail(
          summary: sample.$1,
          mobile: mobile,
        ).posts.single.poll!;
        expect(poll.summary, sample.$1);
        expect(poll.participantCount, sample.$2);
        expect(poll.rulesText, sample.$3);
        expect(poll.options, hasLength(2));
        expect(
          poll.options.every((option) => option.voteCount == null),
          isTrue,
        );
        expect(poll.options.every((option) => option.percent == null), isTrue);
      });
    }

    for (final summary in [
      '单选投票，共有未知人数参与投票',
      '单选投票，共有 -1 人参与投票',
      '单选投票，共有 99999999999999999999999999 人参与投票',
      '单选投票，最多可选 2 项，15 票',
      '单选投票，共有 15 人参与投票，未知附加规则',
    ]) {
      test('$source preserves an unrecognized summary: $summary', () {
        final poll = _detail(
          summary: summary,
          mobile: mobile,
        ).posts.single.poll!;
        expect(poll.summary, summary);
        expect(poll.participantCount, isNull);
        expect(poll.rulesText, isNull);
      });
    }

    test('$source multiple-choice totals do not determine participation', () {
      final poll = _detail(
        summary: '多选投票: ( 最多可选 2 项 ), 共有 10 人参与投票',
        mobile: mobile,
        multiple: true,
        results: true,
      ).posts.single.poll!;
      expect(poll.isMultipleChoice, isTrue);
      expect(poll.maxChoices, 2);
      expect(poll.options.map((option) => option.voteCount), [9, 8]);
      expect(poll.participantCount, 10);
    });
  }

  test('desktop voters link stays in the source summary but not the rules', () {
    final poll = _detail(
      summary: '单选投票, 共有 15 人参与投票',
      mobile: false,
      votersLink: true,
    ).posts.single.poll!;
    expect(poll.summary, '单选投票, 共有 15 人参与投票 查看投票参与人');
    expect(poll.participantCount, 15);
    expect(poll.rulesText, '单选投票');
  });

  const codec = ThreadDetailSnapshotCodec();
  for (final summary in [
    '单选投票, 投票后结果可见, 共有 15 人参与投票',
    '共有 0 人参与投票',
    'unknown poll summary',
  ]) {
    test('snapshot preserves optional metadata and empty rules: $summary', () {
      final detail = _detail(summary: summary, mobile: true);
      final original = detail.posts.single.poll!;
      final decoded = codec.decode(codec.encode(detail)).posts.single.poll!;
      expect(decoded.participantCount, original.participantCount);
      expect(decoded.rulesText, original.rulesText);
      expect(decoded.summary, original.summary);
    });

    test('legacy snapshot uses the same conservative extraction: $summary', () {
      final detail = _detail(summary: summary, mobile: true);
      final json = codec.encode(detail) as Map<String, Object?>;
      final encodedPoll = _encodedPoll(json);
      encodedPoll.remove('participantCount');
      encodedPoll.remove('rulesText');
      final original = detail.posts.single.poll!;
      final decoded = codec.decode(json).posts.single.poll!;
      expect(decoded.participantCount, original.participantCount);
      expect(decoded.rulesText, original.rulesText);
      expect(decoded.summary, original.summary);
      expect(codec.canDecodeVersion(codecVersion: 1, parserVersion: 2), isTrue);
    });
  }

  test('nullable metadata is not replaced with guessed numbers on decode', () {
    final json =
        codec.encode(_detail(summary: '单选投票, 共有 15 人参与投票', mobile: true))
            as Map<String, Object?>;
    final poll = _encodedPoll(json);
    poll['participantCount'] = null;
    poll['rulesText'] = null;
    final decoded = codec.decode(json).posts.single.poll!;
    expect(decoded.participantCount, isNull);
    expect(decoded.rulesText, isNull);
    poll['participantCount'] = 'not a count';
    poll['rulesText'] = 15;
    final malformed = codec.decode(json).posts.single.poll!;
    expect(malformed.participantCount, isNull);
    expect(malformed.rulesText, isNull);
  });
}

Map<String, Object?> _encodedPoll(Map<String, Object?> json) =>
    ((json['posts'] as List<Object?>).single as Map<String, Object?>)['poll']
        as Map<String, Object?>;

ThreadDetailData _detail({
  required String summary,
  required bool mobile,
  bool multiple = false,
  bool results = false,
  bool votersLink = false,
}) {
  final inputType = multiple ? 'checkbox' : 'radio';
  final options = StringBuffer();
  for (var id = 1; id <= 2; id++) {
    final selector =
        '<input type="$inputType" name="pollanswers[]" '
        'value="$id" id="option_$id"><label for="option_$id">$id.选项$id</label>';
    final votes = id == 1 ? 9 : 8;
    if (mobile) {
      options.write('<p>$selector');
      if (results) options.write('<em>80% ($votes票)</em>');
      options.write('</p>');
    } else {
      options.write('<tr><td>$selector</td></tr>');
      if (results) {
        options.write('<tr><td><div class="pbr">80% ($votes)</div></td></tr>');
      }
    }
  }
  final link = votersLink
      ? ' <a href="forum.php?mod=misc&amp;action=viewvote&amp;tid=100">查看投票参与人</a>'
      : '';
  final html = mobile
      ? '''
<html><body id="forum"><div class="viewthread"><div class="plc" id="pid1">
  <div class="authi"><div class="mtit"><span class="y">1#</span></div></div>
  <div class="message"><div class="poll"><form id="poll">
    <div class="poll_txt">$summary</div><div class="poll_box">$options</div>
  </form></div></div>
</div></div></body></html>
'''
      : '''
<html><body><div id="postlist"><div id="post_1">
  <form id="poll"><div class="pinf">$summary$link</div>
    <table summary="poll panel">$options</table>
  </form><div id="postmessage_1">Synthetic post</div>
</div></div></body></html>
''';
  return ThreadDetailHtmlParser(
    siteOrigin: Uri.parse('https://example.test'),
  ).parse(html, fallbackTid: '100', fallbackPage: 1);
}
