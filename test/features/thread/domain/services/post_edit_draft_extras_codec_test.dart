import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_draft_extras_codec.dart';

void main() {
  const codec = PostEditDraftExtrasCodec();

  test('round trips sorted positive tombstones', () {
    final extras = codec.encode(
      baselineFingerprint: 'baseline',
      deletedAidTombstones: const ['20', '3', 'invalid', '3', '0'],
    );

    expect(extras['baselineFingerprint'], 'baseline');
    expect(codec.deletedAidTombstones(extras), {'3', '20'});
  });

  test('keeps old edit extras compatible', () {
    expect(
      codec.deletedAidTombstones(const {'baselineFingerprint': 'old'}),
      isEmpty,
    );
    expect(
      codec.deletedAidTombstones(const {
        'deletedAidTombstones': '["bad", 1, "0"]',
      }),
      isEmpty,
    );
  });

  test('tombstone-only edit drafts are not treated as empty', () {
    final draft = ComposerDraftSnapshot(
      identity: const ComposerDraftIdentity.postEdit(
        fid: '5',
        tid: '20',
        pid: '30',
      ),
      message: '',
      useSignature: true,
      updatedAt: DateTime.utc(2026, 8, 1),
      extras: codec.encode(
        baselineFingerprint: 'baseline',
        deletedAidTombstones: const ['12'],
      ),
    );

    expect(draft.isEmpty, isFalse);
  });
}
