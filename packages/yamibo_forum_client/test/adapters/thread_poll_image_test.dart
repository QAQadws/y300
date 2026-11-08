import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:yamibo_forum_client/src/adapters/thread_detail_snapshot_codec.dart';

void main() {
  for (final mobile in [true, false]) {
    for (final voting in [true, false]) {
      test(
        '${mobile ? 'mobile' : 'desktop'} image/text options, voting=$voting',
        () {
          final detail = _detail(mobile: mobile, voting: voting);
          final poll = detail.posts.single.poll!;
          expect(poll.canVote, voting);
          expect(poll.options, hasLength(3));
          expect(poll.options.map((o) => o.label), ['选项一', '选项二', '纯文字']);
          expect(poll.options.first.voteCount, 88);
          expect(poll.options.first.percent, 8.65);
          expect(poll.options.first.colorHex, '#E92725');
          expect(
            poll.options.first.image!.url,
            'https://example.test/data/attachment/forum/poll.png.thumb.jpg',
          );
          expect(poll.options.first.image!.alt, '01.png');
          expect(
            poll.options[1].image!.url,
            'https://cdn.example.test/poll.jpg',
          );
          expect(poll.options[2].image, isNull);
          if (voting || !mobile) {
            expect(poll.options.map((o) => o.id), ['101', '102', '103']);
          }
          const codec = ThreadDetailSnapshotCodec();
          final decoded = codec.decode(codec.encode(detail)).posts.single.poll!;
          expect(
            decoded.options.first.image!.url,
            poll.options.first.image!.url,
          );
          expect(decoded.options.first.image!.alt, '01.png');
          expect(decoded.options[1].image!.width, 130);
          expect(decoded.options[1].image!.height, 200);
          expect(decoded.options[2].image, isNull);
          expect(decoded.canVote, voting);
        },
      );
    }
    test(
      'empty image labels are retained; unsafe and placeholder sources are omitted ($mobile)',
      () {
        final poll = _detail(
          mobile: mobile,
          source: '<img src="javascript:alert(1)">',
          firstLabel: '',
        ).posts.single.poll!;
        expect(poll.options, hasLength(2));
        final imageOnly = _detail(
          mobile: mobile,
          firstLabel: '',
        ).posts.single.poll!;
        expect(imageOnly.options.first.label, isEmpty);
        expect(imageOnly.options.first.image, isNotNull);
        final placeholder = _detail(
          mobile: mobile,
          source: '<img src="static/image/common/nophoto.gif">',
        ).posts.single.poll!;
        expect(placeholder.options.first.image, isNull);
      },
    );
  }
  test('old snapshots do not need the additive image field', () {
    const codec = ThreadDetailSnapshotCodec();
    final encoded = codec.encode(_detail(mobile: true)) as Map<String, Object?>;
    final poll = ((encoded['posts'] as List).single as Map)['poll'] as Map;
    for (final option in poll['options'] as List) {
      (option as Map).remove('image');
    }
    expect(
      codec
          .decode(encoded)
          .posts
          .single
          .poll!
          .options
          .every((o) => o.image == null),
      isTrue,
    );
  });
}

// Mirrors Discuz default touch and desktop viewthread_poll templates; synthetic
// text/identifiers avoid copying session-bearing page markup into fixtures.
ThreadDetailData _detail({
  required bool mobile,
  bool voting = true,
  String? source,
  String firstLabel = '选项一',
}) {
  final options = StringBuffer();
  for (var i = 1; i <= 3; i++) {
    final label = [firstLabel, '选项二', '纯文字'][i - 1];
    final input = voting
        ? '<input type="checkbox" name="pollanswers[]" id="option_$i" value="${100 + i}">'
        : '';
    final image = i == 1
        ? source ??
              '<a class="mimg vm"><img src="data/attachment/forum/poll.png.thumb.jpg" alt="01.png" style="min-width:auto;min-height:auto"></a>'
        : i == 2
        ? '<img src="//cdn.example.test/poll.jpg" width="130px" height="200" zoomfile="https://example.test/original.jpg">'
        : '';
    if (mobile) {
      options.write(
        '<p>$image$input<label for="option_$i">$i.$label</label><em class="y" style="color:#E92725">8.65% (88票)</em></p><hr>',
      );
    } else {
      options.write(
        '<td id="polloption_${100 + i}"><div class="polltd cl">$image<p class="mtn mbn xi2"><label>$input</label>$label</p><div class="imgf imgf2"><span class="jdt" style="width:8.65%;background-color:#E92725"></span><p class="imgfc"><span class="z">88票</span><span class="y">8.65%</span></p></div></div></td>',
      );
    }
  }
  final html = mobile
      ? '''
<html><body id="forum"><div class="viewthread"><div class="plc" id="pid1">
<div class="authi"><div class="mtit"><span class="y">1#</span></div></div>
<div class="message"><div class="poll"><form id="poll"><div class="poll_txt">多选投票: ( 最多可选 2 项 ), 共有 459 人参与投票</div><div class="poll_box">$options</div></form></div></div>
</div></div></body></html>'''
      : '''<html><body><div id="postlist"><div id="post_1"><form id="poll"><div class="pinf">多选投票: ( 最多可选 2 项 ), 共有 459 人参与投票</div><table summary="poll panel"><tr>$options</tr></table></form><div id="postmessage_1">Synthetic post</div></div></div></body></html>''';
  return ThreadDetailHtmlParser(
    siteOrigin: Uri.parse('https://example.test'),
  ).parse(html, fallbackTid: '100', fallbackPage: 1);
}
