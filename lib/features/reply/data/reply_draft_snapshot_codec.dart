import 'dart:convert';

import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplyDraftSnapshotJsonCodec {
  const ReplyDraftSnapshotJsonCodec();

  Map<String, Object?> encode(ReplyDraftSnapshot snapshot) {
    return <String, Object?>{
      'fid': snapshot.identity.fid,
      'tid': snapshot.identity.tid,
      'repquote': snapshot.identity.repquote,
      'message': snapshot.message,
      'useSignature': snapshot.useSignature,
      'updatedAt': snapshot.updatedAt.toIso8601String(),
      'imageAttachments': [
        for (final attachment in snapshot.imageAttachments)
          _encodeAttachment(attachment),
      ],
    };
  }

  ReplyDraftSnapshot? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final fid = _stringValue(decoded['fid']);
      final tid = _stringValue(decoded['tid']);
      final message = _stringValue(decoded['message']);
      final updatedAtRaw = _stringValue(decoded['updatedAt']);
      if (fid == null ||
          fid.trim().isEmpty ||
          tid == null ||
          tid.trim().isEmpty ||
          message == null ||
          updatedAtRaw == null) {
        return null;
      }

      final repquote = _stringValue(decoded['repquote']);
      final updatedAt = DateTime.tryParse(updatedAtRaw);
      if (updatedAt == null) {
        return null;
      }
      final identity = repquote == null || repquote.trim().isEmpty
          ? ReplyDraftIdentity.thread(fid: fid, tid: tid)
          : ReplyDraftIdentity.post(
              fid: fid,
              tid: tid,
              repquote: repquote,
            );
      return ReplyDraftSnapshot(
        identity: identity,
        message: message,
        useSignature: decoded['useSignature'] is bool
            ? decoded['useSignature'] as bool
            : true,
        updatedAt: updatedAt,
        imageAttachments: _decodeAttachments(decoded['imageAttachments']),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _encodeAttachment(
    ReplyImageAttachment attachment,
  ) {
    return <String, Object?>{
      'localId': attachment.localId,
      'localPath': attachment.localPath,
      'fileName': attachment.fileName,
      'mimeType': attachment.mimeType,
      'order': attachment.order,
      'status': attachment.status.name,
      'aid': attachment.aid,
      'uploadedAt': attachment.uploadedAt?.toIso8601String(),
      'errorMessage': attachment.errorMessage,
      'cachePath': attachment.cachePath,
    };
  }

  List<ReplyImageAttachment> _decodeAttachments(Object? raw) {
    if (raw is! List) {
      return const <ReplyImageAttachment>[];
    }
    return [
      for (final item in raw)
        ?_decodeAttachment(item),
    ];
  }

  ReplyImageAttachment? _decodeAttachment(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final localId = _stringValue(raw['localId']);
    final localPath = _stringValue(raw['localPath']);
    final fileName = _stringValue(raw['fileName']);
    final mimeType = _stringValue(raw['mimeType']);
    final order = _intValue(raw['order']);
    final statusRaw = _stringValue(raw['status']);
    final status = _decodeStatus(statusRaw);
    if (localId == null ||
        localPath == null ||
        fileName == null ||
        mimeType == null ||
        order == null ||
        status == null) {
      return null;
    }

    final uploadedAtRaw = _stringValue(raw['uploadedAt']);
    final uploadedAt = uploadedAtRaw == null
        ? null
        : DateTime.tryParse(uploadedAtRaw);
    if (uploadedAtRaw != null && uploadedAt == null) {
      return null;
    }

    return ReplyImageAttachment(
      localId: localId,
      localPath: localPath,
      fileName: fileName,
      mimeType: mimeType,
      order: order,
      status: status,
      aid: _stringValue(raw['aid']),
      uploadedAt: uploadedAt,
      errorMessage: _stringValue(raw['errorMessage']),
      cachePath: _stringValue(raw['cachePath']),
    );
  }

  ReplyImageAttachmentStatus? _decodeStatus(String? raw) {
    if (raw == null) {
      return null;
    }
    for (final status in ReplyImageAttachmentStatus.values) {
      if (status.name == raw) {
        return status;
      }
    }
    return null;
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  String? _stringValue(Object? value) {
    if (value is String) {
      return value;
    }
    return null;
  }
}
