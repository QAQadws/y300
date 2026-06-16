import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/posting_draft_extras_codec.dart';

void main() {
  const codec = PostingDraftExtrasCodec();

  group('PostingDraftExtrasCodec', () {
    test('encodes only set fields, omits defaults', () {
      final encoded = codec.encode(
        selectedTypeId: null,
        allowNoticeAuthor: false,
        bbCodeOff: false,
        smileyOff: false,
        parseUrlOff: false,
        tags: const <String>[],
        special: NewThreadSpecial.normal,
        poll: null,
      );
      expect(encoded, isEmpty);
    });

    test('encodes typeid, options and tags', () {
      final encoded = codec.encode(
        selectedTypeId: '101',
        allowNoticeAuthor: true,
        bbCodeOff: false,
        smileyOff: true,
        parseUrlOff: false,
        tags: const ['百合', '动画'],
        special: NewThreadSpecial.normal,
        poll: null,
      );
      expect(encoded['typeid'], '101');
      expect(encoded['allowNoticeAuthor'], '1');
      expect(encoded['smileyOff'], '1');
      expect(encoded['tags'], '百合,动画');
      expect(encoded.containsKey('special'), isFalse);
    });

    test('decode returns sane defaults for empty map', () {
      final decoded = codec.decode(const <String, String>{});
      expect(decoded.selectedTypeId, isNull);
      expect(decoded.allowNoticeAuthor, isFalse);
      expect(decoded.tags, isEmpty);
      expect(decoded.special, NewThreadSpecial.normal);
      expect(decoded.poll, isNull);
    });

    test('decode reconstructs tags with trim', () {
      final decoded = codec.decode(const <String, String>{'tags': '百合, 动画 '});
      expect(decoded.tags, ['百合', '动画']);
    });

    test('round-trips a poll draft', () {
      final encoded = codec.encode(
        selectedTypeId: null,
        allowNoticeAuthor: false,
        bbCodeOff: false,
        smileyOff: false,
        parseUrlOff: false,
        tags: const <String>[],
        special: NewThreadSpecial.poll,
        poll: const NewThreadPollDraft(
          options: ['A', 'B', 'C'],
          multiple: true,
          maxChoices: 2,
          expirationDays: 7,
          overt: true,
          visibilityPoll: true,
        ),
      );
      // poll 字段被写出
      expect(encoded['pollOptions'], 'A\nB\nC');
      expect(encoded['pollMultiple'], '1');
      expect(encoded['pollMaxChoices'], '2');
      expect(encoded['pollExpirationDays'], '7');
      expect(encoded['pollOvert'], '1');
      expect(encoded['pollVisibility'], '1');
      expect(encoded['special'], 'poll');

      final decoded = codec.decode(encoded);
      expect(decoded.special, NewThreadSpecial.poll);
      expect(decoded.poll, isNotNull);
      expect(decoded.poll!.options, ['A', 'B', 'C']);
      expect(decoded.poll!.multiple, isTrue);
      expect(decoded.poll!.maxChoices, 2);
      expect(decoded.poll!.expirationDays, 7);
      expect(decoded.poll!.overt, isTrue);
      expect(decoded.poll!.visibilityPoll, isTrue);
    });

    test('decode tolerates poll declared via special only', () {
      // 老版本 / 极端情况：用户切到投票还没填任何字段，flushDraft 时只
      // 写了 special=poll，没写 pollOptions。decode 仍然要给一个 poll 对象，
      // 让 UI 重启后保持在 poll 模式。
      final decoded = codec.decode(const <String, String>{'special': 'poll'});
      expect(decoded.special, NewThreadSpecial.poll);
      expect(decoded.poll, isNotNull);
      expect(decoded.poll!.options, isEmpty);
    });
  });
}
