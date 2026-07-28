import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_manual_episode_url_policy.dart';

void main() {
  const policy = ComicManualEpisodeUrlPolicy();

  test('extracts the same tid from supported Yamibo URL shapes', () {
    const inputs = <String>[
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573440&page=1&mobile=2',
      'https://bbs.yamibo.com/thread-573440-1-1.html',
      'https://bbs.yamibo.com/api/mobile/index.php?module=viewthread&tid=573440&page=1&version=4',
    ];

    for (final input in inputs) {
      final target = policy.parse(input);
      expect(target.tid, '573440');
      expect(
        target.sourceUrl,
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573440',
      );
    }
  });

  test('accepts a bare positive tid', () {
    final target = policy.parse('573440');

    expect(target.tid, '573440');
    expect(target.sourceUrl, contains('tid=573440'));
  });

  test('rejects invalid or untrusted inputs with stable codes', () {
    const invalid = <String, ComicManualEpisodeInputErrorCode>{
      '': ComicManualEpisodeInputErrorCode.emptyInput,
      '0': ComicManualEpisodeInputErrorCode.unsupportedThreadUrl,
      '-1': ComicManualEpisodeInputErrorCode.unsupportedThreadUrl,
      'abc': ComicManualEpisodeInputErrorCode.unsupportedThreadUrl,
      'https://example.com/forum.php?mod=viewthread&tid=573440':
          ComicManualEpisodeInputErrorCode.unexpectedHost,
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&tid=573440':
          ComicManualEpisodeInputErrorCode.unsupportedThreadUrl,
      'https://bbs.yamibo.com/api/mobile/index.php?module=login&tid=573440':
          ComicManualEpisodeInputErrorCode.unsupportedThreadUrl,
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=0':
          ComicManualEpisodeInputErrorCode.missingTid,
    };

    for (final entry in invalid.entries) {
      expect(
        () => policy.parse(entry.key),
        throwsA(
          isA<ComicManualEpisodeInputException>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
        reason: entry.key,
      );
    }
  });
}
