import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/services/composer_submission_error_presenter.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_controller_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';
import 'package:y300/features/posting/data/repositories/new_thread_repository.dart';
import 'package:y300/features/posting/data/repositories/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/data/providers/posting_providers.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/new_thread_payload_builder.dart';
import 'package:y300/features/posting/domain/services/new_thread_tags_normalizer.dart';
import 'package:y300/features/posting/domain/services/posting_draft_extras_codec.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';

final postingComposerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<
      PostingComposerController,
      PostingComposerState,
      PostingComposerArgs
    >((args) => PostingComposerController(args));

/// 发帖编辑器控制器。
///
/// 通用流程（草稿恢复 / 防抖落盘 / 模式切换 / 图片上传 / submit 调度）走
/// [ComposerControllerBase]；这里只补：
/// 1) `_loadMetadata`：拉取 forumdisplay 元数据，并在 metadata 到位后校正
///    草稿恢复出来的 typeid。
/// 2) 业务字段更新（subject / typeid / 选项 / tags / special / poll）+
///    草稿落盘。tags / poll 走单独的小型 setter，避免基类感知发帖独有字段。
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
  PostingDraftExtrasCodec? _draftExtrasCodec;
  NewThreadTagsNormalizer? _tagsNormalizer;

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
    _draftExtrasCodec = ref.read(postingDraftExtrasCodecProvider);
    _tagsNormalizer = ref.read(newThreadTagsNormalizerProvider);
    return super.build();
  }

  @override
  Future<PostingComposerState> buildInitialState({
    required ComposerDraftSnapshot? restoredDraft,
    required ComposerPreferences preferences,
  }) async {
    final extras = _draftExtrasCodec!.decode(
      restoredDraft?.extras ?? const <String, String>{},
    );
    return PostingComposerState.initial(
      target: _args.target,
      subject: restoredDraft?.subject ?? '',
      message: restoredDraft?.message ?? '',
      useSignature:
          restoredDraft?.useSignature ?? preferences.newDraftUseSignature,
      restoredDraft: restoredDraft != null,
      imageAttachments:
          restoredDraft?.imageAttachments ?? const <ComposerImageAttachment>[],
      isLoadingMetadata: true,
      selectedTypeId: extras.selectedTypeId,
      allowNoticeAuthor: extras.allowNoticeAuthor,
      bbCodeOff: extras.bbCodeOff,
      smileyOff: extras.smileyOff,
      parseUrlOff: extras.parseUrlOff,
      tags: extras.tags,
      special: extras.special,
      poll: extras.poll,
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
    return _draftExtrasCodec!.encode(
      selectedTypeId: value.selectedTypeId,
      allowNoticeAuthor: value.allowNoticeAuthor,
      bbCodeOff: value.bbCodeOff,
      smileyOff: value.smileyOff,
      parseUrlOff: value.parseUrlOff,
      tags: value.tags,
      special: value.special,
      poll: value.poll,
    );
  }

  @override
  PostingComposerState resetAfterSuccess(PostingComposerState value) {
    return _resetDraftFields(value);
  }

  @override
  PostingComposerState resetDraftContent(PostingComposerState value) {
    return _resetDraftFields(value);
  }

  PostingComposerState _resetDraftFields(PostingComposerState value) {
    return value.copyWith(
      subject: '',
      clearSelectedTypeId: true,
      allowNoticeAuthor: false,
      bbCodeOff: false,
      smileyOff: false,
      parseUrlOff: false,
      tags: const <String>[],
      special: NewThreadSpecial.normal,
      clearPoll: true,
    );
  }

  /// 业务专属字段更新走自己的 setter，绕开 [ComposerStatePatch]，让基类
  /// 不必感知发帖独有字段。
  void updateSubject(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    setStateValue(current.copyWith(subject: value, clearErrorMessage: true));
    unawaited(scheduleDraftSave());
  }

  void updateSelectedTypeId(String? typeId) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final trimmed = typeId?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '0') {
      setStateValue(
        current.copyWith(clearSelectedTypeId: true, clearErrorMessage: true),
      );
    } else {
      setStateValue(
        current.copyWith(selectedTypeId: trimmed, clearErrorMessage: true),
      );
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

  /// tags 整组替换。UI 端的 chip widget 负责加 / 删 / dedupe，由 controller
  /// 在落盘前用 [NewThreadTagsNormalizer] 收一遍 trim / 上限。
  void updateTags(List<String> next) {
    _updateOption(
      (s) => s.copyWith(
        tags: List<String>.unmodifiable(_tagsNormalizer!.normalize(next)),
      ),
    );
  }

  /// 切换主题特殊类型。
  ///
  /// - normal → poll：若当前 poll 为空就给一个 [NewThreadPollDraft.empty]，
  ///   让 UI 立即展开"投票编辑器"；
  /// - poll → normal：保留 poll 草稿不删（用户切回投票时还能看到原选项），
  ///   但 special 字段改为 normal，序列化时 poll 不会被 form 捎带。
  ///
  /// 这里**不**清空 poll，是为了保护用户已经填了一半的投票草稿；
  /// `resetAfterSuccess` 在提交成功后才显式清空。
  void updateSpecial(NewThreadSpecial next) {
    final current = state.value;
    if (current == null) return;
    if (current.special == next) return;
    final NewThreadPollDraft? poll;
    if (next == NewThreadSpecial.poll) {
      poll = current.poll ?? NewThreadPollDraft.empty;
    } else {
      poll = current.poll;
    }
    setStateValue(
      current.copyWith(special: next, poll: poll, clearErrorMessage: true),
    );
    unawaited(scheduleDraftSave());
  }

  // ── poll 字段编辑 ─────────────────────────────────
  void updatePollOptions(List<String> options) {
    _updatePoll((p) => p.copyWith(options: List<String>.from(options)));
  }

  void updatePollMultiple(bool multiple) {
    _updatePoll((p) {
      // 关闭多选时把 maxChoices 强制压回 1，避免草稿恢复后 UI 出现
      // 单选 + maxChoices=5 这种自相矛盾的状态。
      if (!multiple) {
        return p.copyWith(multiple: false, maxChoices: 1);
      }
      // 打开多选时，若历史 maxChoices < 2，给个 2 当起步——选项数还没填够时
      // [canSubmit] 仍会拦住提交，UI 上的输入框允许用户继续上调。
      return p.copyWith(
        multiple: true,
        maxChoices: p.maxChoices < 2 ? 2 : p.maxChoices,
      );
    });
  }

  void updatePollMaxChoices(int n) {
    _updatePoll((p) => p.copyWith(maxChoices: n < 1 ? 1 : n));
  }

  void updatePollExpirationDays(int days) {
    _updatePoll((p) => p.copyWith(expirationDays: days < 0 ? 0 : days));
  }

  void updatePollOvert(bool value) {
    _updatePoll((p) => p.copyWith(overt: value));
  }

  void updatePollVisibilityPoll(bool value) {
    _updatePoll((p) => p.copyWith(visibilityPoll: value));
  }

  void _updatePoll(NewThreadPollDraft Function(NewThreadPollDraft) reducer) {
    final current = state.value;
    if (current == null) return;
    if (current.special != NewThreadSpecial.poll) return;
    final next = reducer(current.poll ?? NewThreadPollDraft.empty);
    setStateValue(current.copyWith(poll: next, clearErrorMessage: true));
    unawaited(scheduleDraftSave());
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
      setStateValue(
        current.copyWith(isLoadingMetadata: true, clearMetadataError: true),
      );
    }

    final result = await _metadataRepository!.getFormMetadata(
      fid: _args.target.fid,
    );
    final latest = state.value;
    if (latest == null) {
      return;
    }
    if (result case ApiSuccess<NewThreadFormMetadata>(:final data)) {
      setStateValue(
        latest.copyWith(
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
        ),
      );
      return;
    }
    final error = (result as ApiFailure<NewThreadFormMetadata>).error;
    setStateValue(
      latest.copyWith(
        isLoadingMetadata: false,
        metadataError: error.message.isEmpty ? '加载发帖表单失败' : error.message,
      ),
    );
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
    if (state.special == NewThreadSpecial.poll) {
      final pollError = _validatePoll(state.poll);
      if (pollError != null) return pollError;
    }
    return null;
  }

  String? _validatePoll(NewThreadPollDraft? poll) {
    if (poll == null) {
      return '投票配置缺失，请添加选项';
    }
    final validOptions = poll.options
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    if (validOptions.length < NewThreadPollValidation.minOptions) {
      return '投票至少需要 ${NewThreadPollValidation.minOptions} 个非空选项';
    }
    if (poll.options.any(
      (option) =>
          option.trim().length > NewThreadPollValidation.maxOptionLength,
    )) {
      return '单个投票选项不能超过 ${NewThreadPollValidation.maxOptionLength} 字符';
    }
    if (poll.multiple && poll.maxChoices < 2) {
      return '多选投票的最大选择数需 ≥ 2';
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
      tags: state.tags,
      special: state.special,
      poll: state.poll,
    );
    final payload = _payloadBuilder!.build(input: input, metadata: metadata);
    final result = await _newThreadRepository!.submit(payload: payload);
    if (result case ApiSuccess<NewThreadSubmissionResult>(:final data)) {
      _lastSuccess = data;
      return ComposerSubmissionOutcome.success(
        message: data.message.isEmpty ? '发布成功' : data.message,
      );
    }
    final error = (result as ApiFailure<NewThreadSubmissionResult>).error;
    final errorMessage =
        _errorPresenter?.present(error, kind: ComposerKind.newThread) ??
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
}
