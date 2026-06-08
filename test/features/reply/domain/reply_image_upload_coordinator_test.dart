import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_image_upload_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_image_upload_coordinator.dart';

void main() {
  group('SerialReplyImageUploadCoordinator', () {
    test('uploads images sequentially by order', () async {
      final repository = _FakeReplyImageUploadRepository(
        aidsByLocalId: const <String, String>{
          'b': '200',
          'a': '100',
        },
      );
      final coordinator = SerialReplyImageUploadCoordinator(
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
            .where((event) => event.type == ReplyImageUploadEventType.uploaded)
            .map((event) => event.uploadedImage?.aid),
        ['100', '200'],
      );
      expect(events.last.type, ReplyImageUploadEventType.completed);
    });

    test('keeps uploading later images when one fails', () async {
      final repository = _FakeReplyImageUploadRepository(
        aidsByLocalId: const <String, String>{'second': '222'},
        failedLocalIds: const {'first'},
      );
      final coordinator = SerialReplyImageUploadCoordinator(
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
          ReplyImageUploadEventType.failed,
          ReplyImageUploadEventType.uploaded,
          ReplyImageUploadEventType.completed,
        ]),
      );
    });

    test('emits progress from repository callback', () async {
      final repository = _FakeReplyImageUploadRepository(
        aidsByLocalId: const <String, String>{'local-1': '123'},
        progressValues: const <double>[0.25, 0.75],
      );
      final coordinator = SerialReplyImageUploadCoordinator(
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
            .where((event) => event.type == ReplyImageUploadEventType.progress)
            .map((event) => event.progress),
        [0.25, 0.75],
      );
    });

    test('prepare failure marks all attachments failed', () async {
      final repository = _FakeReplyImageUploadRepository(
        prepareResult: const ApiFailure<ReplyImageUploadPermission>(
          ApiError(type: ApiErrorType.business, message: '没有上传权限'),
        ),
      );
      final coordinator = SerialReplyImageUploadCoordinator(
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
            .where((event) => event.type == ReplyImageUploadEventType.failed)
            .map((event) => event.localId),
        ['first', 'second'],
      );
    });

    test('cancel stops remaining uploads', () async {
      final firstCompleter = Completer<ApiResult<ReplyUploadedImage>>();
      final repository = _FakeReplyImageUploadRepository(
        asyncResults: <String, Future<ApiResult<ReplyUploadedImage>>>{
          'first': firstCompleter.future,
        },
      );
      final coordinator = SerialReplyImageUploadCoordinator(
        repository: repository,
      );
      final events = <ReplyImageUploadEvent>[];
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
        ApiSuccess<ReplyUploadedImage>(
          ReplyUploadedImage(
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

ReplyImageAttachment _attachment({
  required String localId,
  required int order,
}) {
  return ReplyImageAttachment(
    localId: localId,
    localPath: '/gallery/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: order,
    status: ReplyImageAttachmentStatus.local,
  );
}

class _FakeReplyImageUploadRepository implements ReplyImageUploadRepository {
  _FakeReplyImageUploadRepository({
    this.prepareResult = const ApiSuccess<ReplyImageUploadPermission>(
      ReplyImageUploadPermission(
        uid: '597454',
        uploadHash: 'hash',
        allowedExtensions: {'jpg'},
        attachRemain: ReplyAttachRemain(size: -1, count: -1),
      ),
    ),
    this.aidsByLocalId = const <String, String>{},
    this.failedLocalIds = const <String>{},
    this.progressValues = const <double>[],
    this.asyncResults = const <String, Future<ApiResult<ReplyUploadedImage>>>{},
  });

  final ApiResult<ReplyImageUploadPermission> prepareResult;
  final Map<String, String> aidsByLocalId;
  final Set<String> failedLocalIds;
  final List<double> progressValues;
  final Map<String, Future<ApiResult<ReplyUploadedImage>>> asyncResults;
  final List<String> uploadedLocalIds = <String>[];

  @override
  Future<ApiResult<ReplyImageUploadPermission>> prepareUpload({
    required String fid,
  }) async {
    return prepareResult;
  }

  @override
  Future<ApiResult<ReplyUploadedImage>> uploadImage({
    required String fid,
    required ReplyImageUploadPermission permission,
    required ReplyImageAttachment attachment,
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
      return const ApiFailure<ReplyUploadedImage>(
        ApiError(type: ApiErrorType.business, message: '上传失败'),
      );
    }
    return ApiSuccess<ReplyUploadedImage>(
      ReplyUploadedImage(
        localId: attachment.localId,
        aid: aidsByLocalId[attachment.localId] ?? attachment.localId,
        uploadedAt: DateTime.utc(2026, 6, 8),
      ),
    );
  }
}
