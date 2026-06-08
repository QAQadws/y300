import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_image_picker.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/data/reply_upload_notification_service.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_attach_bbcode_service.dart';
import 'package:y300/features/reply/domain/services/reply_image_upload_coordinator.dart';
import 'package:y300/features/reply/domain/services/reply_submission_error_presenter.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

final replyComposerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReplyComposerController, ReplyComposerState, ReplyComposerArgs>(
      (args) => ReplyComposerController(args),
    );

class ReplyComposerController extends AsyncNotifier<ReplyComposerState> {
  ReplyComposerController(this._args);

  static const Duration _saveDebounce = Duration(milliseconds: 700);

  final ReplyComposerArgs _args;
  Timer? _saveTimer;
  ReplyDraftRepository? _draftRepository;
  ReplyRepository? _replyRepository;
  ReplySubmissionErrorPresenter? _errorPresenter;
  ReplyImagePicker? _imagePicker;
  ReplyImageUploadCoordinator? _imageUploadCoordinator;
  ReplyUploadNotificationService? _uploadNotificationService;
  ReplyAttachBbCodeService? _attachBbCodeService;
  ReplyComposerState? _latestState;
  StreamSubscription<ReplyImageUploadEvent>? _imageUploadSubscription;
  Set<String> _activeUploadLocalIds = const <String>{};

  @override
  FutureOr<ReplyComposerState> build() async {
    _draftRepository = ref.read(replyDraftRepositoryProvider);
    _replyRepository = ref.read(replyRepositoryProvider);
    _errorPresenter = ref.read(replySubmissionErrorPresenterProvider);
    _imagePicker = ref.read(replyImagePickerProvider);
    _imageUploadCoordinator = ref.read(replyImageUploadCoordinatorProvider);
    _uploadNotificationService =
        ref.read(replyUploadNotificationServiceProvider);
    _attachBbCodeService = ref.read(replyAttachBbCodeServiceProvider);
    ref.onDispose(() {
      _saveTimer?.cancel();
      _imageUploadCoordinator?.cancel();
      unawaited(_imageUploadSubscription?.cancel());
      final current = _latestState;
      if (current != null) {
        unawaited(_saveSnapshot(current));
      }
    });

    await _pruneDraftsIfNeeded();
    final snapshot = await _draftRepository!.loadDraft(_args.identity);
    final restoredDraft = snapshot != null && !snapshot.isEmpty;
    final initialState = ReplyComposerState.initial(
      target: _args.target,
      message: snapshot?.message ?? '',
      useSignature: snapshot?.useSignature ?? true,
      isPreparing: _shouldPreparePostReply,
      restoredDraft: restoredDraft,
    );
    _latestState = initialState;
    if (_shouldPreparePostReply) {
      unawaited(Future<void>.microtask(_preparePostReply));
    }
    return initialState;
  }

  void updateMessage(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _setDataState(
      current.copyWith(
        message: value,
        clearErrorMessage: true,
      ),
    );
    _scheduleDraftSave();
  }

  void toggleUseSignature(bool value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _setDataState(
      current.copyWith(
        useSignature: value,
        clearErrorMessage: true,
      ),
    );
    _scheduleDraftSave();
  }

  void switchMode(ReplyComposerMode mode) {
    final current = state.value;
    if (current == null || current.mode == mode) {
      return;
    }
    _setDataState(current.copyWith(mode: mode));
  }

  Future<void> retryPreparePostReply() {
    return _preparePostReply();
  }

  Future<void> pickImages() async {
    final current = state.value;
    if (current == null || !current.canPickImages) {
      return;
    }

    try {
      final pickedImages = await _imagePicker!.pickImagesInOrder();
      if (pickedImages.isEmpty) {
        return;
      }
      final latest = state.value ?? current;
      if (!latest.canPickImages) {
        return;
      }
      final baseTime = DateTime.now().microsecondsSinceEpoch;
      final existingCount = latest.imageAttachments.length;
      final sortedPickedImages = pickedImages.toList(growable: false)
        ..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
      final attachments = [
        ...latest.imageAttachments,
        for (var index = 0; index < sortedPickedImages.length; index += 1)
          ReplyImageAttachment(
            localId: 'picked-$baseTime-${existingCount + index}',
            localPath: sortedPickedImages[index].path,
            fileName: sortedPickedImages[index].fileName,
            mimeType: sortedPickedImages[index].mimeType,
            order: existingCount + index,
            status: ReplyImageAttachmentStatus.local,
          ),
      ];
      _setDataState(
        latest.copyWith(
          imageAttachments: attachments,
          isUploadingImages: true,
          imageUploadCurrent: 0,
          imageUploadTotal: sortedPickedImages.length,
          clearImageUploadError: true,
        ),
      );
      _startImageUpload(attachments.skip(existingCount).toList(growable: false));
    } on ReplyImagePickerException catch (_) {
      final latest = state.value ?? current;
      _setDataState(
        latest.copyWith(imageUploadError: '选择图片失败，请重试'),
      );
    }
  }

