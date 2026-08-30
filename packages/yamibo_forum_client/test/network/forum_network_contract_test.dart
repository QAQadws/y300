import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  test(
    'request cancellation is observable and transport request retains context',
    () {
      final cancellation = ForumRequestCancellation();
      final request = ForumRequest(
        method: ForumRequestMethod.post,
        uri: Uri.parse('https://bbs.yamibo.com/search.php'),
        context: const ForumRequestContext(
          operation: 'search',
          module: 'forum',
        ),
        cancellation: cancellation,
      );
      expect(request.context.operation, 'search');
      expect(cancellation.isCancelled, isFalse);
      cancellation.cancel();
      expect(cancellation.isCancelled, isTrue);
    },
  );

  test(
    'source plan facade returns unsupported instead of empty success',
    () async {
      final client = YamiboForumClient(
        config: ForumClientConfig(
          siteOrigin: Uri.parse('https://bbs.yamibo.com'),
        ),
        network: _UnusedNetwork(),
      );
      final result = await client.unsupported<Object, Object>();
      expect(result, isA<DataReadFailure<Object, Object>>());
      expect(result.failureOrNull!.kind, DataReadFailureKind.unsupported);
    },
  );

  test('cookie store applies Set-Cookie deletion semantics', () async {
    final store = MemoryForumCookieStore();
    final uri = Uri.parse('https://bbs.yamibo.com/');
    await store.merge(uri, <String, String>{'sid': 'abc', 'keep': 'yes'});
    await store.mergeSetCookie(uri, <String>['sid=deleted; Max-Age=0']);
    expect(await store.read(uri), <String, String>{'keep': 'yes'});
  });

  test('ordered form fields preserve duplicate names', () {
    final fields = ForumFormFields(const <MapEntry<String, String>>[
      MapEntry<String, String>('pollanswers[]', '7'),
      MapEntry<String, String>('pollanswers[]', '9'),
    ]);

    expect(fields.encode(), 'pollanswers%5B%5D=7&pollanswers%5B%5D=9');
  });
}

final class _UnusedNetwork implements ForumClientNetwork {
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async => const ForumTransportError(
    ForumTransportFailure(
      kind: ForumTransportFailureKind.unknown,
      code: 'unused',
    ),
  );
}
