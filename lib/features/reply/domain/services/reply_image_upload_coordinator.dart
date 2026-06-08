import 'dart:async';

import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_image_upload_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

enum ReplyImageUploadEventType {
  started,
  progress,
  uploaded,
  failed,
  completed,
}

class ReplyImageUploadEvent {
  const ReplyImageUploadEvent._({
    required this.type,
    required this.localId,
    required this.current,
    required this.total,
    this.progress,
    this.uploadedImage,
    this.errorMessage,
  });

  const ReplyImageUploadEvent.started({
    required String localId,
    required int current,
    required int total,
  }) : this._(
          type: ReplyImageUploadEventType.started,
          localId: localId,
          current: current,
          total: total,
        );

  const ReplyImageUploadEvent.progress({
    required String localId,
    required int current,
    required int total,
    required double progress,
  }) : this._(
          type: ReplyImageUploadEventType.progress,
          localId: localId,
          current: current,
          total: total,
          progress: progress,
        );

  const ReplyImageUploadEvent.uploaded({
    required String localId,
    required int current,
    required int total,
    required ReplyUploadedImage uploadedImage,
  }) : this._(
          type: ReplyImageUploadEventType.uploaded,
          localId: localId,
          current: current,
          total: total,
          uploadedImage: uploadedImage,
        );

  const ReplyImageUploadEvent.failed({
    required String localId,
    required int current,
    required int total,
    required String errorMessage,
  }) : this._(
          type: ReplyImageUploadEventType.failed,
          localId: localId,
          current: current,
          total: total,
          errorMessage: errorMessage,
        );

  const ReplyImageUploadEvent.completed({
    required int total,
  }) : this._(
          type: ReplyImageUploadEventType.completed,
          localId: '',
          current: total,
          total: total,
        );

  final ReplyImageUploadEventType type;
  final String localId;
  final int current;
  final int total;
  final double? progress;
  final ReplyUploadedImage? uploadedImage;
  final String? errorMessage;
}

abstract class ReplyImageUploadCoordinator {
  Stream<ReplyImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ReplyImageAttachment> attachments,
  });

  void cancel();
}

class SerialReplyImageUploadCoordinator implements ReplyImageUploadCoordinator {
  SerialReplyImageUploadCoordinator({
    required ReplyImageUploadRepository repository,
  }) : _repository = repository;

  final ReplyImageUploadRepository _repository;
  bool _cancelled = false;
  int _runId = 0;

  @override
  Stream<ReplyImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ReplyImageAttachment> attachments,
  }) {
    _runId += 1;
    final runId = _runId;
    _cancelled = false;
    final controller = StreamController<ReplyImageUploadEvent>();
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
    required StreamController<ReplyImageUploadEvent> controller,
    required String fid,
    required List<ReplyImageAttachment> attachments,
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
        controller.add(const ReplyImageUploadEvent.completed(total: 0));
        await controller.close();
        return;
      }

      final permissionResult = await _repository.prepareUpload(fid: fid);
      if (_isCancelled(runId)) {
        await controller.close();
        return;
      }
      if (permissionResult
          case ApiFailure<ReplyImageUploadPermission>(:final error)) {
        for (var index = 0; index < sorted.length; index += 1) {
          if (_isCancelled(runId)) {
            await controller.close();
            return;
          }
          controller.add(ReplyImageUploadEvent.failed(
            localId: sorted[index].localId,
            current: index + 1,
            total: total,
            errorMessage: error.message,
          ));
        }
        controller.add(ReplyImageUploadEvent.completed(total: total));
        await controller.close();
        return;
      }
      final permission =
          (permissionResult as ApiSuccess<ReplyImageUploadPermission>).data;

      for (var index = 0; index < sorted.length; index += 1) {
        if (_isCancelled(runId)) {
          await controller.close();
          return;
        }
        final attachment = sorted[index];
        final current = index + 1;
        controller.add(ReplyImageUploadEvent.started(
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
              ReplyImageUploadEvent.progress(
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
        if (result case ApiSuccess<ReplyUploadedImage>(:final data)) {
          controller.add(ReplyImageUploadEvent.uploaded(
            localId: attachment.localId,
            current: current,
            total: total,
            uploadedImage: data,
          ));
        } else {
          final error = (result as ApiFailure<ReplyUploadedImage>).error;
          controller.add(ReplyImageUploadEvent.failed(
            localId: attachment.localId,
            current: current,
            total: total,
            errorMessage: error.message,
          ));
        }
      }
      if (!_isCancelled(runId)) {
        controller.add(ReplyImageUploadEvent.completed(total: total));
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
