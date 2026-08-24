import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/data/services/y300_forum_resource_file_service.dart';

void main() {
  final siteOrigin = Uri.parse('https://bbs.yamibo.com');

  test(
    'maps cache metadata and only accepts referer plus ETag input',
    () async {
      final client = _RecordingResourceClient(
        response: ForumResourceSuccess(
          uri: Uri.parse('https://bbs.yamibo.com/image.jpg'),
          statusCode: 200,
          content: Stream<List<int>>.value(const <int>[1, 2, 3]),
          contentLength: 3,
          contentType: 'image/jpeg',
          eTag: 'fresh-etag',
          validUntil: DateTime.utc(2026, 8, 25),
          fileExtension: '.jpg',
        ),
      );
      final service = Y300ForumResourceFileService(
        client: client,
        siteOrigin: siteOrigin,
      );

      final response = await service.get(
        '/image.jpg',
        headers: const <String, String>{
          'Referer':
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573279',
          'If-None-Match': 'old-etag',
          'Cookie': 'must-not-cross-the-boundary',
          'User-Agent': 'must-not-cross-the-boundary',
        },
      );

      expect(await response.content.expand((chunk) => chunk).toList(), <int>[
        1,
        2,
        3,
      ]);
      expect(response.statusCode, 200);
      expect(response.contentLength, 3);
      expect(response.eTag, 'fresh-etag');
      expect(response.validTill, DateTime.utc(2026, 8, 25));
      expect(response.fileExtension, '.jpg');
      expect(client.lastRequest?.ifNoneMatch, 'old-etag');
      expect(
        client.lastRequest?.reference.referer.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573279',
      );
    },
  );

  test('maps structured resource failures without exposing payloads', () async {
    final client = _RecordingResourceClient(
      response: const ForumResourceError(
        ForumResourceFailure(
          kind: ForumResourceFailureKind.invalidContent,
          code: 'resource_is_not_image',
          statusCode: 200,
        ),
      ),
    );
    final service = Y300ForumResourceFileService(
      client: client,
      siteOrigin: siteOrigin,
    );

    expect(
      () => service.get('/challenge.html'),
      throwsA(
        isA<ForumResourceFileServiceException>().having(
          (error) => error.failure.kind,
          'failure kind',
          ForumResourceFailureKind.invalidContent,
        ),
      ),
    );
  });

  test(
    'rejects invalid references before invoking the resource client',
    () async {
      final client = _RecordingResourceClient(
        response: const ForumResourceError(
          ForumResourceFailure(
            kind: ForumResourceFailureKind.unknown,
            code: 'unexpected',
          ),
        ),
      );
      final service = Y300ForumResourceFileService(
        client: client,
        siteOrigin: siteOrigin,
      );

      expect(
        () => service.get('file:///private/image.jpg'),
        throwsA(isA<ForumResourceFileServiceException>()),
      );
      expect(client.callCount, 0);
    },
  );
}

final class _RecordingResourceClient implements ForumResourceClient {
  _RecordingResourceClient({required this.response});

  final ForumResourceResult response;
  ForumResourceRequest? lastRequest;
  int callCount = 0;

  @override
  Future<ForumResourceResult> open(ForumResourceRequest request) async {
    callCount += 1;
    lastRequest = request;
    return response;
  }
}
