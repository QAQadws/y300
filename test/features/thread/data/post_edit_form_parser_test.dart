import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/services/post_edit_form_parser.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

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

  test('parses the fixture form, controls and existing image metadata', () {
    final result = const PostEditFormParser().parse(
      _readFixture(),
      target: target,
    );

    expect(result.isSuccess, isTrue);
    final snapshot = result.snapshot!;
    expect(snapshot.formHash, 'fixture-formhash');
    expect(snapshot.postTime, '1700000000');
    expect(snapshot.rawMessage, contains('[attachimg]1624572[/attachimg]'));
    expect(
      snapshot.successfulControls.map((field) => field.name),
      contains('usesig'),
    );
    expect(
      snapshot.successfulControls.map((field) => field.name),
      isNot(contains('htmlon')),
    );
    expect(snapshot.existingImages, hasLength(1));
    expect(snapshot.existingImages.single.aid, '1624572');
    expect(snapshot.existingImages.single.isAssociated, isTrue);
    expect(
      snapshot.existingImages.single.imageUri,
      Uri.parse(
        'https://bbs.yamibo.com/data/attachment/forum/fixture/existing-image.jpg',
      ),
    );
    expect(snapshot.regularAttachments, isEmpty);
  });

  test(
    'rejects missing, duplicate, malformed and mismatched form contracts',
    () {
      final parser = const PostEditFormParser();
      expect(
        parser
            .parse('<html><body>nothing</body></html>', target: target)
            .failure,
        PostEditFormParseFailureReason.missingForm,
      );
      expect(
        parser.parse('<html><body>请先登录</body></html>', target: target).failure,
        PostEditFormParseFailureReason.authenticationRequired,
      );
      expect(
        parser
            .parse('<html><body>没有权限访问</body></html>', target: target)
            .failure,
        PostEditFormParseFailureReason.permissionDenied,
      );
      expect(
        parser
            .parse('<html><body>该帖子不存在或已删除</body></html>', target: target)
            .failure,
        PostEditFormParseFailureReason.postDeleted,
      );
      expect(
        parser
            .parse(
              _readFixture().replaceFirst(
                'action="forum.php?mod=post&amp;action=edit',
                'action="forum.php?mod=post&amp;action=reply',
              ),
              target: target,
            )
            .failure,
        PostEditFormParseFailureReason.invalidSubmitAction,
      );
      expect(
        parser
            .parse(
              _readFixture().replaceFirst(
                'name="tid" value="557857"',
                'name="tid" value="1"',
              ),
              target: target,
            )
            .failure,
        PostEditFormParseFailureReason.targetMismatch,
      );
      expect(
        parser
            .parse(
              _readFixture().replaceFirst(
                '</form>',
                '<input type="hidden" name="pid" value="41587383"></form>',
              ),
              target: target,
            )
            .failure,
        PostEditFormParseFailureReason.duplicateCriticalControl,
      );
    },
  );

  test('detects regular attachment and external form-owner controls', () {
    final html = _readFixture()
        .replaceFirst(
          '</form>',
          '</form><input form="postform" name="external" value="1">',
        )
        .replaceFirst(
          '<ul id="attlist" class="post_attlist setbox cl"></ul>',
          '<ul id="attlist" class="post_attlist setbox cl"><li aid="99">file.zip</li></ul>',
        );
    final result = const PostEditFormParser().parse(html, target: target);

    expect(result.isSuccess, isTrue);
    expect(result.snapshot!.structureEvidence.hasRegularAttachments, isTrue);
    expect(
      result.snapshot!.structureEvidence.hasExternalFormOwnerControls,
      isTrue,
    );
    expect(result.snapshot!.regularAttachments.single.aid, '99');
  });

  test('keeps image DOM order, descriptions and association state', () {
    final html = _readFixture().replaceFirst(
      RegExp(r'</ul>\s*<ul id="attlist"'),
      '''<li>
          <span aid="1624573" class="del"><a href="javascript:;">删除</a></span>
          <span class="p_img"><img src="/data/attachment/forum/second.png" alt="second.png"></span>
          <input type="hidden" name="attachnew[1624573][description]" value="second description">
        </li>
      </ul>
      <ul id="attlist"''',
    );
    final result = const PostEditFormParser().parse(html, target: target);

    expect(result.isSuccess, isTrue);
    final images = result.snapshot!.existingImages;
    expect(images.map((image) => image.aid), ['1624572', '1624573']);
    expect(images[0].isAssociated, isTrue);
    expect(images[1].isAssociated, isFalse);
    expect(images[1].description, 'second description');
    expect(
      images[1].imageUri,
      Uri.parse('https://bbs.yamibo.com/data/attachment/forum/second.png'),
    );
  });

  test('fails closed for duplicate or unsafe image metadata', () {
    final duplicate = _readFixture().replaceFirst(
      RegExp(r'</ul>\s*<ul id="attlist"'),
      '<li><span aid="1624572"><img src="/duplicate.jpg"></span></li></ul><ul id="attlist"',
    );
    expect(
      const PostEditFormParser().parse(duplicate, target: target).failure,
      PostEditFormParseFailureReason.malformedAttachment,
    );

    final unsafe = _readFixture().replaceFirst(
      'src="data/attachment/forum/fixture/existing-image.jpg"',
      'src="javascript:alert(1)"',
    );
    expect(
      const PostEditFormParser().parse(unsafe, target: target).failure,
      PostEditFormParseFailureReason.malformedAttachment,
    );
  });
}

String _readFixture() {
  return File(_fixturePath).readAsStringSync(encoding: utf8);
}
