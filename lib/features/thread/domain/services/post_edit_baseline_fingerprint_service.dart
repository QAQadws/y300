import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final postEditBaselineFingerprintServiceProvider =
    Provider<PostEditBaselineFingerprintService>((ref) {
      return const PostEditBaselineFingerprintService();
    });

class PostEditBaselineFingerprintService {
  const PostEditBaselineFingerprintService();

  String fingerprint({
    required PostEditTarget target,
    required String rawMessage,
    required String originalSubject,
    required List<PostEditFormField> successfulControls,
    required List<PostEditExistingImage> existingImages,
    List<PostEditRegularAttachment> regularAttachments =
        const <PostEditRegularAttachment>[],
  }) {
    final stableControls = successfulControls
        .where((field) => !_volatileNames.contains(field.name.toLowerCase()))
        .map(
          (field) => <String, String>{
            'name': field.name,
            'value': _normalizeText(field.value),
            'kind': field.controlKind.name,
          },
        )
        .toList(growable: false);
    final payload = <String, Object?>{
      'target': <String, Object?>{
        'fid': target.fid,
        'tid': target.tid,
        'pid': target.pid,
      },
      'message': _normalizeText(rawMessage),
      'subject': _normalizeText(originalSubject),
      'controls': stableControls,
      'images': existingImages
          .map(
            (image) => <String, Object?>{
              'aid': image.aid,
              'url': image.imageUri.toString(),
              'associated': image.isAssociated,
              'description': image.description,
              'fileName': image.fileName,
            },
          )
          .toList(growable: false),
      'regularAttachments': regularAttachments
          .map(
            (attachment) => <String, Object?>{
              'aid': attachment.aid,
              'fileName': attachment.fileName,
            },
          )
          .toList(growable: false),
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  String _normalizeText(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static const Set<String> _volatileNames = <String>{
    'formhash',
    'posttime',
    'editsubmit',
    'handlekey',
    'inajax',
    'geoloc',
  };
}