  void _startImageUpload(List<ReplyImageAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    unawaited(_imageUploadSubscription?.cancel());
    _activeUploadLocalIds = attachments
        .map((attachment) => attachment.localId)
        .toSet();
    final stream = _imageUploadCoordinator!.uploadInOrder(
      fid: _args.target.fid,
      attachments: attachments,
    );
    _imageUploadSubscription = stream.listen(
      _handleImageUploadEvent,
      onError: (Object error, StackTrace stackTrace) {
        final current = state.value ?? _latestState;
        if (current == null) {
          return;
        }
        _activeUploadLocalIds = const <String>{};
        _setDataState(
          current.copyWith(
            isUploadingImages: false,
            imageUploadError: '图片上传失败，请重试',
          ),
        );
      },
    );
  }

  void _handleImageUploadEvent(ReplyImageUploadEvent event) {
    final current = state.value ?? _latestState;
    if (current == null) {
      return;
    }
    switch (event.type) {
      case ReplyImageUploadEventType.started:
        _setDataState(
          current.copyWith(
            imageAttachments: _replaceAttachmentStatus(
              current.imageAttachments,
              localId: event.localId,
              status: ReplyImageAttachmentStatus.uploading,
            ),
            isUploadingImages: true,
            imageUploadCurrent: event.current,
            imageUploadTotal: event.total,
          ),
        );
        unawaited(_uploadNotificationService?.showProgress(
          current: event.current,
          total: event.total,
        ));
        break;
      case ReplyImageUploadEventType.progress:
        _setDataState(
          current.copyWith(
            isUploadingImages: true,
            imageUploadCurrent: event.current,
            imageUploadTotal: event.total,
          ),
        );
        unawaited(_uploadNotificationService?.showProgress(
          current: event.current,
          total: event.total,
        ));
        break;
      case ReplyImageUploadEventType.uploaded:
        final uploadedImage = event.uploadedImage;
        if (uploadedImage == null) {
          return;
        }
        final nextMessage = _attachBbCodeService!.appendAttachCodes(
          current.message,
          [uploadedImage.aid],
        );
        final nextState = current.copyWith(
          message: nextMessage,
          imageAttachments: _replaceAttachmentStatus(
            current.imageAttachments,
            localId: event.localId,
            status: ReplyImageAttachmentStatus.uploaded,
            aid: uploadedImage.aid,
            uploadedAt: uploadedImage.uploadedAt,
            clearErrorMessage: true,
          ),
          isUploadingImages: true,
          imageUploadCurrent: event.current,
          imageUploadTotal: event.total,
        );
        _setDataState(nextState);
        _scheduleDraftSave();
        unawaited(_uploadNotificationService?.showProgress(
          current: event.current,
          total: event.total,
        ));
        break;
      case ReplyImageUploadEventType.failed:
        _setDataState(
          current.copyWith(
            imageAttachments: _replaceAttachmentStatus(
              current.imageAttachments,
              localId: event.localId,
              status: ReplyImageAttachmentStatus.failed,
              errorMessage: event.errorMessage ?? '图片上传失败',
            ),
            isUploadingImages: true,
            imageUploadCurrent: event.current,
            imageUploadTotal: event.total,
            imageUploadError: event.errorMessage ?? '图片上传失败，请重试',
          ),
        );
        break;
      case ReplyImageUploadEventType.completed:
        final failedCount = (state.value ?? current)
            .imageAttachments
            .where(
              (attachment) =>
                  _activeUploadLocalIds.contains(attachment.localId) &&
                  attachment.status == ReplyImageAttachmentStatus.failed,
            )
            .length;
        _activeUploadLocalIds = const <String>{};
        _setDataState(
          current.copyWith(
            isUploadingImages: false,
            imageUploadCurrent: event.total,
            imageUploadTotal: event.total,
          ),
        );
        if (failedCount > 0) {
          unawaited(_uploadNotificationService?.showFailure(
            failedCount: failedCount,
            total: event.total,
          ));
        } else {
          unawaited(_uploadNotificationService?.clear());
        }
        break;
    }
  }

  List<ReplyImageAttachment> _replaceAttachmentStatus(
    List<ReplyImageAttachment> attachments, {
    required String localId,
    required ReplyImageAttachmentStatus status,
    String? aid,
    DateTime? uploadedAt,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return [
      for (final attachment in attachments)
        if (attachment.localId == localId)
          ReplyImageAttachment(
            localId: attachment.localId,
            localPath: attachment.localPath,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            order: attachment.order,
            status: status,
            aid: aid ?? attachment.aid,
            uploadedAt: uploadedAt ?? attachment.uploadedAt,
            errorMessage: clearErrorMessage
                ? null
                : errorMessage ?? attachment.errorMessage,
            cachePath: attachment.cachePath,
          )
        else
          attachment,
    ];
  }

  Future<void> flushDraft() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final current = _latestState;
    if (current == null) {
      return;
    }
    await _saveSnapshot(current);
  }

