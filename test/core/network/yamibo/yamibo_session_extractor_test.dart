import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo_session_extractor.dart';

void main() {
  group('YamiboSessionExtractor', () {
    final now = DateTime(2026, 6, 19, 12);
    late YamiboSessionExtractor extractor;

    setUp(() {
      extractor = YamiboSessionExtractor(now: () => now);
    });

    test('extracts session snapshot from API variables', () {
      final snapshot = extractor.extractFromApiVariables(<String, dynamic>{
        'member_uid': '597454',
        'member_username': 'tester',
        'formhash': 'fh_api',
        'auth': 'token',
      }, source: 'api:profile');

      expect(snapshot, isNotNull);
      expect(snapshot!.isLoggedIn, isTrue);
      expect(snapshot.uid, '597454');
      expect(snapshot.username, 'tester');
      expect(snapshot.formhash, 'fh_api');
      expect(snapshot.updatedAt, now);
      expect(snapshot.source, 'api:profile');
    });

    test('extracts formhash and uid from mobile HTML', () {
      final snapshot = extractor.extractFromHtml('''
<html>
<body>
  <form><input type="hidden" name="formhash" value="fh_html"></form>
  <script>var discuz_uid = '597454', SITEURL = 'https://bbs.yamibo.com/';</script>
</body>
</html>
''', source: 'html:forum.home.html');

      expect(snapshot, isNotNull);
      expect(snapshot!.isLoggedIn, isTrue);
      expect(snapshot.uid, '597454');
      expect(snapshot.formhash, 'fh_html');
      expect(snapshot.source, 'html:forum.home.html');
    });

    test('returns null when no session fields are present', () {
      final snapshot = extractor.extractFromHtml(
        '<html><body><p>plain page</p></body></html>',
        source: 'html:plain',
      );

      expect(snapshot, isNull);
    });
  });
}
