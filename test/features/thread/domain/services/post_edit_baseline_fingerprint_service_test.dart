import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/services/post_edit_form_parser.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_baseline_fingerprint_service.dart';

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

  test('excludes volatile controls while retaining stable form content', () {
    final snapshot = const PostEditFormParser()
        .parse(_readFixture(), target: target)
        .snapshot!;
    const service = PostEditBaselineFingerprintService();

    final volatileChanged = service.fingerprint(
      target: target,
      rawMessage: snapshot.rawMessage,
      originalSubject: snapshot.originalSubject,
      successfulControls: snapshot.successfulControls
          .map(
            (field) => PostEditFormField(
              name: field.name,
              value: field.name == 'formhash'
                  ? 'new-hash'
                  : field.name == 'posttime'
                  ? '9999999999'
                  : field.value,
              controlKind: field.controlKind,
            ),
          )
          .toList(),
      existingImages: snapshot.existingImages,
    );

    expect(volatileChanged, snapshot.baselineFingerprint);
  });

  test('changes for message, image URL, aid and association changes', () {
    final snapshot = const PostEditFormParser()
        .parse(_readFixture(), target: target)
        .snapshot!;
    const service = PostEditBaselineFingerprintService();
    String fingerprint({String? message, List<PostEditExistingImage>? images}) {
      return service.fingerprint(
        target: target,
        rawMessage: message ?? snapshot.rawMessage,
        originalSubject: snapshot.originalSubject,
        successfulControls: snapshot.successfulControls,
        existingImages: images ?? snapshot.existingImages,
      );
    }

    expect(
      fingerprint(message: 'changed'),
      isNot(snapshot.baselineFingerprint),
    );
    expect(
      fingerprint(
        images: [
          PostEditExistingImage(
            aid: '1624572',
            imageUri: Uri.parse('https://bbs.yamibo.com/changed.jpg'),
            isAssociated: true,
          ),
        ],
      ),
      isNot(snapshot.baselineFingerprint),
    );
    expect(
      fingerprint(
        images: [
          PostEditExistingImage(
            aid: '999',
            imageUri: snapshot.existingImages.single.imageUri,
            isAssociated: true,
          ),
        ],
      ),
      isNot(snapshot.baselineFingerprint),
    );
    expect(
      fingerprint(
        images: [
          PostEditExistingImage(
            aid: '1624572',
            imageUri: snapshot.existingImages.single.imageUri,
            isAssociated: false,
          ),
        ],
      ),
      isNot(snapshot.baselineFingerprint),
    );
  });
}

String _readFixture() {
  return File(_fixturePath).readAsStringSync(encoding: utf8);
}
