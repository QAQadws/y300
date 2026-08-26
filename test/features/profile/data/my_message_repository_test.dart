import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart' as forum;
import 'package:y300/features/profile/data/repositories/my_message_repository.dart';

void main() {
  test('package-backed repository loads notifications and messages', () async {
    final network = _MessageNetwork();
    final client = forum.YamiboForumClientBuilder(
      config: forum.ForumClientConfig(
        siteOrigin: Uri.parse('https://bbs.yamibo.com'),
        apiOrigin: Uri.parse('https://api.yamibo.com/mobile/index.php'),
      ),
      network: network,
    ).buildStandardClient();
    final repository = PackageMyMessageRepository(client);

    final result = await repository.getMessageCenter();

    expect(result.isSuccess, isTrue);
    expect(network.modules, ['mynotelist', 'mypm']);
    final data = result.dataOrNull!;
    expect(data.notifications.items.single.id, 'notice-1');
    expect(data.notifications.items.single.author, 'Alice');
    expect(data.privateMessages.items.single.pmid, 'pm-1');
    expect(data.privateMessages.items.single.fromName, 'Bob');
  });
}

final class _MessageNetwork implements forum.ForumClientNetwork {
  final modules = <String>[];

  @override
  Future<forum.ForumTransportResult<forum.ForumResponse<Object?>>> send(
    forum.ForumRequest request,
  ) async {
    final module = request.uri.queryParameters['module'] ?? '';
    modules.add(module);
    final variables = switch (module) {
      'mynotelist' => <String, Object?>{
        'count': '1',
        'page': '1',
        'perpage': '20',
        'list': <Object?>[
          <String, Object?>{
            'id': 'notice-1',
            'type': 'post',
            'new': '1',
            'authorid': '10',
            'author': 'Alice',
            'note': '<a href="thread-1-1-1.html">reply</a>',
            'dateline': '1767225600',
          },
        ],
      },
      'mypm' => <String, Object?>{
        'count': '1',
        'page': '1',
        'perpage': '20',
        'list': <Object?>[
          <String, Object?>{
            'pmid': 'pm-1',
            'plid': 'conversation-1',
            'isnew': '1',
            'subject': 'Hello',
            'msgfromid': '11',
            'msgfrom': 'Bob',
            'touid': '12',
            'tousername': 'Carol',
            'message': 'preview',
            'vdateline': '2026-01-01 12:00',
          },
        ],
      },
      _ => <String, Object?>{'list': <Object?>[]},
    };
    return forum.ForumTransportSuccess(
      forum.ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: <String, Object?>{
          'Version': '4',
          'Charset': 'utf-8',
          'Variables': variables,
        },
      ),
    );
  }
}
