import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';

void main() {
  group('SerialComposerImageUploadCoordinator', () {
    test('uploads images sequentially by order', () async {
      final repository = _FakeComposerAttachmentRepository(
        aidsByLocalId: const <String, String>{
          'b': '200',
          'a': '100',
        },
      );
      final coordinator = SerialComposerImageUploadCoordinator(
        repository: repository,
      );

      final events = await coordinator
          .uploadInOrder(
            fid: '33',
            attachments: [
              _attachment(localId: 'b', order: 1),
              _attachment(localId: 'a', order: 0),
            ],
          )
          .toList();

      expect(repository.uploadedLocalIds, ['a', 'b']);
      expect(
        events
            .where((event) =>
                event.type == ComposerImageUploadEventType.uploaded)
            .map((event) => event.uploadedImage?.aid),
        ['100', '200'],
      );
      expect(events.last.type, ComposerImageUploadEventType.completed);
    });

    test('keeps uploading later images when one fails', () async {
      final repository = _FakeComposerAttachmentRepository(
        aidsByLocalId: const <String, String>{'second': '222'},
        failedLocalIds: const {'first'},
      );
      final coordinator = SerialComposerImageUploadCoordinator(
        repository: repository,
      );

      final events = await coordinator
          .uploadInOrder(
            fid: '33',
            attachments: [
              _attachment(localId: 'first', order: 0),
              _attachment(localId: 'second', order: 1),
            ],
          )
          .toList();

      expect(repository.uploadedLocalIds, ['first', 'second']);
      expect(
        events.map((event) => event.type),
        containsAllInOrder([
          ComposerImageUploadEventType.failed,
          ComposerImageUploadEventType.uploaded,
          ComposerImageUploadEventType.completed,
        ]),
      );
    });

    test('emits progress from repository callback', () async {
      final repository = _FakeComposerAttachmentRepository(
        aidsByLocalId: const <String, String>{'local-1': '123'},
        progressValues: const <double>[0.25, 0.75],
      );
      final coordinator = SerialComposerImageUploadCoordinator(
        repository: repository,
      );

      final events = await coordinator
          .uploadInOrder(
            fid: '33',
            attachments: [_attachment(localId: 'local-1', order: 0)],
          )
          .toList();

      expect(
        events
            .where((event) =>
                event.type == ComposerImageUploadEventType.progress)
            .map((event) => event.progress),
        [0.25, 0.75],
      );
    });

    test('prepare failure marks all attachments failed', () async {
      final repository = _FakeComposerAttachmentRepository(
        prepareResult: const ApiFailure<ComposerImageUploadPermission>(
          ApiError(type: ApiErrorType.business, message: '没有上传权限'),
        ),
      );
      final coordinator = SerialComposerImageUploadCoordinator(
        repository: repository,
      );

      final events = await coordinator
          .uploadInOrder(
            fid: '33',
            attachments: [
              _attachment(localId: 'first', order: 0),
              _attachment(localId: 'second', order: 1),
            ],
          )
          .toList();

      expect(repository.uploadedLocalIds, isEmpty);
      expect(
        events
            .where((event) =>
                event.type == ComposerImageUploadEventType.failed)
            .map((event) => event.localId),
        ['first', 'second'],
      );
    });

    test('cancel stops remaining uploads', () async {
      final firstCompleter = Completer<ApiResult<ComposerUploadedImage>>();
      final repository = _FakeComposerAttachmentRepository(
        asyncResults: <String, Future<ApiResult<ComposerUploadedImage>>>{
          'first': firstCompleter.future,
        },
      );
      final coordinator = SerialComposerImageUploadCoordinator(
        repository: repository,
      );
      final events = <ComposerImageUploadEvent>[];
      final subscription = coordinator
          .uploadInOrder(
            fid: '33',
            attachments: [
              _attachment(localId: 'first', order: 0),
              _attachment(localId: 'second', order: 1),
            ],
          )
          .listen(events.add);

      await Future<void>.delayed(Duration.zero);
      coordinator.cancel();
      firstCompleter.complete(
        ApiSuccess<ComposerUploadedImage>(
          ComposerUploadedImage(
            localId: 'first',
            aid: '111',
            uploadedAt: DateTime.utc(2026, 6, 8),
          ),
        ),
      );
      await subscription.asFuture<void>();

      expect(repository.uploadedLocalIds, ['first']);
      expect(
        events.any((event) => event.localId == 'second'),
        isFalse,
      );
    });
  });
}

ComposerImageAttachment _attachment({
  required String localId,
  required int order,
}) {
  return ComposerImageAttachment(
    localId: localId,
    localPath: '/gallery/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: order,
    status: ComposerImageAttachmentStatus.local,
  );
}

class _FakeComposerAttachmentRepository implements ComposerAttachmentRepository {
  _FakeComposerAttachmentRepository({
    this.prepareResult = const ApiSuccess<ComposerImageUploadPermission>(
      ComposerImageUploadPermission(
        uid: '597454',
        uploadHash: 'hash',
        allowedExtensions: {'jpg'},
        attachRemain: ComposerAttachRemain(size: -1, count: -1),
      ),
    ),
    this.aidsByLocalId = const <String, String>{},
    this.failedLocalIds = const <String>{},
    this.progressValues = const <double>[],
    this.asyncResults =
        const <String, Future<ApiResult<ComposerUploadedImage>>>{},
  });

  final ApiResult<ComposerImageUploadPermission> prepareResult;
  final Map<String, String> aidsByLocalId;
  final Set<String> failedLocalIds;
  final List<double> progressValues;
  final Map<String, Future<ApiResult<ComposerUploadedImage>>> asyncResults;
  final List<String> uploadedLocalIds = <String>[];

  @override
  Future<ApiResult<ComposerImageUploadPermission>> prepareUpload({
    required String fid,
  }) async {
    return prepareResult;
  }

  @override
  Future<ApiResult<ComposerUploadedImage>> uploadImage({
    required String fid,
    required ComposerImageUploadPermission permission,
    required ComposerImageAttachment attachment,
    void Function(double progress)? onProgress,
  }) async {
    uploadedLocalIds.add(attachment.localId);
    final asyncResult = asyncResults[attachment.localId];
    if (asyncResult != null) {
      return asyncResult;
    }
    for (final progress in progressValues) {
      onProgress?.call(progress);
    }
    if (failedLocalIds.contains(attachment.localId)) {
      return const ApiFailure<ComposerUploadedImage>(
        ApiError(type: ApiErrorType.business, message: '上传失败'),
      );
    }
    return ApiSuccess<ComposerUploadedImage>(
      ComposerUploadedImage(
        localId: attachment.localId,
        aid: aidsByLocalId[attachment.localId] ?? attachment.localId,
        uploadedAt: DateTime.utc(2026, 6, 8),
      ),
    );
  }
}
