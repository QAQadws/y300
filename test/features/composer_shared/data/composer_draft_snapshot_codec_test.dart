import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_snapshot_codec.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';

void main() {
  const codec = ComposerDraftSnapshotJsonCodec();

  group('ComposerDraftSnapshotJsonCodec', () {
    test('round-trips a thread reply draft (no subject / extras)', () {
      final snapshot = ComposerDraftSnapshot(
        identity: const ComposerDraftIdentity.thread(fid: '33', tid: '572063'),
        message: '回复正文',
        useSignature: false,
        updatedAt: DateTime.utc(2026, 6, 8, 9, 30),
      );

      final encoded = jsonEncode(codec.encode(snapshot));
      final decoded = codec.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.identity.kind, ComposerDraftKind.threadReply);
      expect(decoded.identity.fid, '33');
      expect(decoded.identity.tid, '572063');
      expect(decoded.identity.repquote, isNull);
      expect(decoded.message, '回复正文');
      expect(decoded.subject, isEmpty);
      expect(decoded.extras, isEmpty);
      expect(decoded.useSignature, isFalse);
    });

    test('round-trips a post reply draft', () {
      final snapshot = ComposerDraftSnapshot(
        identity: const ComposerDraftIdentity.post(
          fid: '33',
          tid: '572063',
          repquote: '41554317',
        ),
        message: '楼层回复',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 6, 8, 9, 30),
      );

      final encoded = jsonEncode(codec.encode(snapshot));
      final decoded = codec.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.identity.kind, ComposerDraftKind.postReply);
      expect(decoded.identity.repquote, '41554317');
      expect(decoded.message, '楼层回复');
    });

    test('round-trips a new thread draft with subject and extras', () {
      final snapshot = ComposerDraftSnapshot(
        identity: const ComposerDraftIdentity.newThread(fid: '33'),
        message: '正文',
        subject: '我的标题',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 6, 8, 9, 30),
        extras: const <String, String>{
          'typeid': '111',
          'allowNoticeAuthor': '1',
        },
      );

      final encoded = jsonEncode(codec.encode(snapshot));
      final decoded = codec.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.identity.kind, ComposerDraftKind.newThread);
      expect(decoded.identity.fid, '33');
      expect(decoded.identity.tid, isNull);
      expect(decoded.identity.repquote, isNull);
      expect(decoded.subject, '我的标题');
      expect(decoded.extras['typeid'], '111');
      expect(decoded.extras['allowNoticeAuthor'], '1');
    });

    test(
      'decodes legacy thread reply payload missing kind / subject / extras',
      () {
        final legacy = jsonEncode({
          'fid': '33',
          'tid': '572063',
          'repquote': null,
          'message': '老草稿',
          'useSignature': true,
          'updatedAt': '2026-06-08T09:30:00.000Z',
          'imageAttachments': <Object?>[],
        });

        final decoded = codec.decode(legacy);

        expect(decoded, isNotNull);
        expect(decoded!.identity.kind, ComposerDraftKind.threadReply);
        expect(decoded.identity.fid, '33');
        expect(decoded.identity.tid, '572063');
        expect(decoded.subject, isEmpty);
        expect(decoded.extras, isEmpty);
        expect(decoded.message, '老草稿');
      },
    );

    test('decodes legacy post reply payload by repquote presence', () {
      final legacy = jsonEncode({
        'fid': '33',
        'tid': '572063',
        'repquote': '41554317',
        'message': '老楼层草稿',
        'useSignature': false,
        'updatedAt': '2026-06-08T09:30:00.000Z',
      });

      final decoded = codec.decode(legacy);

      expect(decoded, isNotNull);
      expect(decoded!.identity.kind, ComposerDraftKind.postReply);
      expect(decoded.identity.repquote, '41554317');
      expect(decoded.message, '老楼层草稿');
    });

    test('discards entries with no fid / message / updatedAt', () {
      final missingFid = jsonEncode({
        'tid': '572063',
        'message': 'x',
        'updatedAt': '2026-06-08T09:30:00.000Z',
      });
      final missingMessage = jsonEncode({
        'fid': '33',
        'tid': '572063',
        'updatedAt': '2026-06-08T09:30:00.000Z',
      });
      final missingUpdatedAt = jsonEncode({
        'fid': '33',
        'tid': '572063',
        'message': 'x',
      });

      expect(codec.decode(missingFid), isNull);
      expect(codec.decode(missingMessage), isNull);
      expect(codec.decode(missingUpdatedAt), isNull);
    });

    test('falls back to safe defaults for malformed extras', () {
      final raw = jsonEncode({
        'kind': 'newThread',
        'fid': '33',
        'tid': null,
        'repquote': null,
        'message': '',
        'subject': '标题',
        'useSignature': true,
        'updatedAt': '2026-06-08T09:30:00.000Z',
        'extras': 'not-a-map',
      });

      final decoded = codec.decode(raw);

      expect(decoded, isNotNull);
      expect(decoded!.identity.kind, ComposerDraftKind.newThread);
      expect(decoded.subject, '标题');
      expect(decoded.extras, isEmpty);
    });

    test('round-trips image attachments', () {
      final snapshot = ComposerDraftSnapshot(
        identity: const ComposerDraftIdentity.newThread(fid: '33'),
        message: '正文',
        subject: '标题',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 6, 8),
        imageAttachments: [
          ComposerImageAttachment(
            localId: 'image-1',
            localPath: '/path/first.jpg',
            fileName: 'first.jpg',
            mimeType: 'image/jpeg',
            order: 0,
            status: ComposerImageAttachmentStatus.uploaded,
            aid: '123',
            uploadedAt: DateTime.utc(2026, 6, 8, 10),
          ),
        ],
      );

      final encoded = jsonEncode(codec.encode(snapshot));
      final decoded = codec.decode(encoded);

      expect(decoded?.imageAttachments, hasLength(1));
      expect(decoded?.imageAttachments.single.aid, '123');
      expect(
        decoded?.imageAttachments.single.status,
        ComposerImageAttachmentStatus.uploaded,
      );
    });

    test('writes a stable failure code through the legacy JSON key', () {
      final snapshot = ComposerDraftSnapshot(
        identity: const ComposerDraftIdentity.thread(fid: '33', tid: '572063'),
        message: '正文',
        useSignature: true,
        updatedAt: DateTime.utc(2026, 7, 28),
        imageAttachments: const [
          ComposerImageAttachment(
            localId: 'failed-1',
            localPath: '/path/failed.jpg',
            fileName: 'failed.jpg',
            mimeType: 'image/jpeg',
            order: 0,
            status: ComposerImageAttachmentStatus.failed,
            failureCode: ComposerImageUploadFailureCode.network,
          ),
        ],
      );

      final encoded = codec.encode(snapshot);
      final attachment =
          (encoded['imageAttachments']! as List).single as Map<String, Object?>;
      expect(attachment['errorMessage'], 'network');
      final decoded = codec.decode(jsonEncode(encoded));
      expect(
        decoded?.imageAttachments.single.failureCode,
        ComposerImageUploadFailureCode.network,
      );
    });

    test('maps a legacy free-text attachment error to unknown', () {
      final raw = jsonEncode({
        'kind': 'threadReply',
        'fid': '33',
        'tid': '572063',
        'message': '正文',
        'useSignature': true,
        'updatedAt': '2026-07-28T00:00:00.000Z',
        'imageAttachments': [
          {
            'localId': 'legacy-1',
            'localPath': '/path/legacy.jpg',
            'fileName': 'legacy.jpg',
            'mimeType': 'image/jpeg',
            'order': 0,
            'status': 'failed',
            'errorMessage': '服务器返回的旧错误 Cookie=secret',
          },
        ],
      });

      final decoded = codec.decode(raw);
      expect(
        decoded?.imageAttachments.single.failureCode,
        ComposerImageUploadFailureCode.unknown,
      );
    });
  });
}
