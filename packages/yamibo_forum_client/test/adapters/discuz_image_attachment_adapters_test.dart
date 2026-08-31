import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_api_client.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_image_attachment_adapters.dart';

void main() {
  group('Discuz image attachment upload', () {
    test('checkpost v1 preserves image limits without exposing hash', () async {
      final network = _QueueNetwork(<Object?>[_checkpost()]);
      final multipart = _Multipart('42');
      final adapter = _uploadAdapter(network, multipart);

      final result = await adapter.load(
        const ForumImageAttachmentUploadPreparationRequest(fid: '30'),
      );

      expect(
        result,
        isA<
          DataReadSuccess<
            ForumImageAttachmentUploadPreparation,
            ForumImageAttachmentUploadCapabilities
          >
        >(),
        reason: result.failureOrNull?.code,
      );
      final data = result.dataOrNull!;
      expect(data.fid, '30');
      expect(
        data.extensionRules.map((rule) => rule.extension),
        orderedEquals(<String>['jpg', 'png', 'gif']),
      );
      expect(data.extensionRules[0].maximumBytes, isNull);
      expect(data.extensionRules[1].maximumBytes, 2048);
      expect(data.remainingBytes, isNull);
      expect(data.remainingCount, 3);
      expect(network.requests.single.uri.queryParameters, <String, String>{
        'module': 'checkpost',
        'version': '1',
        'fid': '30',
      });
      expect(data.toString(), isNot(contains('fixture-upload-hash')));
    });

    test(
      'checkpost rejects unsupported image rules and session mismatch',
      () async {
        final unsupported = await _uploadAdapter(
          _QueueNetwork(<Object?>[
            _checkpost(allowUpload: <String, Object?>{'webp': '4096'}),
          ]),
          _Multipart('42'),
        ).load(const ForumImageAttachmentUploadPreparationRequest(fid: '30'));
        expect(
          unsupported,
          isA<
            DataReadFailure<
              ForumImageAttachmentUploadPreparation,
              ForumImageAttachmentUploadCapabilities
            >
          >(),
        );
        expect(
          unsupported.failureOrNull?.code,
          'checkpost_image_upload_unsupported',
        );

        final sessions = MemoryForumSessionStore();
        await sessions.merge(_authenticatedSession(userId: '99999'));
        final mismatch = await _uploadAdapter(
          _QueueNetwork(<Object?>[_checkpost()]),
          _Multipart('42'),
          sessions: sessions,
        ).load(const ForumImageAttachmentUploadPreparationRequest(fid: '30'));
        expect(
          mismatch,
          isA<
            DataReadFailure<
              ForumImageAttachmentUploadPreparation,
              ForumImageAttachmentUploadCapabilities
            >
          >(),
        );
        expect(
          mismatch.failureOrNull?.code,
          'checkpost_session_identity_mismatch',
        );
      },
    );

    test('positive aid is applied and file stream is passed once', () async {
      final network = _QueueNetwork(<Object?>[_checkpost()]);
      final multipart = _Multipart('42');
      final adapter = _uploadAdapter(network, multipart);
      final preparation = (await adapter.load(
        const ForumImageAttachmentUploadPreparationRequest(fid: '30'),
      )).dataOrNull!;

      final result = await adapter.execute(
        ForumImageAttachmentUploadSubmission(
          preparation: preparation,
          content: ForumImageAttachmentContent(
            fileName: 'fixture.jpg',
            mimeType: 'image/jpeg',
            contentLength: 3,
            openRead: () => Stream.value(<int>[1, 2, 3]),
          ),
        ),
      );

      expect(
        result,
        isA<DataCommandApplied<ForumImageAttachmentUploadReceipt>>(),
      );
      expect(result.receiptOrNull!.aid, '42');
      expect(multipart.requests.single.uri.queryParameters, <String, String>{
        'module': 'forumupload',
        'version': '4',
        'fid': '30',
        'type': 'image',
        'filetype': 'image/jpeg',
      });
      expect(multipart.requests.single.fields, <String, String>{
        'uid': '30001',
        'hash': 'fixture-upload-hash',
      });
      expect(multipart.requests.single.file.fieldName, 'Filedata');
      expect(await multipart.requests.single.file.openRead().single, [1, 2, 3]);
    });

    test(
      'every Discuz negative status has a stable precise rejection',
      () async {
        const expected = <int, String>{
          -1: 'attachment_extension_not_allowed',
          -2: 'attachment_upload_invalid',
          -3: 'attachment_group_file_size_exceeded',
          -4: 'attachment_extension_banned',
          -5: 'attachment_extension_file_size_exceeded',
          -6: 'attachment_upload_permission_denied',
          -7: 'attachment_invalid_image',
          -8: 'attachment_save_failed',
          -9: 'attachment_save_failed',
          -10: 'attachment_upload_hash_invalid',
          -11: 'attachment_daily_quota_exceeded',
          -12: 'attachment_filename_rejected',
          -13: 'attachment_dimensions_exceeded',
        };
        for (final entry in expected.entries) {
          final network = _QueueNetwork(<Object?>[_checkpost()]);
          final adapter = _uploadAdapter(
            network,
            _Multipart(entry.key.toString()),
          );
          final preparation = (await adapter.load(
            const ForumImageAttachmentUploadPreparationRequest(fid: '30'),
          )).dataOrNull!;
          final result = await adapter.execute(
            ForumImageAttachmentUploadSubmission(
              preparation: preparation,
              content: ForumImageAttachmentContent(
                fileName: 'fixture.jpg',
                mimeType: 'image/jpeg',
                contentLength: 1,
                openRead: () => Stream.value(<int>[1]),
              ),
            ),
          );
          expect(
            result,
            isA<DataCommandRejected<ForumImageAttachmentUploadReceipt>>(),
            reason: '${entry.key}',
          );
          expect(result.failureOrNull!.code, entry.value);
          expect(
            result.failureOrNull!.diagnosticMessage,
            isNot(contains('fixture-upload-hash')),
          );
        }
      },
    );

    test('empty and malformed upload responses are outcome unknown', () async {
      for (final body in <String>['', '0', '<html>failure</html>']) {
        final adapter = _uploadAdapter(
          _QueueNetwork(<Object?>[_checkpost()]),
          _Multipart(body),
        );
        final preparation = (await adapter.load(
          const ForumImageAttachmentUploadPreparationRequest(fid: '30'),
        )).dataOrNull!;
        final result = await adapter.execute(
          ForumImageAttachmentUploadSubmission(
            preparation: preparation,
            content: ForumImageAttachmentContent(
              fileName: 'fixture.jpg',
              mimeType: 'image/jpeg',
              contentLength: 1,
              openRead: () => Stream.value(<int>[1]),
            ),
          ),
        );
        expect(
          result,
          isA<DataCommandOutcomeUnknown<ForumImageAttachmentUploadReceipt>>(),
        );
      }
    });

    test(
      'quota and a missing multipart Host fail closed before upload',
      () async {
        final multipart = _Multipart('42');
        final blockedAdapter = _uploadAdapter(
          _QueueNetwork(<Object?>[
            _checkpost(
              attachRemain: <String, Object?>{'size': '100', 'count': '0'},
            ),
          ]),
          multipart,
        );
        final blockedPreparation = (await blockedAdapter.load(
          const ForumImageAttachmentUploadPreparationRequest(fid: '30'),
        )).dataOrNull!;
        final blocked = await blockedAdapter.execute(
          ForumImageAttachmentUploadSubmission(
            preparation: blockedPreparation,
            content: ForumImageAttachmentContent(
              fileName: 'fixture.jpg',
              mimeType: 'image/jpeg',
              contentLength: 1,
              openRead: () => Stream.value(<int>[1]),
            ),
          ),
        );
        expect(
          blocked,
          isA<DataCommandNotSent<ForumImageAttachmentUploadReceipt>>(),
        );
        expect(blocked.failureOrNull?.code, 'attachment_quota_exceeded');
        expect(multipart.requests, isEmpty);

        final unsupportedAdapter = _uploadAdapter(
          _QueueNetwork(<Object?>[_checkpost()]),
          null,
        );
        final unsupportedPreparation = (await unsupportedAdapter.load(
          const ForumImageAttachmentUploadPreparationRequest(fid: '30'),
        )).dataOrNull!;
        final unsupported = await unsupportedAdapter.execute(
          ForumImageAttachmentUploadSubmission(
            preparation: unsupportedPreparation,
            content: ForumImageAttachmentContent(
              fileName: 'fixture.jpg',
              mimeType: 'image/jpeg',
              contentLength: 1,
              openRead: () => Stream.value(<int>[1]),
            ),
          ),
        );
        expect(
          unsupported,
          isA<DataCommandUnsupported<ForumImageAttachmentUploadReceipt>>(),
        );
      },
    );
  });

  group('Discuz unused image attachments', () {
    test('catalog returns ordered validated thumbnail references', () async {
      final sessions = MemoryForumSessionStore();
      await sessions.merge(_authenticatedSession());
      final network = _QueueNetwork(<Object?>[_catalogWithImage()]);
      final adapter = _unusedAdapter(network, sessions);

      final result = await adapter.load(
        const ForumUnusedImageAttachmentDirectoryRequest(),
      );

      expect(
        result,
        isA<
          DataReadSuccess<
            ForumUnusedImageAttachmentDirectory,
            ForumUnusedImageAttachmentCapabilities
          >
        >(),
      );
      final item = result.dataOrNull!.items.single;
      expect(item.aid, '1644337');
      expect(item.fileName, 'fixture.jpg');
      expect(item.thumbnail.origin, ForumResourceOrigin.sameSite);
      expect(item.thumbnail.referer.queryParameters['action'], 'imagelist');
    });

    test('zero delete response uses one readback to prove absence', () async {
      final sessions = MemoryForumSessionStore();
      await sessions.merge(_authenticatedSession());
      final network = _QueueNetwork(<Object?>[
        _catalogWithImage(),
        _cdata('0'),
        _emptyCatalog(),
      ]);
      final adapter = _unusedAdapter(network, sessions);
      final directory = (await adapter.load(
        const ForumUnusedImageAttachmentDirectoryRequest(),
      )).dataOrNull!;

      final result = await adapter.execute(
        DeleteUnusedImageAttachmentRequest(
          aid: '1644337',
          directoryToken: directory.token,
        ),
      );

      expect(
        result,
        isA<DataCommandApplied<ForumImageAttachmentDeleteReceipt>>(),
      );
      expect(result.receiptOrNull!.deletedCount, 0);
      expect(network.requests, hasLength(3));
      expect(network.requests[1].uri.queryParameters['action'], 'deleteattach');
      expect(network.requests[2].uri.queryParameters['action'], 'imagelist');
    });

    test('directory proof rejects an unrelated aid before deletion', () async {
      final sessions = MemoryForumSessionStore();
      await sessions.merge(_authenticatedSession());
      final network = _QueueNetwork(<Object?>[_catalogWithImage()]);
      final adapter = _unusedAdapter(network, sessions);
      final directory = (await adapter.load(
        const ForumUnusedImageAttachmentDirectoryRequest(),
      )).dataOrNull!;

      final result = await adapter.execute(
        DeleteUnusedImageAttachmentRequest(
          aid: '999',
          directoryToken: directory.token,
        ),
      );

      expect(
        result,
        isA<DataCommandNotSent<ForumImageAttachmentDeleteReceipt>>(),
      );
      expect(network.requests, hasLength(1));
    });

    test('empty catalog requires a confirmed authenticated session', () async {
      final anonymous = await _unusedAdapter(
        _QueueNetwork(<Object?>[_emptyCatalog()]),
        MemoryForumSessionStore(),
      ).load(const ForumUnusedImageAttachmentDirectoryRequest());
      expect(
        anonymous,
        isA<
          DataReadFailure<
            ForumUnusedImageAttachmentDirectory,
            ForumUnusedImageAttachmentCapabilities
          >
        >(),
      );

      final sessions = MemoryForumSessionStore();
      await sessions.merge(_authenticatedSession());
      final authenticated = await _unusedAdapter(
        _QueueNetwork(<Object?>[_emptyCatalog()]),
        sessions,
      ).load(const ForumUnusedImageAttachmentDirectoryRequest());
      expect(
        authenticated,
        isA<
          DataReadSuccess<
            ForumUnusedImageAttachmentDirectory,
            ForumUnusedImageAttachmentCapabilities
          >
        >(),
      );
      expect(authenticated.dataOrNull?.items, isEmpty);
    });

    test('catalog rejects cross-site thumbnail references', () async {
      final sessions = MemoryForumSessionStore();
      await sessions.merge(_authenticatedSession());
      final result = await _unusedAdapter(
        _QueueNetwork(<Object?>[
          _catalogWithImage(
            source: 'https://evil.example/forum.php?mod=image&aid=1644337',
          ),
        ]),
        sessions,
      ).load(const ForumUnusedImageAttachmentDirectoryRequest());

      expect(
        result,
        isA<
          DataReadFailure<
            ForumUnusedImageAttachmentDirectory,
            ForumUnusedImageAttachmentCapabilities
          >
        >(),
      );
    });

    test('identical duplicate aids deduplicate but conflicts fail', () async {
      final sessions = MemoryForumSessionStore();
      await sessions.merge(_authenticatedSession());
      final duplicate = await _unusedAdapter(
        _QueueNetwork(<Object?>[_catalogWithDuplicate(conflicting: false)]),
        sessions,
      ).load(const ForumUnusedImageAttachmentDirectoryRequest());
      expect(
        duplicate,
        isA<
          DataReadSuccess<
            ForumUnusedImageAttachmentDirectory,
            ForumUnusedImageAttachmentCapabilities
          >
        >(),
      );
      expect(duplicate.dataOrNull?.items, hasLength(1));

      final conflict = await _unusedAdapter(
        _QueueNetwork(<Object?>[_catalogWithDuplicate(conflicting: true)]),
        sessions,
      ).load(const ForumUnusedImageAttachmentDirectoryRequest());
      expect(
        conflict,
        isA<
          DataReadFailure<
            ForumUnusedImageAttachmentDirectory,
            ForumUnusedImageAttachmentCapabilities
          >
        >(),
      );
    });
  });

  group('Discuz post image attachment delete', () {
    test('sends stable post identities and accepts a positive count', () async {
      final network = _QueueNetwork(<Object?>[_cdata('1')]);
      final config = _config();
      final adapter = DiscuzPostImageAttachmentDeleteAdapter(
        config: config,
        network: network,
        requestProfiles: DefaultForumRequestProfileResolver(config),
        formhash: const _Formhash(),
      );

      final result = await adapter.execute(
        const DeletePostImageAttachmentRequest(
          tid: '10001',
          pid: '20001',
          aid: '30001',
        ),
      );

      expect(
        result,
        isA<DataCommandApplied<ForumImageAttachmentDeleteReceipt>>(),
      );
      expect(result.receiptOrNull?.aid, '30001');
      expect(network.requests, hasLength(1));
      expect(network.requests.single.uri.queryParameters, <String, String>{
        'mod': 'ajax',
        'action': 'deleteattach',
        'inajax': 'yes',
        'formhash': 'fixture-formhash',
        'tid': '10001',
        'pid': '20001',
        'aids[]': '30001',
      });
    });

    test('invalid identity is not sent and zero remains unknown', () async {
      final network = _QueueNetwork(<Object?>[_cdata('0')]);
      final config = _config();
      final adapter = DiscuzPostImageAttachmentDeleteAdapter(
        config: config,
        network: network,
        requestProfiles: DefaultForumRequestProfileResolver(config),
        formhash: const _Formhash(),
      );

      final invalid = await adapter.execute(
        const DeletePostImageAttachmentRequest(
          tid: '0',
          pid: '20001',
          aid: '30001',
        ),
      );
      expect(
        invalid,
        isA<DataCommandNotSent<ForumImageAttachmentDeleteReceipt>>(),
      );
      expect(network.requests, isEmpty);

      final unknown = await adapter.execute(
        const DeletePostImageAttachmentRequest(
          tid: '10001',
          pid: '20001',
          aid: '30001',
        ),
      );
      expect(
        unknown,
        isA<DataCommandOutcomeUnknown<ForumImageAttachmentDeleteReceipt>>(),
      );
    });
  });
}

