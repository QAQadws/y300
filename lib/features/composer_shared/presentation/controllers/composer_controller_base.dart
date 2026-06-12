import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/data/composer_upload_notification_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_editor_mode.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';

/// 编辑器（回复 / 发帖）共用的模板方法基类。
///
/// 这里集中处理通用流程：
/// - 草稿 prune / 恢复 / 防抖落盘 / 显式 flush / 显式 discard
/// - 图片选择 + 串行上传事件流分发（含通知栏进度）
/// - submit 调度：sanitize 过期附件 → preflight 校验 → 子类 performSubmit
///   → 成功删草稿、失败保留草稿
///
/// 子类只需要：
/// 1) 提供 `draftIdentity` / `uploadFid`（或后续阶段引入的 ComposerScope）。
/// 2) 在 `buildInitialState` 中根据恢复出的草稿构造自己的初始状态。
/// 3) 在 `applyPatch` 中把基类下发的 [ComposerStatePatch] 合并到自己的 state 上。
/// 4) 在 `performSubmit` 中调用业务侧 repository 完成提交。
abstract class ComposerControllerBase<TState extends ComposerStateBase>
    extends AsyncNotifier<TState> {
  ComposerControllerBase();

  static const Duration defaultSaveDebounce = Duration(milliseconds: 700);

  Duration get saveDebounce => defaultSaveDebounce;

  // ── 子类必须实现 ─────────────────────────────────────────────
  ComposerDraftIdentity get draftIdentity;
  String get uploadFid;

  /// 由子类根据恢复出的草稿（可能为 null）构造初始 state。
  Future<TState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
  });

  /// 把基类生成的 patch 合并进具体 state。
  TState applyPatch(TState current, ComposerStatePatch patch);

  /// 子类在提交前做业务校验。
  ///
  /// 返回 null 表示通过；返回非空字符串表示失败，基类会把它写入
  /// `errorMessage` 并直接返回 not-sent，**不会**调用 [performSubmit]。
  String? preflightValidate(TState state) {
    if (state.message.trim().isEmpty) {
      return '请输入内容';
    }
    return null;
  }

  /// 子类负责真正的网络提交。
  /// `uploadedAids` 已经经过 message 与附件双重校验，可直接进入 payload。
  Future<ComposerSubmissionOutcome> performSubmit({
    required TState state,
    required List<String> uploadedAids,
  });

  // ── 基类内部状态 ─────────────────────────────────────────────
  Timer? _saveTimer;
  ComposerDraftRepository? _draftRepository;
  ComposerImagePicker? _imagePicker;
  ComposerImageUploadCoordinator? _imageUploadCoordinator;
  ComposerUploadNotificationService? _uploadNotificationService;
  ComposerAttachBbCodeService? _attachBbCodeService;
  final ComposerDraftAttachmentSanitizer _draftAttachmentSanitizer =
      const ComposerDraftAttachmentSanitizer();
  TState? _latestState;
  StreamSubscription<ComposerImageUploadEvent>? _imageUploadSubscription;
  Set<String> _activeUploadLocalIds = const <String>{};

  TState? get latestState => _latestState;
  ComposerAttachBbCodeService get attachBbCodeService =>
      _attachBbCodeService ?? const ComposerAttachBbCodeService();

  @override
  FutureOr<TState> build() async {
    _draftRepository = ref.read(composerDraftRepositoryProvider);
    _imagePicker = ref.read(composerImagePickerProvider);
    _imageUploadCoordinator = ref.read(composerImageUploadCoordinatorProvider);
    _uploadNotificationService =
        ref.read(composerUploadNotificationServiceProvider);
    _attachBbCodeService = ref.read(composerAttachBbCodeServiceProvider);

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
    final snapshot = await _draftRepository!.loadDraft(draftIdentity);
    final initial = await buildInitialState(
      restoredDraft: snapshot != null && !snapshot.isEmpty ? snapshot : null,
    );
    _latestState = initial;
    onAfterBuild(initial);
    return initial;
  }

  /// 子类钩子：基类构造完成、`_latestState` 已经写入之后调用，
  /// 用来在确保 state 不为空时 schedule 业务侧的后续异步流程
  /// （例如 reply 的楼层引用准备）。默认 no-op。
  void onAfterBuild(TState initial) {}

  /// 子类钩子：草稿落盘时把当前 state 中的"标题"返回。
  /// reply 一直是空字符串；posting 返回主题标题。
  String draftSubjectFor(TState value) => '';

  /// 子类钩子：草稿落盘时把当前 state 中的"额外 KV"返回。
  /// reply 一直是空 map；posting 把 typeid / 选项等放进去。
  Map<String, String> draftExtrasFor(TState value) =>
      const <String, String>{};

  /// 子类钩子：提交成功后基类已经清空 message / 附件，子类可以在此把
  /// 业务专属字段（如发帖标题、所选分类）也重置到"空白"。默认 no-op。
  TState resetAfterSuccess(TState value) => value;


  // ── 通用 mutators ─────────────────────────────────────────────
  void updateMessage(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _setDataState(applyPatch(
      current,
      ComposerStatePatch(message: value, clearErrorMessage: true),
    ));
    _scheduleDraftSave();
  }

  void toggleUseSignature(bool value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _setDataState(applyPatch(
      current,
      ComposerStatePatch(useSignature: value, clearErrorMessage: true),
    ));
    _scheduleDraftSave();
  }

  void switchMode(ComposerEditorMode mode) {
    final current = state.value;
    if (current == null || current.mode == mode) {
      return;
    }
    _setDataState(applyPatch(current, ComposerStatePatch(mode: mode)));
  }

  // ── 草稿持久化 ───────────────────────────────────────────────
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
    await _draftRepository?.deleteDraft(draftIdentity);
  }

  void _scheduleDraftSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, () {
      unawaited(flushDraft());
    });
  }

  Future<void> scheduleDraftSave() async {
    _scheduleDraftSave();
  }

  Future<void> _pruneDraftsIfNeeded() async {
    try {
      await _draftRepository?.pruneDrafts();
    } catch (_) {
      // 草稿清理失败不阻断编辑器加载，后续保存会继续覆盖当前草稿。
    }
  }

  Future<void> _saveSnapshot(TState value) async {
    try {
      await _draftRepository?.saveDraft(
        ComposerDraftSnapshot(
          identity: draftIdentity,
          message: value.message,
          subject: draftSubjectFor(value),
          extras: draftExtrasFor(value),
          useSignature: value.useSignature,
          updatedAt: DateTime.now(),
          imageAttachments: value.imageAttachments,
        ),
      );
    } catch (_) {
      // 草稿保存失败不阻断编辑或发送，用户仍可继续完成当前编辑。
    }
  }

  // ── 图片选择 + 上传事件分发 ──────────────────────────────────
  /// 子类可覆盖来追加业务侧的"暂时不能选图"判断（如 reply 楼层引用准备中）。
  bool canPickImages(TState state) {
    return !state.isSubmitting && !state.isUploadingImages;
  }

  Future<void> pickImages() async {
    final current = state.value;
    if (current == null || !canPickImages(current)) {
      return;
    }

    try {
      final pickedImages = await _imagePicker!.pickImagesInOrder();
      if (pickedImages.isEmpty) {
        return;
      }
      final latest = state.value ?? current;
      if (!canPickImages(latest)) {
        return;
      }
      final baseTime = DateTime.now().microsecondsSinceEpoch;
      final existingCount = latest.imageAttachments.length;
      final sortedPickedImages = pickedImages.toList(growable: false)
        ..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
      final attachments = <ComposerImageAttachment>[
        ...latest.imageAttachments,
        for (var index = 0; index < sortedPickedImages.length; index += 1)
          ComposerImageAttachment(
            localId: 'picked-$baseTime-${existingCount + index}',
            localPath: sortedPickedImages[index].path,
            fileName: sortedPickedImages[index].fileName,
            mimeType: sortedPickedImages[index].mimeType,
            order: existingCount + index,
            status: ComposerImageAttachmentStatus.local,
          ),
      ];
      _setDataState(applyPatch(
        latest,
        ComposerStatePatch(
          imageAttachments: attachments,
          isUploadingImages: true,
          imageUploadCurrent: 0,
          imageUploadTotal: sortedPickedImages.length,
          clearImageUploadError: true,
        ),
      ));
      _startImageUpload(
        attachments.skip(existingCount).toList(growable: false),
      );
    } on ComposerImagePickerException catch (_) {
      final latest = state.value ?? current;
      _setDataState(applyPatch(
        latest,
        const ComposerStatePatch(imageUploadError: '选择图片失败，请重试'),
      ));
    }
  }

  void _startImageUpload(List<ComposerImageAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    unawaited(_imageUploadSubscription?.cancel());
    _activeUploadLocalIds = attachments
        .map((attachment) => attachment.localId)
        .toSet();
    final stream = _imageUploadCoordinator!.uploadInOrder(
      fid: uploadFid,
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
        _setDataState(applyPatch(
          current,
          const ComposerStatePatch(
            isUploadingImages: false,
            imageUploadError: '图片上传失败，请重试',
          ),
        ));
      },
    );
  }

  void _handleImageUploadEvent(ComposerImageUploadEvent event) {
    final current = state.value ?? _latestState;
    if (current == null) {
      return;
    }
    switch (event.type) {
      case ComposerImageUploadEventType.started:
        _setDataState(applyPatch(
          current,
          ComposerStatePatch(
            imageAttachments: _replaceAttachmentStatus(
              current.imageAttachments,
              localId: event.localId,
              status: ComposerImageAttachmentStatus.uploading,
            ),
            isUploadingImages: true,
            imageUploadCurrent: event.current,
            imageUploadTotal: event.total,
          ),
        ));
        unawaited(_uploadNotificationService?.showProgress(
          current: event.current,
          total: event.total,
        ));
        break;
      case ComposerImageUploadEventType.progress:
        _setDataState(applyPatch(
          current,
          ComposerStatePatch(
            isUploadingImages: true,
            imageUploadCurrent: event.current,
            imageUploadTotal: event.total,
          ),
        ));
        unawaited(_uploadNotificationService?.showProgress(
          current: event.current,
          total: event.total,
        ));
        break;
      case ComposerImageUploadEventType.uploaded:
        final uploadedImage = event.uploadedImage;
        if (uploadedImage == null) {
          return;
        }
        final nextMessage = attachBbCodeService.appendAttachCodes(
          current.message,
          [uploadedImage.aid],
        );
        _setDataState(applyPatch(
          current,
          ComposerStatePatch(
            message: nextMessage,
            imageAttachments: _replaceAttachmentStatus(
              current.imageAttachments,
              localId: event.localId,
              status: ComposerImageAttachmentStatus.uploaded,
              aid: uploadedImage.aid,
              uploadedAt: uploadedImage.uploadedAt,
              clearErrorMessage: true,
            ),
            isUploadingImages: true,
            imageUploadCurrent: event.current,
            imageUploadTotal: event.total,
          ),
        ));
        _scheduleDraftSave();
        unawaited(_uploadNotificationService?.showProgress(
          current: event.current,
          total: event.total,
        ));
        break;
      case ComposerImageUploadEventType.failed:
        _setDataState(applyPatch(
          current,
          ComposerStatePatch(
            imageAttachments: _replaceAttachmentStatus(
              current.imageAttachments,
              localId: event.localId,
              status: ComposerImageAttachmentStatus.failed,
              errorMessage: event.errorMessage ?? '图片上传失败',
            ),
            isUploadingImages: true,
            imageUploadCurrent: event.current,
            imageUploadTotal: event.total,
            imageUploadError: event.errorMessage ?? '图片上传失败，请重试',
          ),
        ));
        break;
      case ComposerImageUploadEventType.completed:
        final failedCount = (state.value ?? current)
            .imageAttachments
            .where(
              (attachment) =>
                  _activeUploadLocalIds.contains(attachment.localId) &&
                  attachment.status == ComposerImageAttachmentStatus.failed,
            )
            .length;
        _activeUploadLocalIds = const <String>{};
        _setDataState(applyPatch(
          current,
          ComposerStatePatch(
            isUploadingImages: false,
            imageUploadCurrent: event.total,
            imageUploadTotal: event.total,
          ),
        ));
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

  List<ComposerImageAttachment> _replaceAttachmentStatus(
    List<ComposerImageAttachment> attachments, {
    required String localId,
    required ComposerImageAttachmentStatus status,
    String? aid,
    DateTime? uploadedAt,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return [
      for (final attachment in attachments)
        if (attachment.localId == localId)
          ComposerImageAttachment(
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

  // ── 提交调度 ────────────────────────────────────────────────
  Future<ComposerSubmitInvocationResult> submit() async {
    final stateValue = state.value;
    if (stateValue == null || stateValue.isSubmitting) {
      return const ComposerSubmitInvocationResult.notSent();
    }
    _saveTimer?.cancel();
    _saveTimer = null;

    final marked = applyPatch(
      stateValue,
      const ComposerStatePatch(
        isSubmitting: true,
        clearErrorMessage: true,
      ),
    );
    _setDataState(marked);

    final sanitized = await _sanitizeBeforeSubmit(marked);

    final preflight = preflightValidate(sanitized);
    if (preflight != null) {
      _setDataState(applyPatch(
        sanitized,
        ComposerStatePatch(isSubmitting: false, errorMessage: preflight),
      ));
      return ComposerSubmitInvocationResult.notSent(message: preflight);
    }

    final uploadedAids = _resolveUploadedAttachmentAids(sanitized);

    final outcome = await performSubmit(
      state: sanitized,
      uploadedAids: uploadedAids,
    );
    final afterSubmit = state.value ?? sanitized;

    if (outcome.success) {
      await discardDraft();
      final reset = applyPatch(
        afterSubmit,
        ComposerStatePatch(
          isSubmitting: false,
          message: '',
          imageAttachments: const <ComposerImageAttachment>[],
          clearErrorMessage: true,
        ),
      );
      _setDataState(resetAfterSuccess(reset));
      return ComposerSubmitInvocationResult.sent(
        outcome.successMessage ?? '',
      );
    }

    final errorMessage = outcome.errorMessage ?? '';
    final failed = applyPatch(
      afterSubmit,
      ComposerStatePatch(
        isSubmitting: false,
        errorMessage: errorMessage,
      ),
    );
    _setDataState(failed);
    await _saveSnapshot(failed);
    return ComposerSubmitInvocationResult.notSent(message: errorMessage);
  }

  Future<TState> _sanitizeBeforeSubmit(TState current) async {
    final result = _draftAttachmentSanitizer.sanitize(
      message: current.message,
      imageAttachments: current.imageAttachments,
      now: DateTime.now(),
    );
    if (!result.changed) {
      return current;
    }
    final sanitized = applyPatch(
      current,
      ComposerStatePatch(
        message: result.message,
        imageAttachments: result.imageAttachments,
        clearImageUploadError: true,
      ),
    );
    _setDataState(sanitized);
    await _saveSnapshot(sanitized);
    return sanitized;
  }

  /// 把 message 中残留的 `[attach]aid[/attach]` 与已上传附件双向交集，
  /// 取出最终能进入提交载荷的 aid 列表，按 message 中出现顺序排序。
  List<String> _resolveUploadedAttachmentAids(TState current) {
    final service = attachBbCodeService;
    final validAids = <String>{
      for (final attachment in current.imageAttachments)
        if (attachment.canEnterSubmitPayload) attachment.aid!.trim(),
    };
    if (validAids.isEmpty) {
      return const <String>[];
    }
    final seen = <String>{};
    final resolved = <String>[];
    for (final aid in service.extractAttachAids(current.message)) {
      if (!validAids.contains(aid) || !seen.add(aid)) {
        continue;
      }
      resolved.add(aid);
    }
    return resolved;
  }

  // ── 内部 ─────────────────────────────────────────────────────
  /// 子类直接写 state 的入口（被业务专属字段更新使用，例如 reply 的 preparation）。
  ///
  /// 该方法同步刷新 `_latestState`，确保 `flushDraft` / dispose 时落盘的是最新值。
  /// 名义上是 `protected`，外部不应该调用。
  void setStateValue(TState value) {
    _latestState = value;
    state = AsyncData(value);
  }

  void _setDataState(TState value) => setStateValue(value);
}

