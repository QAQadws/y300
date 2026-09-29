import 'dart:async';

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/profile/presentation/blog/blog_editor_media_controller.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  late MemoryFileSystem files;
  late _Picker picker;
  late _MediaService service;
  late UserBlogEditorPreparation? prepared;
  late String? actor;
  late bool sessionCurrent;
  late List<(UserBlogUploadedImage, String)> inserted;

  BlogEditorMediaController make() => BlogEditorMediaController(
    picker: picker,
    service: service,
    preparation: () => prepared,
    currentActor: () => actor,
    isSessionCurrent: () => sessionCurrent,
    onUploaded: (image, localPath) => inserted.add((image, localPath)),
    fileSystem: files,
  );

  setUp(() {
    files = MemoryFileSystem();
    files.file('/one.png').writeAsBytesSync([1, 2, 3]);
    files.file('/two.png').writeAsBytesSync([4, 5]);
    picker = _Picker();
    service = _MediaService();
    prepared = _preparation();
    actor = '101';
    sessionCurrent = true;
    inserted = [];
  });

  test(
    'serial uploads preserve picker order and borrow local preview files',
    () async {
      final media = make();
      addTearDown(media.dispose);
      final pending = media.pickImages();
      expect(media.value.busy, isTrue);
      picker.selected.complete([
        _picked('/two.png', 1),
        _picked('/one.png', 0),
      ]);
      await _until(() => service.requests.length == 1);
      final first = service.requests.single.input;
      expect(first.preparation, same(prepared));
      expect(first.actorUserId, '101');
      expect(first.content.fileName, 'one.png');
      expect(first.content.contentLength, 3);
      expect(await first.content.openRead().expand((bytes) => bytes).toList(), [
        1,
        2,
        3,
      ]);
      expect(await first.content.openRead().expand((bytes) => bytes).toList(), [
        1,
        2,
        3,
      ]);
      first.onProgress!(0.4);
      expect(media.value.progress, 0.4);
      expect(media.value.current, 1);
      expect(media.value.total, 2);
      final one = _image('1');
      service.requests.first.result.complete(DataCommandApplied(one));
      await _until(() => service.requests.length == 2);
      expect(inserted, [(one, '/one.png')]);
      final two = _image('2');
      service.requests.last.result.complete(DataCommandApplied(two));
      await pending;
      expect(inserted, [(one, '/one.png'), (two, '/two.png')]);
      expect(media.uploadedImages, [one, two]);
      expect(media.previewPaths, {
        one.imageUri.toString(): '/one.png',
        two.imageUri.toString(): '/two.png',
      });
      expect(media.value.busy, isFalse);
      expect(media.value.progress, 1);
      expect(media.value.failure, isNull);
      media.expire();
      expect(media.uploadedImages, isEmpty);
      expect(media.previewPaths, isEmpty);
      expect(files.file('/one.png').existsSync(), isTrue);
      expect(files.file('/two.png').existsSync(), isTrue);
    },
  );

  test(
    'repeated taps remain single flight through picking and uploading',
    () async {
      final media = make();
      addTearDown(media.dispose);
      final pending = media.pickImages();
      await media.pickImages();
      expect(picker.calls, 1);
      picker.selected.complete([_picked('/one.png', 0)]);
      await _until(() => service.requests.isNotEmpty);
      await media.pickImages();
      expect(picker.calls, 1);
      expect(service.requests, hasLength(1));
      service.requests.single.result.complete(DataCommandApplied(_image('1')));
      await pending;
    },
  );

  test(
    'missing capability or preparation never opens the image picker',
    () async {
      final media = make();
      addTearDown(media.dispose);
      prepared = _preparation(canUpload: false);
      await media.pickImages();
      prepared = null;
      await media.pickImages();
      expect(picker.calls, 0);
      expect(media.value.busy, isFalse);
    },
  );

  test('picker cancellation is a successful empty operation', () async {
    final media = make();
    addTearDown(media.dispose);
    final pending = media.pickImages();
    picker.selected.complete([]);
    await pending;
    expect(media.value.busy, isFalse);
    expect(media.value.failure, isNull);
    expect(service.requests, isEmpty);
  });

  test(
    'picker failures use a safe failure without raw paths or exception text',
    () async {
      final media = make();
      addTearDown(media.dispose);
      final pending = media.pickImages();
      picker.selected.completeError(
        const ComposerImagePickerException(cause: 'private path'),
      );
      await pending;
      expect(media.value.failure!.code, 'blog_image_picker_failed');
      expect(
        media.value.failure!.diagnosticMessage,
        isNot(contains('private path')),
      );
      expect(media.value.busy, isFalse);
      expect(service.requests, isEmpty);
    },
  );

  for (final invalidPath in ['/missing.png', '/empty.png']) {
    test('$invalidPath is rejected before starting a remote command', () async {
      files.file('/empty.png').createSync();
      final media = make();
      addTearDown(media.dispose);
      final pending = media.pickImages();
      picker.selected.complete([_picked(invalidPath, 0)]);
      await pending;
      expect(media.value.failure!.kind, DataCommandFailureKind.validation);
      expect(service.requests, isEmpty);
      expect(media.value.busy, isFalse);
    });
  }

  test('account change while selecting drops the picker result', () async {
    final media = make();
    addTearDown(media.dispose);
    final pending = media.pickImages();
    actor = '102';
    picker.selected.complete([_picked('/one.png', 0)]);
    await pending;
    expect(service.requests, isEmpty);
    expect(media.value.busy, isFalse);
    expect(inserted, isEmpty);
  });

  test('session invalidation drops late progress and applied images', () async {
    final media = make();
    addTearDown(media.dispose);
    final pending = media.pickImages();
    picker.selected.complete([_picked('/one.png', 0)]);
    await _until(() => service.requests.isNotEmpty);
    final request = service.requests.single;
    sessionCurrent = false;
    request.input.onProgress!(0.6);
    expect(request.input.cancellation!.isCancelled, isTrue);
    request.result.complete(DataCommandApplied(_image('1')));
    await pending;
    expect(inserted, isEmpty);
    expect(media.uploadedImages, isEmpty);
    expect(media.value.busy, isFalse);
  });

  test(
    'a replacement editor preparation invalidates the pending batch',
    () async {
      final media = make();
      addTearDown(media.dispose);
      final pending = media.pickImages();
      picker.selected.complete([
        _picked('/one.png', 0),
        _picked('/two.png', 1),
      ]);
      await _until(() => service.requests.isNotEmpty);
      prepared = _preparation();
      service.requests.single.result.complete(DataCommandApplied(_image('1')));
      await pending;
      expect(inserted, isEmpty);
      expect(service.requests, hasLength(1));
      expect(media.value.busy, isFalse);
    },
  );

  for (final disposing in [false, true]) {
    test(
      '${disposing ? 'dispose' : 'cancel'} aborts transport and ignores late success',
      () async {
        final media = make();
        if (!disposing) addTearDown(media.dispose);
        final pending = media.pickImages();
        picker.selected.complete([_picked('/one.png', 0)]);
        await _until(() => service.requests.isNotEmpty);
        final request = service.requests.single;
        if (disposing) {
          media.dispose();
        } else {
          media.cancel();
        }
        expect(request.input.cancellation!.isCancelled, isTrue);
        request.input.onProgress!(0.5);
        request.result.complete(DataCommandApplied(_image('1')));
        await pending;
        expect(inserted, isEmpty);
        expect(media.uploadedImages, isEmpty);
        expect(files.file('/one.png').existsSync(), isTrue);
      },
    );
  }

  test('unknown upload outcomes stop the batch and are not replayed', () async {
    final media = make();
    addTearDown(media.dispose);
    final pending = media.pickImages();
    picker.selected.complete([_picked('/one.png', 0), _picked('/two.png', 1)]);
    await _until(() => service.requests.isNotEmpty);
    service.requests.single.result.complete(
      const DataCommandOutcomeUnknown(_unknown),
    );
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(service.requests, hasLength(1));
    expect(media.value.failure, same(_unknown));
    expect(media.value.outcomeUnknown, isTrue);
    expect(media.uploadedImages, isEmpty);
    expect(inserted, isEmpty);
    expect(media.value.busy, isFalse);
  });

  test(
    'a later failure retains earlier confirmed images without retrying them',
    () async {
      final media = make();
      addTearDown(media.dispose);
      final pending = media.pickImages();
      picker.selected.complete([
        _picked('/one.png', 0),
        _picked('/two.png', 1),
      ]);
      await _until(() => service.requests.length == 1);
      final first = _image('1');
      service.requests.first.result.complete(DataCommandApplied(first));
      await _until(() => service.requests.length == 2);
      service.requests.last.result.complete(
        const DataCommandRejected(_rejected),
      );
      await pending;
      expect(service.requests, hasLength(2));
      expect(media.uploadedImages, [first]);
      expect(inserted, [(first, '/one.png')]);
      expect(media.value.failure, same(_rejected));
      expect(media.value.outcomeUnknown, isFalse);
      expect(media.value.busy, isFalse);
    },
  );

  test(
    'unexpected transport errors remain unknown without exposing payloads',
    () async {
      final media = make();
      addTearDown(media.dispose);
      final pending = media.pickImages();
      picker.selected.complete([_picked('/one.png', 0)]);
      await _until(() => service.requests.isNotEmpty);
      service.requests.single.result.completeError(
        StateError('private server payload'),
      );
      await pending;
      expect(media.value.failure!.retryPolicy, DataCommandRetryPolicy.never);
      expect(media.value.outcomeUnknown, isTrue);
      expect(
        media.value.failure!.diagnosticMessage,
        isNot(contains('private')),
      );
      expect(inserted, isEmpty);
    },
  );
}

