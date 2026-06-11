import 'dart:async';

import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/composer_attachment_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

enum ComposerImageUploadEventType {
  started,
  progress,
  uploaded,
  failed,
  completed,
}

class ComposerImageUploadEvent {
  const ComposerImageUploadEvent._({
    required this.type,
    required this.localId,
    required this.current,
    required this.total,
    this.progress,
    this.uploadedImage,
    this.errorMessage,
  });

  const ComposerImageUploadEvent.started({
    required String localId,
    required int current,
    required int total,
  }) : this._(
          type: ComposerImageUploadEventType.started,
          localId: localId,
          current: current,
          total: total,
        );

  const ComposerImageUploadEvent.progress({
    required String localId,
    required int current,
    required int total,
    required double progress,
  }) : this._(
          type: ComposerImageUploadEventType.progress,
          localId: localId,
          current: current,
          total: total,
          progress: progress,
        );

  const ComposerImageUploadEvent.uploaded({
    required String localId,
    required int current,
    required int total,
    required ComposerUploadedImage uploadedImage,
  }) : this._(
          type: ComposerImageUploadEventType.uploaded,
          localId: localId,
          current: current,
          total: total,
          uploadedImage: uploadedImage,
        );

  const ComposerImageUploadEvent.failed({
    required String localId,
    required int current,
    required int total,
    required String errorMessage,
  }) : this._(
          type: ComposerImageUploadEventType.failed,
          localId: localId,
          current: current,
          total: total,
          errorMessage: errorMessage,
        );

  const ComposerImageUploadEvent.completed({
    required int total,
  }) : this._(
          type: ComposerImageUploadEventType.completed,
          localId: '',
          current: total,
          total: total,
        );

  final ComposerImageUploadEventType type;
  final String localId;
  final int current;
  final int total;
  final double? progress;
  final ComposerUploadedImage? uploadedImage;
  final String? errorMessage;
}

abstract class ComposerImageUploadCoordinator {
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  });

  void cancel();
}

/// 串行上传：保证图片之间相对顺序，避免服务端为同一会话并发触发限流。
class SerialComposerImageUploadCoordinator
    implements ComposerImageUploadCoordinator {
  SerialComposerImageUploadCoordinator({
    required ComposerAttachmentRepository repository,
  }) : _repository = repository;

  final ComposerAttachmentRepository _repository;
  bool _cancelled = false;
  int _runId = 0;

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) {
    _runId += 1;
    final runId = _runId;
    _cancelled = false;
    final controller = StreamController<ComposerImageUploadEvent>();
    controller.onCancel = () {
      if (runId == _runId) {
        cancel();
      }
    };
    unawaited(_runUpload(
      controller: controller,
      fid: fid,
      attachments: attachments,
      runId: runId,
    ));
    return controller.stream;
  }

  Future<void> _runUpload({
    required StreamController<ComposerImageUploadEvent> controller,
    required String fid,
    required List<ComposerImageAttachment> attachments,
    required int runId,
  }) async {
    try {
      final sorted = attachments.toList(growable: false)
        ..sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          if (byOrder != 0) {
            return byOrder;
          }
          return a.localId.compareTo(b.localId);
        });
      final total = sorted.length;
      if (total == 0) {
        controller.add(const ComposerImageUploadEvent.completed(total: 0));
        await controller.close();
        return;
      }

      final permissionResult = await _repository.prepareUpload(fid: fid);
      if (_isCancelled(runId)) {
        await controller.close();
        return;
      }
      if (permissionResult
          case ApiFailure<ComposerImageUploadPermission>(:final error)) {
        for (var index = 0; index < sorted.length; index += 1) {
          if (_isCancelled(runId)) {
            await controller.close();
            return;
          }
          controller.add(ComposerImageUploadEvent.failed(
            localId: sorted[index].localId,
            current: index + 1,
            total: total,
            errorMessage: error.message,
          ));
        }
        controller.add(ComposerImageUploadEvent.completed(total: total));
        await controller.close();
        return;
      }
      final permission =
          (permissionResult as ApiSuccess<ComposerImageUploadPermission>).data;

      for (var index = 0; index < sorted.length; index += 1) {
        if (_isCancelled(runId)) {
          await controller.close();
          return;
        }
        final attachment = sorted[index];
        final current = index + 1;
        controller.add(ComposerImageUploadEvent.started(
          localId: attachment.localId,
          current: current,
          total: total,
        ));
        final result = await _repository.uploadImage(
          fid: fid,
          permission: permission,
          attachment: attachment,
          onProgress: (progress) {
            if (_isCancelled(runId) || controller.isClosed) {
              return;
            }
            controller.add(
              ComposerImageUploadEvent.progress(
                localId: attachment.localId,
                current: current,
                total: total,
                progress: progress,
              ),
            );
          },
        );
        if (_isCancelled(runId)) {
          await controller.close();
          return;
        }
        if (result case ApiSuccess<ComposerUploadedImage>(:final data)) {
          controller.add(ComposerImageUploadEvent.uploaded(
            localId: attachment.localId,
            current: current,
            total: total,
            uploadedImage: data,
          ));
        } else {
          final error = (result as ApiFailure<ComposerUploadedImage>).error;
          controller.add(ComposerImageUploadEvent.failed(
            localId: attachment.localId,
            current: current,
            total: total,
            errorMessage: error.message,
          ));
        }
      }
      if (!_isCancelled(runId)) {
        controller.add(ComposerImageUploadEvent.completed(total: total));
      }
      await controller.close();
    } catch (error) {
      if (!_isCancelled(runId) && !controller.isClosed) {
        controller.addError(error);
        await controller.close();
      }
    }
  }

  @override
  void cancel() {
    _cancelled = true;
  }

  bool _isCancelled(int runId) {
    return _cancelled || runId != _runId;
  }
}
