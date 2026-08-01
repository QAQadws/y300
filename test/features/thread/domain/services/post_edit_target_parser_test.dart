import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_target_parser.dart';

void main() {
  const parser = PostEditTargetParser();

  test('accepts a same-origin forum.php post edit target', () {
    final result = parser.parse(
      rawUrl:
          'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=557857&pid=41587383&page=215&mobile=2',
      currentFid: '5',
      currentTid: '557857',
      currentPid: '41587383',
      currentPage: 1,
      isFirstPost: false,
    );

    expect(result.isSuccess, isTrue);
    expect(result.target, isNotNull);
    expect(result.target!.page, 215);
    expect(result.target!.editUri.queryParameters['mobile'], '2');
  });

  test('accepts HTML encoded query separators', () {
    final result = parser.parse(
      rawUrl:
          'https://bbs.yamibo.com/forum.php?mod=post&amp;action=edit&amp;fid=5&amp;tid=10&amp;pid=11',
      currentFid: '5',
      currentTid: '10',
      currentPid: '11',
    );

    expect(result.isSuccess, isTrue);
  });

  test('fails closed for external, wrong path, wrong action and duplicates', () {
    final cases = <String, PostEditTargetParseFailure>{
      'https://example.com/forum.php?mod=post&action=edit&fid=5&tid=10&pid=11':
          PostEditTargetParseFailure.externalSite,
      'https://bbs.yamibo.com/index.php?mod=post&action=edit&fid=5&tid=10&pid=11':
          PostEditTargetParseFailure.invalidPath,
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=5&tid=10&pid=11':
          PostEditTargetParseFailure.invalidAction,
      'https://bbs.yamibo.com/forum.php?mod=post&mod=post&action=edit&fid=5&tid=10&pid=11':
          PostEditTargetParseFailure.invalidModule,
    };

    for (final entry in cases.entries) {
      final result = parser.parse(
        rawUrl: entry.key,
        currentFid: '5',
        currentTid: '10',
        currentPid: '11',
      );
      expect(result.failure, entry.value, reason: entry.key);
    }
  });

  test('requires positive identifiers and current tid/pid/fid', () {
    final invalidValues = <String>['0', '-1', 'abc', ''];
    for (final value in invalidValues) {
      final result = parser.parse(
        rawUrl:
            'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=$value&tid=10&pid=11',
        currentFid: '5',
        currentTid: '10',
        currentPid: '11',
      );
      expect(result.isSuccess, isFalse, reason: value);
    }

    final mismatch = parser.parse(
      rawUrl:
          'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=10&pid=11',
      currentFid: '6',
      currentTid: '10',
      currentPid: '11',
    );
    expect(mismatch.failure, PostEditTargetParseFailure.targetMismatch);
  });

  test('rejects duplicate critical query parameters and user info', () {
    final duplicate = parser.parse(
      rawUrl:
          'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=10&pid=11&pid=11',
      currentFid: '5',
      currentTid: '10',
      currentPid: '11',
    );
    expect(duplicate.failure, PostEditTargetParseFailure.invalidIdentifier);

    final userInfo = parser.parse(
      rawUrl:
          'https://user:pass@bbs.yamibo.com/forum.php?mod=post&action=edit&fid=5&tid=10&pid=11',
      currentFid: '5',
      currentTid: '10',
      currentPid: '11',
    );
    expect(userInfo.failure, PostEditTargetParseFailure.userInfoNotAllowed);
  });
}
