import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/services/composer_submission_error_presenter.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_controller_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';
import 'package:y300/features/posting/data/new_thread_repository.dart';
import 'package:y300/features/posting/data/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/data/posting_providers.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/new_thread_payload_builder.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';

/// 草稿 extras 中预定义的 key。集中放在这里避免 controller / 草稿 codec / 测试
/// 各自硬编码字符串后字段意外飘逸。
class _PostingDraftExtras {
  static const String typeid = 'typeid';
  static const String allowNoticeAuthor = 'allowNoticeAuthor';
  static const String bbCodeOff = 'bbCodeOff';
  static const String smileyOff = 'smileyOff';
  static const String parseUrlOff = 'parseurlOff';
}

final postingComposerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PostingComposerController, PostingComposerState,
        PostingComposerArgs>(
      (args) => PostingComposerController(args),
    );

/// 发帖编辑器控制器。
///
/// 通用流程（草稿恢复 / 防抖落盘 / 模式切换 / 图片上传 / submit 调度）走
/// [ComposerControllerBase]；这里只补：
/// 1) `_loadMetadata`：拉取 forumdisplay 元数据，并在 metadata 到位后校正
///    草稿恢复出来的 typeid。
/// 2) 业务字段更新（subject / typeid / 选项）+ 草稿落盘。
/// 3) `performSubmit`：把 state 翻译成 [NewThreadDraftInput]，喂给
///    [NewThreadPayloadBuilder]，再交给 [NewThreadRepository] 提交，
///    成功 / 失败统一翻译为 [ComposerSubmissionOutcome]。
class PostingComposerController
    extends ComposerControllerBase<PostingComposerState> {
  PostingComposerController(this._args);

  final PostingComposerArgs _args;
  PostingFormMetadataRepository? _metadataRepository;
  NewThreadRepository? _newThreadRepository;
  NewThreadPayloadBuilder? _payloadBuilder;
  ComposerSubmissionErrorPresenter? _errorPresenter;

  @override
  ComposerDraftIdentity get draftIdentity => _args.identity;

  @override
  String get uploadFid => _args.target.fid;

  @override
  FutureOr<PostingComposerState> build() async {
    _metadataRepository = ref.read(postingFormMetadataRepositoryProvider);
    _newThreadRepository = ref.read(newThreadRepositoryProvider);
    _payloadBuilder = ref.read(newThreadPayloadBuilderProvider);
    _errorPresenter = ref.read(composerSubmissionErrorPresenterProvider);
    return super.build();
  }

  @override
  Future<PostingComposerState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
  }) async {
    final extras = restoredDraft?.extras ?? const <String, String>{};
    final restoredTypeId = _readNonEmpty(extras[_PostingDraftExtras.typeid]);
    return PostingComposerState.initial(
      target: _args.target,
      subject: restoredDraft?.subject ?? '',
      message: restoredDraft?.message ?? '',
      useSignature: restoredDraft?.useSignature ?? true,
      restoredDraft: restoredDraft != null,
      imageAttachments:
          restoredDraft?.imageAttachments ?? const <ComposerImageAttachment>[],
      isLoadingMetadata: true,
      selectedTypeId: restoredTypeId,
      allowNoticeAuthor:
          _readBool(extras[_PostingDraftExtras.allowNoticeAuthor]),
      bbCodeOff: _readBool(extras[_PostingDraftExtras.bbCodeOff]),
      smileyOff: _readBool(extras[_PostingDraftExtras.smileyOff]),
      parseUrlOff: _readBool(extras[_PostingDraftExtras.parseUrlOff]),
    );
  }

  @override
  void onAfterBuild(PostingComposerState initial) {
    // 沿用 reply 的时序约定：用 microtask 把元数据拉取推迟到 build 完成之后。
    unawaited(Future<void>.microtask(_loadMetadata));
  }

  // PLACEHOLDER_PHASE_4_PATCH_AND_UPDATERS
  @override
  PostingComposerState applyPatch(
    PostingComposerState current,
    ComposerStatePatch patch,
  ) {
    return current.copyWith(
      message: patch.message,
      useSignature: patch.useSignature,
      isSubmitting: patch.isSubmitting,
      mode: patch.mode,
      restoredDraft: patch.restoredDraft,
      imageAttachments: patch.imageAttachments,
      isUploadingImages: patch.isUploadingImages,
      imageUploadCurrent: patch.imageUploadCurrent,
      imageUploadTotal: patch.imageUploadTotal,
      errorMessage: patch.errorMessage,
      imageUploadError: patch.imageUploadError,
      clearErrorMessage: patch.clearErrorMessage,
      clearImageUploadError: patch.clearImageUploadError,
    );
  }

  @override
  bool canPickImages(PostingComposerState state) {
    return state.canPickImages;
  }

  @override
  String draftSubjectFor(PostingComposerState value) => value.subject;

  @override
  Map<String, String> draftExtrasFor(PostingComposerState value) {
    return <String, String>{
      if ((value.selectedTypeId ?? '').isNotEmpty)
        _PostingDraftExtras.typeid: value.selectedTypeId!,
      if (value.allowNoticeAuthor) _PostingDraftExtras.allowNoticeAuthor: '1',
      if (value.bbCodeOff) _PostingDraftExtras.bbCodeOff: '1',
      if (value.smileyOff) _PostingDraftExtras.smileyOff: '1',
      if (value.parseUrlOff) _PostingDraftExtras.parseUrlOff: '1',
    };
  }

  @override
  PostingComposerState resetAfterSuccess(PostingComposerState value) {
    return value.copyWith(
      subject: '',
      clearSelectedTypeId: true,
      allowNoticeAuthor: false,
      bbCodeOff: false,
      smileyOff: false,
      parseUrlOff: false,
    );
  }

  /// 业务专属字段更新走自己的 setter，绕开 [ComposerStatePatch]，让基类
  /// 不必感知发帖独有字段。
  void updateSubject(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    setStateValue(current.copyWith(
      subject: value,
      clearErrorMessage: true,
    ));
    unawaited(scheduleDraftSave());
  }

  void updateSelectedTypeId(String? typeId) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final trimmed = typeId?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '0') {
      setStateValue(current.copyWith(
        clearSelectedTypeId: true,
        clearErrorMessage: true,
      ));
    } else {
      setStateValue(current.copyWith(
        selectedTypeId: trimmed,
        clearErrorMessage: true,
      ));
    }
    unawaited(scheduleDraftSave());
  }

  void updateAllowNoticeAuthor(bool value) {
    _updateOption((s) => s.copyWith(allowNoticeAuthor: value));
  }

  void updateBbCodeOff(bool value) {
    _updateOption((s) => s.copyWith(bbCodeOff: value));
  }

  void updateSmileyOff(bool value) {
    _updateOption((s) => s.copyWith(smileyOff: value));
  }

  void updateParseUrlOff(bool value) {
    _updateOption((s) => s.copyWith(parseUrlOff: value));
  }

  void _updateOption(
    PostingComposerState Function(PostingComposerState) reducer,
  ) {
    final current = state.value;
    if (current == null) {
      return;
    }
    setStateValue(reducer(current).copyWith(clearErrorMessage: true));
    unawaited(scheduleDraftSave());
  }


  // PLACEHOLDER_PHASE_4_METADATA_FLOW
  /// 重新拉取版块 metadata。失败状态下用户点"重试"会调到这里。
  Future<void> retryLoadMetadata() => _loadMetadata();

  Future<void> _loadMetadata() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    if (!current.isLoadingMetadata) {
      setStateValue(current.copyWith(
        isLoadingMetadata: true,
        clearMetadataError: true,
      ));
    }

    final result =
        await _metadataRepository!.getFormMetadata(fid: _args.target.fid);
    final latest = state.value;
    if (latest == null) {
      return;
    }
    if (result case ApiSuccess<NewThreadFormMetadata>(:final data)) {
      setStateValue(latest.copyWith(
        metadata: data,
        isLoadingMetadata: false,
        clearMetadataError: true,
        // 草稿恢复出来的 typeid 如果不在最新 metadata 列表里（可能版块改了
        // 主题分类配置），就把它丢掉。typeid='0' 用户语义是"无分类"，永远合法。
        selectedTypeId: _normalizeRestoredTypeId(
          latest.selectedTypeId,
          metadata: data,
        ),
        clearSelectedTypeId: !_isTypeIdValid(
          latest.selectedTypeId,
          metadata: data,
        ),
      ));
      return;
    }
    final error = (result as ApiFailure<NewThreadFormMetadata>).error;
    setStateValue(latest.copyWith(
      isLoadingMetadata: false,
      metadataError: error.message.isEmpty ? '加载发帖表单失败' : error.message,
    ));
  }

  String? _normalizeRestoredTypeId(
    String? selected, {
    required NewThreadFormMetadata metadata,
  }) {
    if (!_isTypeIdValid(selected, metadata: metadata)) {
      return null;
    }
    return selected;
  }

  bool _isTypeIdValid(
    String? selected, {
    required NewThreadFormMetadata metadata,
  }) {
    final trimmed = selected?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return true;
    }
    if (trimmed == '0') {
      return true;
    }
    return metadata.threadTypes.any((type) => type.id == trimmed);
  }


  // PLACEHOLDER_PHASE_4_SUBMIT
  @override
  String? preflightValidate(PostingComposerState state) {
    final subject = state.subject.trim();
    if (subject.isEmpty) {
      return '请输入标题';
    }
    final message = state.message.trim();
    if (message.isEmpty) {
      return '请输入正文';
    }
    final metadata = state.metadata;
    if (metadata == null) {
      return state.metadataError == null
          ? '发帖表单还在加载，请稍候再试'
          : '发帖表单加载失败：${state.metadataError}';
    }
    if (metadata.typeRequired) {
      final typeid = state.selectedTypeId?.trim() ?? '';
      if (typeid.isEmpty || typeid == '0') {
        return '该版块要求选择主题分类，请先选择';
      }
    }
    // metadata 可能没有声明上限——`hasSubjectLimit` 已经把 `<=0` 当作"不限制"。
    if (metadata.hasSubjectLimit &&
        subject.length > metadata.maxSubjectLength) {
      return '标题超出版块上限（最多 ${metadata.maxSubjectLength} 字符）';
    }
    if (metadata.hasMessageLimit &&
        message.length > metadata.maxMessageLength) {
      return '正文超出版块上限（最多 ${metadata.maxMessageLength} 字符）';
    }
    return null;
  }

  @override
  Future<ComposerSubmissionOutcome> performSubmit({
    required PostingComposerState state,
    required List<String> uploadedAids,
  }) async {
    final metadata = state.metadata;
    if (metadata == null) {
      // preflight 已经守过这一关；这里只是为类型收口兜底。
      return const ComposerSubmissionOutcome.failure(
        errorMessage: '发帖表单未就绪，请重试',
      );
    }
    final input = NewThreadDraftInput(
      subject: state.subject,
      message: state.message,
      selectedTypeId: state.selectedTypeId,
      useSignature: state.useSignature,
      allowNoticeAuthor: state.allowNoticeAuthor,
      bbCodeOff: state.bbCodeOff,
      smileyOff: state.smileyOff,
      parseUrlOff: state.parseUrlOff,
      imageAttachments: state.imageAttachments,
    );
    final payload = _payloadBuilder!.build(
      input: input,
      metadata: metadata,
    );
    final result = await _newThreadRepository!.submit(payload: payload);
    if (result case ApiSuccess<NewThreadSubmissionResult>(:final data)) {
      _lastSuccess = data;
      return ComposerSubmissionOutcome.success(
        message: data.message.isEmpty ? '发布成功' : data.message,
      );
    }
    final error = (result as ApiFailure<NewThreadSubmissionResult>).error;
    final errorMessage = _errorPresenter?.present(
          error,
          kind: ComposerKind.newThread,
        ) ??
        error.message;
    return ComposerSubmissionOutcome.failure(errorMessage: errorMessage);
  }

  /// 兼容外层"窄化结果"的需求：基类返回 [ComposerSubmitInvocationResult]，
  /// 这里再裹上一层把成功路径下的 tid/pid 带出去。
  @override
  Future<PostingComposerResult> submit() async {
    _lastSuccess = null;
    final result = await super.submit();
    return PostingComposerResult.fromInvocation(
      result,
      tid: _lastSuccess?.tid,
      pid: _lastSuccess?.pid,
    );
  }


  // PLACEHOLDER_PHASE_4_HELPERS
  /// `performSubmit` 写入、`submit` 读取，最后封进 [PostingComposerResult]。
  /// 单线程运行，submit 之间不会重叠，所以一个普通字段足够。
  NewThreadSubmissionResult? _lastSuccess;

  String? _readNonEmpty(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _readBool(String? value) {
    if (value == null) {
      return false;
    }
    final normalized = value.trim().toLowerCase();
    return normalized == '1' || normalized == 'true';
  }
}
