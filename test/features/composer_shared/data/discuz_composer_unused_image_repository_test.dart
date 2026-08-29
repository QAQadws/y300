import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/composer_shared/data/repositories/discuz_composer_unused_image_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_unused_image_remote_data_source.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';

void main() {
  late _FakeRemoteDataSource remote;
  late YamiboSessionStore sessionStore;

  setUp(() {
    remote = _FakeRemoteDataSource();
    sessionStore = YamiboSessionStore()
      ..saveExtracted(
        YamiboSessionSnapshot(
          isLoggedIn: true,
          uid: '100',
          username: 'tester',
          formhash: 'session-hash',
          updatedAt: DateTime.utc(2026, 8, 3),
          source: 'test',
        ),
      );
  });

  test('loads the full unused-image catalog with posttime zero', () async {
    remote.loadBody = '<root><![CDATA[${_catalogCell('12')}]]></root>';
    final repository = _repository(remote: remote, sessionStore: sessionStore);

    final result = await repository.loadUnusedImages();

    expect(result.dataOrNull?.single.aid, '12');
    final uri = remote.loadedUris.single;
    expect(uri.host, 'bbs.yamibo.com');
    expect(uri.path, '/forum.php');
    expect(uri.queryParameters['mod'], 'ajax');
    expect(uri.queryParameters['action'], 'imagelist');
    expect(uri.queryParameters['posttime'], '0');
  });

  test('does not accept an empty catalog without confirmed login', () async {
    sessionStore.clear();
    remote.loadBody = '<root><![CDATA[]]></root>';
    final result = await _repository(
      remote: remote,
      sessionStore: sessionStore,
    ).loadUnusedImages();

    expect(result, isA<ApiFailure<List<ComposerUnusedImage>>>());
  });

  test(
    'does not treat a login flag without a positive uid as confirmed',
    () async {
      sessionStore.clear();
      sessionStore.saveExtracted(
        YamiboSessionSnapshot(
          isLoggedIn: true,
          uid: '',
          username: 'tester',
          formhash: 'hash',
          updatedAt: DateTime.utc(2026, 8, 3),
          source: 'test',
        ),
      );
      remote.loadBody = '<root><![CDATA[]]></root>';

      final result = await _repository(
        remote: remote,
        sessionStore: sessionStore,
      ).loadUnusedImages();

      expect(result, isA<ApiFailure<List<ComposerUnusedImage>>>());
    },
  );

  test('deletes one aid with current formhash and fixed unused ids', () async {
    remote.deleteBody = '<root><![CDATA[1]]></root>';
    final repository = _repository(
      remote: remote,
      sessionStore: sessionStore,
      formhash: 'fresh-secret',
    );

    final result = await repository.deleteUnusedImage('12');

    expect(result.dataOrNull?.deleted, isTrue);
    final uri = remote.deletedUris.single;
    expect(uri.queryParameters['action'], 'deleteattach');
    expect(uri.queryParameters['formhash'], 'fresh-secret');
    expect(uri.queryParameters['tid'], '0');
    expect(uri.queryParameters['pid'], '0');
    expect(uri.queryParameters['aids[]'], '12');
  });

  test('treats zero and non-numeric delete responses as failures', () async {
    final repository = _repository(remote: remote, sessionStore: sessionStore);

    remote.deleteBody = '<root><![CDATA[0]]></root>';
    final zero = await repository.deleteUnusedImage('12');
    expect(
      zero.dataOrNull?.outcome,
      ComposerUnusedImageDeleteOutcome.notDeleted,
    );

    remote.deleteBody = '<root><![CDATA[permission denied]]></root>';
    final unknown = await repository.deleteUnusedImage('12');
    expect(
      unknown.dataOrNull?.outcome,
      ComposerUnusedImageDeleteOutcome.unconfirmed,
    );
  });

  test('rejects a redirected deletion response', () async {
    remote.deleteBody = '<root><![CDATA[1]]></root>';
    remote.deleteSourceUri = Uri.parse(
      'https://bbs.yamibo.com/member.php?mod=logging',
    );

    final result = await _repository(
      remote: remote,
      sessionStore: sessionStore,
    ).deleteUnusedImage('12');

    expect(result, isA<ApiFailure<ComposerUnusedImageDeleteResult>>());
  });

  test(
    'rejects invalid aid before loading formhash or issuing a request',
    () async {
      var formhashLoads = 0;
      final repository = DiscuzComposerUnusedImageRepository(
        remoteDataSource: remote,
        sessionStore: sessionStore,
        formhashProvider: _FakeForumFormhashProvider(
          value: 'hash',
          onLoad: () => formhashLoads += 1,
        ),
      );

      final result = await repository.deleteUnusedImage('0');

      expect(result, isA<ApiFailure<ComposerUnusedImageDeleteResult>>());
      expect(formhashLoads, 0);
      expect(remote.deletedUris, isEmpty);
    },
  );
}

DiscuzComposerUnusedImageRepository _repository({
  required _FakeRemoteDataSource remote,
  required YamiboSessionStore sessionStore,
  String formhash = 'hash',
}) {
  return DiscuzComposerUnusedImageRepository(
    remoteDataSource: remote,
    sessionStore: sessionStore,
    formhashProvider: _FakeForumFormhashProvider(value: formhash),
  );
}

final class _FakeForumFormhashProvider implements ForumFormhashProvider {
  const _FakeForumFormhashProvider({required this.value, this.onLoad});

  final String value;
  final void Function()? onLoad;

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async {
    onLoad?.call();
    return ForumFormhashSuccess(value);
  }
}

String _catalogCell(String aid) {
  return '''
<table class="imgl"><tr><td id="image_td_$aid">
  <a id="imageattach$aid" title="image.jpg">
    <img id="image_$aid" src="forum.php?mod=image&amp;aid=$aid&amp;size=300x300&amp;key=x" />
  </a>
  <input name="attachnew[$aid][description]" value="" />
</td></tr></table>
''';
}

final class _FakeRemoteDataSource
    implements ComposerUnusedImageRemoteDataSource {
  String loadBody = '<root><![CDATA[]]></root>';
  String deleteBody = '<root><![CDATA[0]]></root>';
  Uri? deleteSourceUri;
  final List<Uri> loadedUris = <Uri>[];
  final List<Uri> deletedUris = <Uri>[];

  @override
  Future<ApiResult<ComposerUnusedImageRemoteDocument>> load(Uri uri) async {
    loadedUris.add(uri);
    return ApiSuccess(
      ComposerUnusedImageRemoteDocument(sourceUri: uri, body: loadBody),
    );
  }

  @override
  Future<ApiResult<ComposerUnusedImageRemoteDocument>> delete(Uri uri) async {
    deletedUris.add(uri);
    return ApiSuccess(
      ComposerUnusedImageRemoteDocument(
        sourceUri: deleteSourceUri ?? uri,
        body: deleteBody,
      ),
    );
  }
}