DiscuzImageAttachmentUploadAdapter _uploadAdapter(
  ForumClientNetwork network,
  ForumMultipartClient? multipart, {
  ForumSessionStore? sessions,
}) {
  final config = _config();
  final effectiveSessions = sessions ?? MemoryForumSessionStore();
  return DiscuzImageAttachmentUploadAdapter(
    DiscuzApiClient(
      config: config,
      network: network,
      requestProfiles: DefaultForumRequestProfileResolver(config),
      sessionStore: effectiveSessions,
    ),
    config,
    multipart,
    effectiveSessions,
    DefaultForumRequestProfileResolver(config),
  );
}

DiscuzUnusedImageAttachmentAdapter _unusedAdapter(
  ForumClientNetwork network,
  ForumSessionStore sessions,
) {
  final config = _config();
  return DiscuzUnusedImageAttachmentAdapter(
    config,
    network,
    DefaultForumRequestProfileResolver(config),
    sessions,
    const _Formhash(),
  );
}

ForumClientConfig _config() => ForumClientConfig(
  siteOrigin: Uri.parse('https://bbs.example.test/'),
  apiOrigin: Uri.parse('https://bbs.example.test/api/mobile/index.php'),
  userAgent: 'fixture-agent',
);

Map<String, Object?> _checkpost({
  Map<String, Object?>? allowUpload,
  Map<String, Object?>? attachRemain,
}) => <String, Object?>{
  'Version': '1',
  'Variables': <String, Object?>{
    'member_uid': '30001',
    'member_username': 'fixture-user',
    'allowperm': <String, Object?>{
      'uploadhash': 'fixture-upload-hash',
      'allowupload':
          allowUpload ??
          <String, Object?>{
            'jpg': '-1',
            'png': '2048',
            'gif': '1024',
            'webp': '4096',
            'bmp': '0',
          },
      'attachremain':
          attachRemain ?? <String, Object?>{'size': '-1', 'count': '3'},
    },
  },
};