Future<void> _until(bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue, reason: 'Expected fixture operation to start');
}

ComposerPickedImage _picked(String path, int order) => ComposerPickedImage(
  path: path,
  fileName: path.split('/').last,
  mimeType: 'image/png',
  originalIndex: order,
);

final class _Picker implements ComposerImagePicker {
  final selected = Completer<List<ComposerPickedImage>>();
  int calls = 0;

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() {
    calls++;
    return selected.future;
  }
}

final class _MediaService implements UserBlogMediaOperations {
  final requests =
      <
        ({
          UserBlogImageUploadSubmission input,
          Completer<DataCommandResult<UserBlogUploadedImage>> result,
        })
      >[];

  @override
  Future<DataCommandResult<UserBlogUploadedImage>> uploadImage(
    UserBlogImageUploadSubmission submission,
  ) {
    final result = Completer<DataCommandResult<UserBlogUploadedImage>>();
    requests.add((input: submission, result: result));
    return result.future;
  }
}

UserBlogEditorPreparation _preparation({bool canUpload = true}) =>
    UserBlogEditorPreparation(
      target: const UserBlogTarget(
        actorUserId: '101',
        ownerUserId: '101',
        action: UserBlogAction.create,
      ),
      token: _EditorToken(),
      subject: '',
      bodyHtml: '',
      tags: '',
      siteCategories: const [],
      personalCategories: const [],
      siteCategoryId: '0',
      personalCategoryId: '0',
      siteCategoryRequired: false,
      canCreateCategory: false,
      canPublishFeed: false,
      publishFeed: false,
      visibility: UserBlogVisibility.public,
      commentsEnabled: true,
      imageUploadLimits: canUpload
          ? const UserBlogImageUploadLimits(
              extensionRules: [
                ForumImageAttachmentExtensionRule(extension: 'png'),
              ],
            )
          : null,
    );

UserBlogUploadedImage _image(String id) => UserBlogUploadedImage(
  picId: id,
  imageUri: Uri.parse('https://example.test/album/$id.png.thumb.jpg'),
  originalImageUri: Uri.parse('https://example.test/album/$id.png'),
  token: _ImageToken(),
);

final class _EditorToken implements UserBlogOperationToken {}

final class _ImageToken implements UserBlogUploadedImageToken {}

const _unknown = DataCommandFailure(
  kind: DataCommandFailureKind.network,
  retryPolicy: DataCommandRetryPolicy.never,
  diagnosticMessage: 'upload_unconfirmed',
);
const _rejected = DataCommandFailure(
  kind: DataCommandFailureKind.permissionDenied,
  retryPolicy: DataCommandRetryPolicy.afterSessionRefresh,
  diagnosticMessage: 'upload_rejected',
);
