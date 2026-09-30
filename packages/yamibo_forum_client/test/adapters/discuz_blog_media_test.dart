import 'dart:async';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

import '../support/blog_fixtures.dart';
import '../support/blog_operation_fixtures.dart';

void main() {
  late MemoryForumSessionStore sessions;
  late BlogOperationNetwork network;
  late _Multipart multipart;
  late YamiboForumClient client;
  setUp(() async {
    sessions = MemoryForumSessionStore();
    await loginBlogActor(sessions, '101');
    network = BlogOperationNetwork(UserBlogAction.edit)..editor = _mediaForm();
    multipart = _Multipart();
    client = YamiboForumClientBuilder(
      config: blogConfig,
      network: network,
      sessionStore: sessions,
      multipartClient: multipart,
    ).buildStandardClient();
  });
  Future<UserBlogEditorPreparation> prepare() async =>
      (await client.blogOperations!.prepareEditor(
        blogOperationTarget(UserBlogAction.edit),
      )).dataOrNull!;
  Future<DataCommandResult<UserBlogUploadedImage>> upload(
    UserBlogEditorPreparation ready, {
    ForumImageAttachmentContent? content,
    ForumRequestCancellation? cancellation,
    void Function(double)? onProgress,
  }) => client.blogMedia!.uploadImage(
    UserBlogImageUploadSubmission(
      preparation: ready,
      actorUserId: '101',
      content: content ?? _content(),
      cancellation: cancellation,
      onProgress: onProgress,
    ),
  );

  test(
    'draft restoration reads album pages and binds fresh proofs without upload',
    () async {
      final ready = await prepare();
      final original = blogConfig.siteOrigin.resolve(
        'data/attachment/album/test.jpg',
      );
      network.onRequest = (request) {
        if (request.uri.queryParameters['op'] == 'album') {
          network.editor = request.uri.queryParameters['page'] == '1'
              ? _albumPage('2', 'data/attachment/album/other.jpg', last: 2)
              : _albumPage('77', original.toString());
        }
      };
      final result = await client.blogMedia!.restoreDraftImages(
        ready,
        images: [
          UserBlogDraftImageReference(picId: '77', originalUri: original),
        ],
      );
      final restored = result.dataOrNull!;
      expect(restored.missingPicIds, isEmpty);
      expect(restored.images.single.originalImageUri, original);
      expect(multipart.requests, isEmpty);
      final reads = network.requests
          .where((r) => r.uri.queryParameters['op'] == 'album')
          .toList();
      expect(reads.map((r) => r.uri.queryParameters['page']), ['1', '2']);
      expect(reads.every((r) => r.method == ForumRequestMethod.get), isTrue);
      final saved = await client.blogOperations!.save(
        UserBlogEditorSubmission(
          preparation: ready,
          actorUserId: '101',
          subject: ready.subject,
          bodyHtml: '<img src="$original">',
          tags: ready.tags,
          siteCategoryId: ready.siteCategoryId,
          personalCategoryId: ready.personalCategoryId,
          publishFeed: ready.publishFeed,
          uploadedImages: restored.images,
        ),
      );
      expect(saved, isA<DataCommandApplied<UserBlogReceipt>>());
      expect(
        Map.fromEntries(
          (network.posts.single.body! as ForumMultipartFields).entries,
        ),
        containsPair('picids[77]', '77'),
      );
    },
  );

  test('missing and changed image addresses remain unverified', () async {
    final ready = await prepare();
    network.editor = _albumPage('77', 'data/attachment/album/replaced.jpg');
    final result = await client.blogMedia!.restoreDraftImages(
      ready,
      images: [
        UserBlogDraftImageReference(
          picId: '77',
          originalUri: blogConfig.siteOrigin.resolve('old.jpg'),
        ),
        UserBlogDraftImageReference(
          picId: '78',
          originalUri: blogConfig.siteOrigin.resolve('missing.jpg'),
        ),
      ],
    );
    expect(result.dataOrNull!.images, isEmpty);
    expect(result.dataOrNull!.missingPicIds, {'77', '78'});
    expect(multipart.requests, isEmpty);
  });

  for (final altered in ['actor', 'pagination', 'table', 'identity']) {
    test('draft album $altered cannot create binding proof', () async {
      final ready = await prepare();
      var album = _albumPage('77', 'data/attachment/album/test.jpg', last: 2);
      album = switch (altered) {
        'actor' => album.replaceAll("discuz_uid = '101'", "discuz_uid = '202'"),
        'pagination' => album.replaceAll(
          'home.php?mod=misc',
          'https://evil.test/home.php?mod=misc',
        ),
        'table' => album.replaceAll('class="imgl"', 'class="other"'),
        _ => album.replaceAll('image_td_77', 'image_td_invalid'),
      };
      network.editor = album;
      final result = await client.blogMedia!.restoreDraftImages(
        ready,
        images: [
          UserBlogDraftImageReference(
            picId: '77',
            originalUri: blogConfig.siteOrigin.resolve(
              'data/attachment/album/test.jpg',
            ),
          ),
        ],
      );
      expect(
        result,
        isA<DataReadFailure<UserBlogDraftImageRestoration, Object?>>(),
      );
      expect(multipart.requests, isEmpty);
    });
  }

  test('actor change and cancellation invalidate late album reads', () async {
    final ready = await prepare();
    network.editor = _albumPage('77', 'data/attachment/album/test.jpg');
    network.onRequest = (_) => loginBlogActor(sessions, '202');
    final result = await client.blogMedia!.restoreDraftImages(
      ready,
      images: [
        UserBlogDraftImageReference(
          picId: '77',
          originalUri: blogConfig.siteOrigin.resolve(
            'data/attachment/album/test.jpg',
          ),
        ),
      ],
    );
    expect(
      result,
      isA<DataReadFailure<UserBlogDraftImageRestoration, Object?>>(),
    );
    final cancellation = ForumRequestCancellation()..cancel();
    expect(
      await client.blogMedia!.restoreDraftImages(
        ready,
        images: const [],
        cancellation: cancellation,
      ),
      isA<DataReadFailure<UserBlogDraftImageRestoration, Object?>>(),
    );
  });

  test(
    'facade shares editor proof and exposes thirty dedicated image smileys',
    () async {
      final ready = await prepare();
      expect(client.blogMedia, same(client.blogOperations));
      expect(ready.imageUploadLimits!.maximumBytes, 2048 * 1024);
      expect(
        ready.imageUploadLimits!.extensionRules.map((rule) => rule.extension),
        ['jpg', 'jpeg', 'gif', 'png', 'webp'],
      );
      expect(ready.blogSmilies, hasLength(30));
      expect(ready.blogSmilies.first.index, 1);
      expect(
        ready.blogSmilies.first.imageUri.path,
        '/static/image/smiley/comcom/1.gif',
      );
      expect(
        ready.blogSmilies.last.imageUri.path,
        '/static/image/smiley/comcom/30.gif',
      );
      expect(multipart.requests, isEmpty);
    },
  );

  for (final transform in <String Function(String)>[
    (s) => s.replaceAll('icoImg_btn_imgattachlist', 'no_upload_control'),
    (s) => s.replaceAll('operation=album', 'operation=upload'),
    (s) => s.replaceAll('"uid":"101"', '"uid":"202"'),
    (s) => s.replaceAll('0123456789abcdef0123456789abcdef', ''),
    (s) => s.replaceAll('"2048"', '"invalid"'),
    (s) => s.replaceAll('*.jpg;*.jpeg;*.gif;*.png;*.webp', '*.exe'),
    (s) => s.replaceAll(
      'upload_url: "misc.php',
      'upload_url: "https://evil.test/misc.php',
    ),
  ]) {
    test('unproved media config keeps text editing available', () async {
      network.editor = transform(_mediaForm());
      final ready = await prepare();
      expect(ready.imageUploadLimits, isNull);
      expect(
        await upload(ready),
        isA<DataCommandUnsupported<UserBlogUploadedImage>>(),
      );
      expect(
        await client.blogOperations!.save(blogEditorSubmission(ready)),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
      expect(multipart.requests, isEmpty);
    });
  }

  test(
    'plain legacy forms have neither upload nor smiley capabilities',
    () async {
      network.editor = blogEditorForm();
      final ready = await prepare();
      expect(ready.blogSmilies, isEmpty);
      expect(ready.imageUploadLimits, isNull);
    },
  );

  test(
    'missing multipart disables uploads without removing the smiley catalog',
    () async {
      final textOnly = YamiboForumClientBuilder(
        config: blogConfig,
        network: network,
        sessionStore: sessions,
      ).buildStandardClient();
      final ready = (await textOnly.blogOperations!.prepareEditor(
        blogOperationTarget(UserBlogAction.edit),
      )).dataOrNull!;
      expect(ready.imageUploadLimits, isNull);
      expect(ready.blogSmilies, hasLength(30));
    },
  );

  test(
    'desktop template globals, quoted zero limit and parallel upload widgets parse',
    () async {
      // Shapes from header_common.htm and home/editor_image_menu.htm. PHP emits
      // the byte limit divided by 1024 as a quoted number, never a KB suffix.
      network.editor = _mediaForm()
          .replaceFirst(
            "var STATICURL = 'static/';",
            "var STYLEID = '1', STATICURL = 'static/', IMGDIR = 'static/image/common';",
          )
          .replaceFirst('"uid":"101"', '"uid" : "101"')
          .replaceFirst('file_size_limit: "2048"', 'file_size_limit : "0"')
          .replaceFirst(
            'upload_url: "misc.php',
            'upload_url: "${blogConfig.siteOrigin}/misc.php',
          )
          .replaceFirst(
            'var upload = new SWFUpload({',
            "var attachUpload = new SWFUpload({post_params: {uid: 'unrelated'}});\nvar upload = new SWFUpload({",
          );
      final ready = await prepare();
      expect(ready.imageUploadLimits, isNotNull);
      expect(ready.imageUploadLimits!.maximumBytes, isNull);
      expect(ready.blogSmilies, hasLength(30));
      expect(
        await upload(ready),
        isA<DataCommandApplied<UserBlogUploadedImage>>(),
      );
    },
  );

  test('editor source override keeps media bound to that same adapter', () {
    final overridden =
        YamiboForumClientBuilder(
          config: blogConfig,
          network: network,
          sessionStore: sessions,
          multipartClient: multipart,
        ).buildStandardClient(
          sourceOverrides: ForumClientSourcePlan(
            blogOperations: client.blogOperations,
          ),
        );
    expect(overridden.blogMedia, same(client.blogOperations));
  });

  test(
    'uploads album Filedata with source credentials and normalized progress',
    () async {
      final ready = await prepare();
      final progress = <double>[];
      final result = await upload(ready, onProgress: progress.add);
      expect(result, isA<DataCommandApplied<UserBlogUploadedImage>>());
      final image = result.receiptOrNull!;
      expect(image.picId, '77');
      expect(image.imageUri.path, '/data/attachment/album/test.jpg');
      expect(image.imageUri, image.originalImageUri);
      expect(image.originalImageUri.path, '/data/attachment/album/test.jpg');
      final sent = multipart.requests.single;
      expect(sent.uri.path, '/misc.php');
      expect(sent.uri.queryParameters, {
        'mod': 'swfupload',
        'action': 'swfupload',
        'operation': 'album',
      });
      expect(sent.fields, {
        'uid': '101',
        'hash': '0123456789abcdef0123456789abcdef',
      });
      expect(sent.file.fieldName, 'Filedata');
      expect(sent.file.fileName, 'image.png');
      expect(sent.followRedirects, isFalse);
      expect(sent.context.silent, isTrue);
      expect(progress, [0.5, 1.0]);
      expect(await sent.file.openRead().expand((bytes) => bytes).toList(), [
        1,
        2,
        3,
      ]);
      expect(await sent.file.openRead().expand((bytes) => bytes).toList(), [
        1,
        2,
        3,
      ]);
      expect(network.requests, hasLength(1));
    },
  );

  for (final content in [
    _content(name: '../image.png'),
    _content(name: 'bad\n.png'),
    _content(mime: 'text/html'),
    _content(name: 'image.exe'),
    _content(length: 0),
    _content(length: 2048 * 1024 + 1),
  ]) {
    test(
      'invalid local image is not sent (${content.fileName}/${content.contentLength})',
      () async {
        expect(
          await upload(await prepare(), content: content),
          isA<DataCommandNotSent<UserBlogUploadedImage>>(),
        );
        expect(multipart.requests, isEmpty);
      },
    );
  }

  test('cancelled and changed-actor uploads never send', () async {
    final ready = await prepare();
    final cancellation = ForumRequestCancellation()..cancel();
    expect(
      await upload(ready, cancellation: cancellation),
      isA<DataCommandNotSent<UserBlogUploadedImage>>(),
    );
    await loginBlogActor(sessions, '202');
    expect(
      await upload(ready),
      isA<DataCommandNotSent<UserBlogUploadedImage>>(),
    );
    expect(multipart.requests, isEmpty);
  });

  test('late upload results after account changes remain unknown', () async {
    multipart.onSend = () => loginBlogActor(sessions, '202');
    expect(
      await upload(await prepare()),
      isA<DataCommandOutcomeUnknown<UserBlogUploadedImage>>(),
    );
    expect(multipart.requests, hasLength(1));
  });

  for (final response in [
    'garbage',
    '{"picid":"77","url":"javascript:alert(1)","bigimg":"/image.png"}',
    '{"picid":"77","url":"0","bigimg":"0"}',
  ]) {
    test(
      'malformed upload receipts are unknown without retry: $response',
      () async {
        multipart.body = response;
        expect(
          await upload(await prepare()),
          isA<DataCommandOutcomeUnknown<UserBlogUploadedImage>>(),
        );
        expect(multipart.requests, hasLength(1));
      },
    );
  }

  test('explicit zero image response is a rejection', () async {
    multipart.body = '{"picid":"0","url":"0","bigimg":"0"}';
    expect(
      await upload(await prepare()),
      isA<DataCommandRejected<UserBlogUploadedImage>>(),
    );
  });

  test(
    'redirects and transport exceptions cannot establish applied images',
    () async {
      final ready = await prepare();
      multipart.uri = Uri.parse('https://external.test/response');
      expect(
        await upload(ready),
        isA<DataCommandOutcomeUnknown<UserBlogUploadedImage>>(),
      );
      multipart.onSend = () =>
          throw const FormatException('private transport payload');
      final result = await upload(ready);
      expect(result, isA<DataCommandOutcomeUnknown<UserBlogUploadedImage>>());
      expect(
        result.failureOrNull!.diagnosticMessage,
        'blog_image_transport_failed',
      );
      expect(multipart.requests, hasLength(2));
    },
  );

  test(
    'fresh editor tickets bind only uploaded images still in the HTML',
    () async {
      final image = (await upload(await prepare())).receiptOrNull!;
      final fresh = await prepare();
      final body = '<p><b>富文本</b></p><img src="${image.imageUri}">';
      expect(
        await client.blogOperations!.save(_submission(fresh, body, [image])),
        isA<DataCommandApplied<UserBlogReceipt>>(),
      );
      final fields = Map.fromEntries(
        (network.posts.single.body! as ForumMultipartFields).entries,
      );
      expect(fields['picids[77]'], '77');
      expect(fields['savealbumid'], '0');
      expect(fields['message'], body);
    },
  );

  test('removed images are not rebound or appended by the server', () async {
    final ready = await prepare();
    final image = (await upload(ready)).receiptOrNull!;
    await client.blogOperations!.save(
      _submission(ready, '<p>Image removed</p>', [image]),
    );
    final fields = Map.fromEntries(
      (network.posts.single.body! as ForumMultipartFields).entries,
    );
    expect(fields.containsKey('picids[77]'), isFalse);
    expect(fields.containsKey('savealbumid'), isFalse);
  });

  test('forged receipts and cross-editor receipts cannot bind', () async {
    final ready = await prepare();
    final image = (await upload(ready)).receiptOrNull!;
    final fake = UserBlogUploadedImage(
      picId: '78',
      imageUri: image.imageUri,
      originalImageUri: image.originalImageUri,
      token: image.token,
    );
    expect(
      await client.blogOperations!.save(
        _submission(ready, '<img src="${image.imageUri}">', [fake]),
      ),
      isA<DataCommandNotSent<UserBlogReceipt>>(),
    );
    final other = YamiboForumClientBuilder(
      config: blogConfig,
      network: network,
      sessionStore: sessions,
      multipartClient: multipart,
    ).buildStandardClient();
    final otherReady = (await other.blogOperations!.prepareEditor(
      blogOperationTarget(UserBlogAction.edit),
    )).dataOrNull!;
    expect(
      await other.blogOperations!.save(
        _submission(otherReady, '<img src="${image.imageUri}">', [image]),
      ),
      isA<DataCommandNotSent<UserBlogReceipt>>(),
    );
    expect(network.posts, isEmpty);
  });

  test('source-proved existing picture bindings survive editing', () async {
    network.editor = _mediaForm().replaceFirst(
      '</form>',
      '<input type="hidden" name="picids[31]" value="31"></form>',
    );
    await client.blogOperations!.save(blogEditorSubmission(await prepare()));
    final fields = Map.fromEntries(
      (network.posts.single.body! as ForumMultipartFields).entries,
    );
    expect(fields['picids[31]'], '31');
  });
}

String _albumPage(String id, String original, {int last = 1}) =>
    '''
$blogOperationHeader
<table class="imgl"><tr><td id="image_td_$id">
<img src="thumb.jpg" onclick="insertImage('$original');"></td></tr></table>
<div class="pgs">${last > 1 ? '<a href="home.php?mod=misc&amp;ac=ajax&amp;op=album&amp;id=0&amp;page=$last">$last</a>' : ''}</div>
''';

UserBlogEditorSubmission _submission(
  UserBlogEditorPreparation ready,
  String body,
  List<UserBlogUploadedImage> images,
) => UserBlogEditorSubmission(
  preparation: ready,
  actorUserId: '101',
  subject: ready.subject,
  bodyHtml: body,
  tags: ready.tags,
  siteCategoryId: ready.siteCategoryId,
  personalCategoryId: ready.personalCategoryId,
  publishFeed: ready.publishFeed,
  uploadedImages: images,
);

ForumImageAttachmentContent _content({
  String name = 'image.png',
  String mime = 'image/png',
  int length = 3,
}) => ForumImageAttachmentContent(
  fileName: name,
  mimeType: mime,
  contentLength: length,
  openRead: () => Stream.value([1, 2, 3]),
);

String _mediaForm() => '''${blogEditorForm()}
<script>var STATICURL = 'static/';</script>
<iframe name="uchome-ifrHtmlEditor" src="home.php?mod=editor&amp;allowhtml=0"></iframe>
<li id="icoImg_btn_imgattachlist"><a>Upload</a></li>
<script>
var upload = new SWFUpload({
  upload_url: "misc.php?mod=swfupload&action=swfupload&operation=album",
  post_params: {"uid":"101", "hash":"0123456789abcdef0123456789abcdef"},
  file_size_limit: "2048",
  file_types: "*.jpg;*.jpeg;*.gif;*.png;*.webp",
  custom_settings: {uploadSource: 'portal', uploadType: 'blog'}
});
</script>''';

final class _Multipart implements ForumMultipartClient {
  String body =
      '{"picid":"77","url":"/data/attachment/album/test.jpg.thumb.jpg","bigimg":"/data/attachment/album/test.jpg"}';
  Uri? uri;
  FutureOr<void> Function()? onSend;
  final requests = <ForumMultipartRequest>[];
  @override
  Future<ForumTransportResult<ForumMultipartResponse>> sendMultipart(
    ForumMultipartRequest request,
  ) async {
    requests.add(request);
    await onSend?.call();
    request.onSendProgress?.call(1, 2);
    request.onSendProgress?.call(2, 2);
    return ForumTransportSuccess(
      ForumMultipartResponse(
        uri: uri ?? request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}