String _catalogWithImage({
  String source = 'forum.php?mod=image&amp;aid=1644337&amp;size=300x300',
}) => _cdata('''
<table class="imgl"><tr><td id="image_td_1644337">
  <img id="image_1644337" src="$source" />
  <a id="imageattach1644337" title="fixture.jpg"></a>
  <input name="attachnew[1644337][description]" value="fixture" />
</td></tr></table>
''');

String _catalogWithDuplicate({required bool conflicting}) {
  final secondDescription = conflicting ? 'different' : 'fixture';
  return _cdata('''
<table class="imgl"><tr>
  <td id="image_td_1644337">
    <img id="image_1644337" src="forum.php?mod=image&amp;aid=1644337" />
    <a id="imageattach1644337" title="fixture.jpg"></a>
    <input name="attachnew[1644337][description]" value="fixture" />
  </td>
  <td id="image_td_1644337">
    <img id="image_1644337" src="forum.php?mod=image&amp;aid=1644337" />
    <a id="imageattach1644337" title="fixture.jpg"></a>
    <input name="attachnew[1644337][description]" value="$secondDescription" />
  </td>
</tr></table>
''');
}

String _emptyCatalog() => _cdata('<table class="imgl"></table>');
String _cdata(String value) => '<root><![CDATA[$value]]></root>';

ForumSessionSnapshot _authenticatedSession({String userId = '30001'}) =>
    ForumSessionSnapshot(
      isLoggedIn: true,
      userId: userId,
      username: 'fixture-user',
      formhash: 'fixture-formhash',
      updatedAt: DateTime.utc(2026),
      formhashUpdatedAt: DateTime.now(),
      source: 'fixture',
    );

final class _QueueNetwork implements ForumClientNetwork {
  _QueueNetwork(this.responses);
  final List<Object?> responses;
  final List<ForumRequest> requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (responses.isEmpty) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.network,
          code: 'fixture_exhausted',
        ),
      );
    }
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: responses.removeAt(0),
      ),
    );
  }
}

final class _Multipart implements ForumMultipartClient {
  _Multipart(this.body);
  final String body;
  final List<ForumMultipartRequest> requests = <ForumMultipartRequest>[];

  @override
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  ) async {
    requests.add(request);
    request.onSendProgress?.call(
      request.file.contentLength,
      request.file.contentLength,
    );
    return ForumTransportSuccess(
      ForumMultipartResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: body,
      ),
    );
  }
}

final class _Formhash implements ForumFormhashProvider {
  const _Formhash();

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async => const ForumFormhashSuccess('fixture-formhash');
}
