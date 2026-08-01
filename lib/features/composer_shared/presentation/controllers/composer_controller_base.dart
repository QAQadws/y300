import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_insertion_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_revision_tracker.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';

/// 编辑器（回复 / 发帖）共用的模板方法基类。
///
/// 这里集中处理通用流程：
/// - 草稿 prune / 恢复 / 防抖落盘 / 显式 flush / 显式 discard
/// - 图片选择 + 串行上传事件流分发
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

  /// The business context used for structured submission failures.
  ComposerKind get composerKind => ComposerKind.reply;

  // ── 子类必须实现 ─────────────────────────────────────────────
  ComposerDraftIdentity get draftIdentity;
  String get uploadFid;

  /// 由子类根据恢复出的草稿（可能为 null）构造初始 state。
  Future<TState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
    required ComposerPreferences preferences,
  });

  /// Allows a business controller to reject a persisted draft before it is
  /// projected into its initial state. The default preserves legacy behavior.
  ComposerDraftSnapshot? restoreDraft(ComposerDraftSnapshot? restoredDraft) {
    return restoredDraft;
  }

  /// 把基类生成的 patch 合并进具体 state。
  TState applyPatch(TState current, ComposerStatePatch patch);

  /// 子类在提交前做业务校验。
  ///
  /// Returns a locale-neutral failure and never invokes [performSubmit] when
  /// validation fails.
  ComposerValidationFailure? preflightValidate(TState state) {
    if (state.message.trim().isEmpty) {
      return const ComposerValidationFailure(
        code: ComposerValidationFailureCode.contentRequired,
      );
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
  Future<void> _draftWriteTail = Future<void>.value();
  ComposerDraftRepository? _draftRepository;
  ComposerImagePicker? _imagePicker;
  ComposerImageUploadCoordinator? _imageUploadCoordinator;
  ComposerAttachBbCodeService? _attachBbCodeService;
  final ComposerDraftAttachmentSanitizer _draftAttachmentSanitizer =
      const ComposerDraftAttachmentSanitizer();
  TState? _latestState;
  StreamSubscription<ComposerImageUploadEvent>? _imageUploadSubscription;
  int _uploadGeneration = 0;
  final ComposerMessageInsertionService _messageInsertionService =
      const ComposerMessageInsertionService();
  final ComposerMessageRevisionTracker _messageRevisionTracker =
      ComposerMessageRevisionTracker();
  _ComposerUploadBatch? _activeUploadBatch;

  TState? get latestState => _latestState;
  ComposerAttachBbCodeService get attachBbCodeService =>
      _attachBbCodeService ?? const ComposerAttachBbCodeService();

  @override
  FutureOr<TState> build() async {
    _draftRepository = ref.read(composerDraftRepositoryProvider);
    _imagePicker = ref.read(composerImagePickerProvider);
    _imageUploadCoordinator = ref.read(composerImageUploadCoordinatorProvider);
    _attachBbCodeService = ref.read(composerAttachBbCodeServiceProvider);

    ref.onDispose(() {
      _saveTimer?.cancel();
      _uploadGeneration += 1;
      _imageUploadCoordinator?.cancel();
      unawaited(_imageUploadSubscription?.cancel());
      _imageUploadSubscription = null;
      final current = _latestState;
      if (current != null) {
        unawaited(_saveSnapshot(current));
      }
    });

    await _pruneDraftsIfNeeded();
    final snapshot = await _draftRepository!.loadDraft(draftIdentity);
    final preferences = await ref.read(
      composerPreferencesControllerProvider.future,
    );
    final initial = await buildInitialState(
      restoredDraft: restoreDraft(
        snapshot != null && !snapshot.isEmpty ? snapshot : null,
      ),
      preferences: preferences,
    );
    _latestState = initial;
    _messageRevisionTracker.reset(
      source: initial.message,
      revision: initial.messageRevision,
    );
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
  Map<String, String> draftExtrasFor(TState value) => const <String, String>{};

  /// Whether the current state represents a meaningful draft for this
  /// composer. Edit controllers override this against their server baseline;
  /// reply/posting keep the historical non-empty behavior.
  bool shouldPersistDraft(TState value) => value.hasDraftContent;

  /// Builds the persisted draft payload. Edit controllers can retain a
  /// pending conflict draft without replacing it with the server projection.
  ComposerDraftSnapshot draftSnapshotFor(TState value) {
    return ComposerDraftSnapshot(
      identity: draftIdentity,
      message: value.message,
      subject: draftSubjectFor(value),
      extras: draftExtrasFor(value),
      useSignature: value.useSignature,
      updatedAt: DateTime.now(),
      imageAttachments: value.imageAttachments,
    );
  }

  /// 子类钩子：提交成功后基类已经清空 message / 附件，子类可以在此把
  /// 业务专属字段（如发帖标题、所选分类）也重置到"空白"。默认 no-op。
  TState resetAfterSuccess(TState value) => value;

  /// 用户主动重置草稿时，子类清空自己的业务字段。默认只清空通用字段。
  TState resetDraftContent(TState value) => value;

  /// Reset hook for editors whose empty state is a server baseline rather than
  /// an empty composer. The default keeps the legacy reset behavior.
  TState resetToBaseline(TState value) => resetDraftContent(value);

  /// Source text that the revision tracker should use after a reset.
  String messageForRevisionReset(TState value) => value.message;

  // ── 通用 mutators ─────────────────────────────────────────────
  void updateMessage(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _messageRevisionTracker.recordChange(
      previousSource: current.message,
      nextSource: value,
    );
    _setDataState(
      applyPatch(
        current,
        ComposerStatePatch(
          message: value,
          messageRevision: _messageRevisionTracker.revision,
          clearLastMessageMutation: true,
          clearFailure: true,
        ),
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
      applyPatch(
        current,
        ComposerStatePatch(useSignature: value, clearFailure: true),
      ),
    );
    _scheduleDraftSave();
    unawaited(_saveNewDraftSignatureDefault(value));
  }

  Future<void> _saveNewDraftSignatureDefault(bool value) async {
    try {
      await ref
          .read(composerPreferencesControllerProvider.notifier)
          .setNewDraftUseSignature(value);
    } catch (_) {
      // The current draft keeps its explicit setting when saving the future
      // new-draft default fails.
    }
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
    final repository = _draftRepository;
    if (repository == null) {
      return;
    }
    await _enqueueDraftWrite(() => repository.deleteDraft(draftIdentity));
  }

  Future<void> resetDraft() async {
    final current = state.value ?? _latestState;
    if (current == null || current.isSubmitting) {
      return;
    }

    _saveTimer?.cancel();
    _saveTimer = null;
    _uploadGeneration += 1;
    _activeUploadBatch = null;
    _imageUploadCoordinator?.cancel();
    final subscription = _imageUploadSubscription;
    _imageUploadSubscription = null;
    await subscription?.cancel();

    final reset = resetToBaseline(
      applyPatch(
        current,
        ComposerStatePatch(
          message: '',
          messageRevision: current.messageRevision + 1,
          clearLastMessageMutation: true,
          pendingAttachmentAids: <String>[],
          clearPendingAttachmentNotice: true,
          restoredDraft: false,
          imageAttachments: <ComposerImageAttachment>[],
          isUploadingImages: false,
          imageUploadCurrent: 0,
          imageUploadTotal: 0,
          clearFailure: true,
          clearImageUploadFailure: true,
        ),
      ),
    );
    _setDataState(reset);
    _messageRevisionTracker.reset(
      source: messageForRevisionReset(reset),
      revision: current.messageRevision + 1,
    );
    final repository = _draftRepository;
    if (repository != null) {
      try {
        await _enqueueDraftWrite(() => repository.deleteDraft(draftIdentity));
      } catch (_) {
        // 保持 UI 已清空，并通过空快照再次尝试移除持久化草稿。
        _scheduleDraftSave();
      }
    }
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
    final repository = _draftRepository;
    if (repository == null) {
      return;
    }
    if (!shouldPersistDraft(value)) {
      try {
        await _enqueueDraftWrite(() => repository.deleteDraft(draftIdentity));
      } catch (_) {
        // Draft cleanup is best effort and must not block leaving the editor.
      }
      return;
    }
    final snapshot = draftSnapshotFor(value);
    try {
      await _enqueueDraftWrite(() => repository.saveDraft(snapshot));
    } catch (_) {
      // 草稿保存失败不阻断编辑或发送，用户仍可继续完成当前编辑。
    }
  }

  Future<void> _enqueueDraftWrite(Future<void> Function() operation) {
    final next = _draftWriteTail.then((_) => operation());
    _draftWriteTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  // ── 图片选择 + 上传事件分发 ──────────────────────────────────
  /// 子类可覆盖来追加业务侧的"暂时不能选图"判断（如 reply 楼层引用准备中）。
  bool canPickImages(TState state) {
    return !state.isSubmitting && !state.isUploadingImages;
  }

  Future<void> pickImages({ComposerInsertionAnchor? insertionAnchor}) async {
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
      _setDataState(
        applyPatch(
          latest,
          ComposerStatePatch(
            imageAttachments: attachments,
            isUploadingImages: true,
            imageUploadCurrent: 0,
            imageUploadTotal: sortedPickedImages.length,
            clearImageUploadFailure: true,
          ),
        ),
      );
      _activeUploadBatch = _ComposerUploadBatch(
        anchor: insertionAnchor,
        localIds: [
          for (final attachment in attachments.skip(existingCount))
            attachment.localId,
        ],
      );
      _startImageUpload(
        attachments.skip(existingCount).toList(growable: false),
      );
    } on ComposerImagePickerException catch (_) {
      final latest = state.value ?? current;
      _setDataState(
        applyPatch(
          latest,
          const ComposerStatePatch(
            imageUploadFailure: ComposerImageUploadFailure(
              code: ComposerImageUploadFailureCode.pickerFailed,
            ),
          ),
        ),
      );
    }
  }

  void _startImageUpload(List<ComposerImageAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    final generation = ++_uploadGeneration;
    unawaited(_imageUploadSubscription?.cancel());
    final stream = _imageUploadCoordinator!.uploadInOrder(
      fid: uploadFid,
      attachments: attachments,
    );
    _imageUploadSubscription = stream.listen(
      (event) => _handleImageUploadEvent(event, generation),
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _uploadGeneration) {
          return;
        }
        final current = state.value ?? _latestState;
        if (current == null) {
          return;
        }
        _setDataState(
          applyPatch(
            current,
            const ComposerStatePatch(
              isUploadingImages: false,
              imageUploadFailure: ComposerImageUploadFailure(
                code: ComposerImageUploadFailureCode.unknown,
              ),
            ),
          ),
        );
        _settleSuccessfulUploadsAsPending(generation);
      },
    );
  }

  void _handleImageUploadEvent(ComposerImageUploadEvent event, int generation) {
    if (generation != _uploadGeneration) {
      return;
    }
    final current = state.value ?? _latestState;
    if (current == null) {
      return;
    }
    switch (event.type) {
      case ComposerImageUploadEventType.started:
        _setDataState(
          applyPatch(
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
          ),
        );
        break;
      case ComposerImageUploadEventType.progress:
        _setDataState(
          applyPatch(
            current,
            ComposerStatePatch(
              isUploadingImages: true,
              imageUploadCurrent: event.current,
              imageUploadTotal: event.total,
            ),
          ),
        );
        break;
      case ComposerImageUploadEventType.uploaded:
        final uploadedImage = event.uploadedImage;
        if (uploadedImage == null) {
          return;
        }
        _setDataState(
          applyPatch(
            current,
            ComposerStatePatch(
              imageAttachments: _replaceAttachmentStatus(
                current.imageAttachments,
                localId: event.localId,
                status: ComposerImageAttachmentStatus.uploaded,
                aid: uploadedImage.aid,
                uploadedAt: uploadedImage.uploadedAt,
                clearFailureCode: true,
              ),
              isUploadingImages: true,
              imageUploadCurrent: event.current,
              imageUploadTotal: event.total,
              clearLastMessageMutation: true,
            ),
          ),
        );
        break;
      case ComposerImageUploadEventType.failed:
        _setDataState(
          applyPatch(
            current,
            ComposerStatePatch(
              imageAttachments: _replaceAttachmentStatus(
                current.imageAttachments,
                localId: event.localId,
                status: ComposerImageAttachmentStatus.failed,
                failureCode:
                    event.failure?.code ??
                    ComposerImageUploadFailureCode.unknown,
              ),
              isUploadingImages: true,
              imageUploadCurrent: event.current,
              imageUploadTotal: event.total,
              imageUploadFailure:
                  event.failure ??
                  const ComposerImageUploadFailure(
                    code: ComposerImageUploadFailureCode.unknown,
                  ),
            ),
          ),
        );
        break;
      case ComposerImageUploadEventType.completed:
        _setDataState(
          applyPatch(
            current,
            ComposerStatePatch(
              isUploadingImages: false,
              imageUploadCurrent: event.total,
              imageUploadTotal: event.total,
            ),
          ),
        );
        _finishUploadBatch(generation);
        break;
    }
  }

  /// Inserts successful uploads only after the whole batch is settled. This
  /// keeps selection mapping deterministic and preserves the picker order.
  void _finishUploadBatch(int generation) {
    if (generation != _uploadGeneration) {
      return;
    }
    final batch = _activeUploadBatch;
    _activeUploadBatch = null;
    final current = state.value ?? _latestState;
    if (batch == null || current == null) {
      return;
    }
    final aids = _successfulAidsForBatch(current, batch);
    if (aids.isEmpty) {
      return;
    }
    final anchor = batch.anchor;
    final resolved = anchor == null
        ? null
        : _messageRevisionTracker.resolve(anchor);
    if (resolved == null) {
      _setPendingAttachments(current, aids);
      return;
    }
    _insertAidsAtAnchor(current, resolved, aids);
  }

  void _settleSuccessfulUploadsAsPending(int generation) {
    if (generation != _uploadGeneration) {
      return;
    }
    final batch = _activeUploadBatch;
    _activeUploadBatch = null;
    final current = state.value ?? _latestState;
    if (batch == null || current == null) {
      return;
    }
    final aids = _successfulAidsForBatch(current, batch);
    if (aids.isNotEmpty) {
      _setPendingAttachments(current, aids);
    }
  }

  List<String> _successfulAidsForBatch(
    TState current,
    _ComposerUploadBatch batch,
  ) {
    final byLocalId = <String, ComposerImageAttachment>{
      for (final attachment in current.imageAttachments)
        attachment.localId: attachment,
    };
    final seen = <String>{};
    return [
      for (final localId in batch.localIds)
        if (byLocalId[localId] case final attachment?)
          if (attachment.canEnterSubmitPayload &&
              seen.add(attachment.aid!.trim()))
            attachment.aid!.trim(),
    ];
  }

  void _setPendingAttachments(TState current, List<String> aids) {
    final existing = current.pendingAttachmentAids.toSet();
    final merged = <String>[
      ...current.pendingAttachmentAids,
      for (final aid in aids)
        if (existing.add(aid)) aid,
    ];
    _setDataState(
      applyPatch(
        current,
        ComposerStatePatch(
          pendingAttachmentAids: merged,
          pendingAttachmentNotice: ComposerPendingAttachmentNotice(
            code: ComposerPendingAttachmentNoticeCode.readyToReinsert,
            count: merged.length,
          ),
          clearLastMessageMutation: true,
        ),
      ),
    );
    _scheduleDraftSave();
  }

  Future<void> insertPendingAttachments(ComposerInsertionAnchor anchor) async {
    final current = state.value ?? _latestState;
    if (current == null || current.pendingAttachmentAids.isEmpty) {
      return;
    }
    final resolved = _messageRevisionTracker.resolve(anchor);
    if (resolved == null) {
      _setDataState(
        applyPatch(
          current,
          ComposerStatePatch(
            pendingAttachmentNotice: ComposerPendingAttachmentNotice(
              code: ComposerPendingAttachmentNoticeCode.selectionExpired,
              count: current.pendingAttachmentAids.length,
            ),
          ),
        ),
      );
      return;
    }
    _insertAidsAtAnchor(current, resolved, current.pendingAttachmentAids);
  }

  void _insertAidsAtAnchor(
    TState current,
    ComposerInsertionAnchor anchor,
    List<String> aids,
  ) {
    final mutation = _messageInsertionService.insertAttachmentBlock(
      source: current.message,
      selection: anchor.selection,
      attachmentCodes: [
        for (final aid in aids) attachBbCodeService.attachCode(aid),
      ],
      revision: _messageRevisionTracker.revision + 1,
    );
    _messageRevisionTracker.recordChange(
      previousSource: current.message,
      nextSource: mutation.nextSource,
    );
    _setDataState(
      applyPatch(
        current,
        ComposerStatePatch(
          message: mutation.nextSource,
          messageRevision: _messageRevisionTracker.revision,
          lastMessageMutation: ComposerTextMutation(
            previousSource: mutation.previousSource,
            nextSource: mutation.nextSource,
            replacedSelection: mutation.replacedSelection,
            resultSelection: mutation.resultSelection,
            revision: _messageRevisionTracker.revision,
          ),
          pendingAttachmentAids: const <String>[],
          clearPendingAttachmentNotice: true,
          clearFailure: true,
        ),
      ),
    );
    _scheduleDraftSave();
  }

  List<ComposerImageAttachment> _replaceAttachmentStatus(
    List<ComposerImageAttachment> attachments, {
    required String localId,
    required ComposerImageAttachmentStatus status,
    String? aid,
    DateTime? uploadedAt,
    ComposerImageUploadFailureCode? failureCode,
    bool clearFailureCode = false,
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
            failureCode: clearFailureCode
                ? null
                : failureCode ?? attachment.failureCode,
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
      const ComposerStatePatch(isSubmitting: true, clearFailure: true),
    );
    _setDataState(marked);

    final sanitized = await _sanitizeBeforeSubmit(marked);

    final preflight = preflightValidate(sanitized);
    if (preflight != null) {
      _setDataState(
        applyPatch(
          sanitized,
          ComposerStatePatch(isSubmitting: false, failure: preflight),
        ),
      );
      return ComposerSubmitInvocationResult.notSent(failure: preflight);
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
          messageRevision: afterSubmit.messageRevision + 1,
          pendingAttachmentAids: const <String>[],
          clearLastMessageMutation: true,
          clearPendingAttachmentNotice: true,
          clearFailure: true,
        ),
      );
      _setDataState(resetAfterSuccess(reset));
      _messageRevisionTracker.reset(
        source: '',
        revision: afterSubmit.messageRevision + 1,
      );
      return ComposerSubmitInvocationResult.sent(
        rawDetail: outcome.rawSuccessDetail,
      );
    }

    final failure =
        outcome.failure ??
        ComposerSubmissionFailure(
          code: ComposerSubmissionFailureCode.unknown,
          kind: composerKind,
        );
    final failed = applyPatch(
      afterSubmit,
      ComposerStatePatch(isSubmitting: false, failure: failure),
    );
    _setDataState(failed);
    await _saveSnapshot(failed);
    return ComposerSubmitInvocationResult.notSent(failure: failure);
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
        messageRevision: current.message == result.message
            ? current.messageRevision
            : _recordMessageChange(current.message, result.message),
        clearLastMessageMutation: true,
        clearImageUploadFailure: true,
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

  int _recordMessageChange(String previousSource, String nextSource) {
    _messageRevisionTracker.recordChange(
      previousSource: previousSource,
      nextSource: nextSource,
    );
    return _messageRevisionTracker.revision;
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

class _ComposerUploadBatch {
  const _ComposerUploadBatch({required this.anchor, required this.localIds});

  final ComposerInsertionAnchor? anchor;
  final List<String> localIds;
}