  Future<void> discardDraft() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _draftRepository?.deleteDraft(_args.identity);
  }

  Future<ReplyComposerResult> submit() async {
    final current = state.value;
    if (current == null || current.isSubmitting) {
      return const ReplyComposerResult(sent: false, message: '');
    }
    final message = current.message.trim();
    if (message.isEmpty) {
      _setDataState(
        current.copyWith(errorMessage: '请输入回复内容'),
      );
      return const ReplyComposerResult(sent: false, message: '请输入回复内容');
    }

    final preparation = current.preparation;
    final missingPostReference =
        current.target.isPostReply &&
        (current.isPreparing || preparation == null);
    if (missingPostReference) {
      _setDataState(
        current.copyWith(errorMessage: '楼层回复引用准备失败，请重试'),
      );
      return const ReplyComposerResult(
        sent: false,
        message: '楼层回复引用准备失败，请重试',
      );
    }

    _saveTimer?.cancel();
    _saveTimer = null;
    _setDataState(
      current.copyWith(
        isSubmitting: true,
        clearErrorMessage: true,
      ),
    );

    final reference = preparation?.reference;
    final result = await _replyRepository!.sendReply(
      draft: ReplyDraft(
        fid: current.target.fid,
        tid: current.target.tid,
        message: message,
        useSignature: current.useSignature,
        formHash: reference?.formHash,
        repPid: reference?.repPid,
        repPost: reference?.repPost,
        noticeAuthor: reference?.noticeAuthor,
        noticeTrimStr: reference?.noticeTrimStr,
        noticeAuthorMsg: reference?.noticeAuthorMsg,
      ),
    );
    final afterSubmit = state.value ?? current;

    if (result case ApiSuccess<ReplySubmissionResult>(:final data)) {
      await discardDraft();
      _setDataState(
        afterSubmit.copyWith(
          isSubmitting: false,
          message: '',
          clearErrorMessage: true,
        ),
      );
      return ReplyComposerResult.sent(
        data.message.isEmpty ? '回复成功' : data.message,
      );
    }

    final error = (result as ApiFailure<ReplySubmissionResult>).error;
    final errorMessage = _errorPresenter?.present(error) ?? error.message;
    _setDataState(
      afterSubmit.copyWith(
        isSubmitting: false,
        errorMessage: errorMessage,
      ),
    );
    await _saveSnapshot(afterSubmit.copyWith(isSubmitting: false));
    return ReplyComposerResult(sent: false, message: errorMessage);
  }

  void _setDataState(ReplyComposerState value) {
    _latestState = value;
    state = AsyncData(value);
  }

  bool get _shouldPreparePostReply {
    return _args.target.isPostReply && _args.replyFormUri != null;
  }

  Future<void> _preparePostReply() async {
    final replyFormUri = _args.replyFormUri;
    if (replyFormUri == null || !_args.target.isPostReply) {
      return;
    }
    final current = state.value ?? _latestState;
    if (current != null) {
      _setDataState(
        current.copyWith(
          isPreparing: true,
          clearPreparation: true,
          clearPreparationError: true,
          clearErrorMessage: true,
        ),
      );
    }

    final result = await _replyRepository!.preparePostReply(
      replyFormUri: replyFormUri,
    );
    final latest = state.value ?? _latestState;
    if (latest == null) {
      return;
    }
    if (result case ApiSuccess<ReplyPreparation>(:final data)) {
      _setDataState(
        latest.copyWith(
          isPreparing: false,
          preparation: data,
          clearPreparationError: true,
        ),
      );
      return;
    }
    final error = (result as ApiFailure<ReplyPreparation>).error;
    _setDataState(
      latest.copyWith(
        isPreparing: false,
        preparationError: error.message,
        errorMessage: error.message,
      ),
    );
  }

  Future<void> _pruneDraftsIfNeeded() async {
    try {
      await _draftRepository?.pruneDrafts();
    } catch (_) {
      // 草稿清理失败不阻断回复页加载，后续保存会继续覆盖当前草稿。
    }
  }

  void _scheduleDraftSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      unawaited(flushDraft());
    });
  }

  Future<void> _saveSnapshot(ReplyComposerState value) async {
    try {
      await _draftRepository?.saveDraft(
        ReplyDraftSnapshot(
          identity: _args.identity,
          message: value.message,
          useSignature: value.useSignature,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // 草稿保存失败不阻断编辑或发送；用户仍可继续完成当前回复。
    }
  }
}
