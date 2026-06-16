import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_editor_mode.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';

/// 发帖编辑器路由参数。
///
/// 与 reply 模块的 `ReplyComposerArgs` 同构，作为 Riverpod
/// `AsyncNotifierProvider.autoDispose.family` 的 key——每个 fid 对应一份草稿，
/// args 必须可哈希、可比较。
class PostingComposerArgs {
  const PostingComposerArgs({
    required this.target,
  });

  final PostingTarget target;

  ComposerDraftIdentity get identity =>
      ComposerDraftIdentity.newThread(fid: target.fid);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PostingComposerArgs && other.target == target;
  }

  @override
  int get hashCode => target.hashCode;
}

/// 发帖编辑器的视图状态。
///
/// 字段切分原则：
/// - 通用字段（message / mode / 附件 / 草稿恢复 / 上传进度 / 错误）走基类；
/// - 业务字段（target / metadata / subject / typeid / 选项）放在本类；
/// - metadata 是 `null` 表示"还在加载或加载失败"，由 [isLoadingMetadata] /
///   [metadataError] 区分。这两个状态分开存而非合并 enum，是为了让"加载失败
///   后用户继续打字"的情况，metadata 可以保留旧错误标记同时正常编辑草稿。
/// - tags / special / poll 三个字段是后续扩展轴：tags 普通/投票通用；
///   special 决定 payload strategy；poll 仅当 special == poll 时非空。
class PostingComposerState extends ComposerStateBase {
  const PostingComposerState({
    required this.target,
    required super.message,
    required this.subject,
    required super.useSignature,
    required super.isSubmitting,
    required super.mode,
    required super.restoredDraft,
    required super.imageAttachments,
    required super.isUploadingImages,
    required super.imageUploadCurrent,
    required super.imageUploadTotal,
    required this.isLoadingMetadata,
    this.metadata,
    this.metadataError,
    this.selectedTypeId,
    this.allowNoticeAuthor = false,
    this.bbCodeOff = false,
    this.smileyOff = false,
    this.parseUrlOff = false,
    this.tags = const <String>[],
    this.special = NewThreadSpecial.normal,
    this.poll,
    super.errorMessage,
    super.imageUploadError,
  });

  factory PostingComposerState.initial({
    required PostingTarget target,
    String message = '',
    String subject = '',
    bool useSignature = true,
    ComposerEditorMode mode = ComposerEditorMode.source,
    bool restoredDraft = false,
    List<ComposerImageAttachment> imageAttachments = const [],
    bool isLoadingMetadata = true,
    NewThreadFormMetadata? metadata,
    String? metadataError,
    String? selectedTypeId,
    bool allowNoticeAuthor = false,
    bool bbCodeOff = false,
    bool smileyOff = false,
    bool parseUrlOff = false,
    List<String> tags = const <String>[],
    NewThreadSpecial special = NewThreadSpecial.normal,
    NewThreadPollDraft? poll,
  }) {
    return PostingComposerState(
      target: target,
      message: message,
      subject: subject,
      useSignature: useSignature,
      isSubmitting: false,
      mode: mode,
      restoredDraft: restoredDraft,
      imageAttachments: imageAttachments,
      isUploadingImages: false,
      imageUploadCurrent: 0,
      imageUploadTotal: 0,
      isLoadingMetadata: isLoadingMetadata,
      metadata: metadata,
      metadataError: metadataError,
      selectedTypeId: selectedTypeId,
      allowNoticeAuthor: allowNoticeAuthor,
      bbCodeOff: bbCodeOff,
      smileyOff: smileyOff,
      parseUrlOff: parseUrlOff,
      tags: tags,
      special: special,
      poll: poll,
    );
  }

  final PostingTarget target;
  final String subject;
  final bool isLoadingMetadata;
  final NewThreadFormMetadata? metadata;
  final String? metadataError;

  /// 用户当前选择的 typeid。`null` 表示"未选择"或"无分类"。
  /// 草稿恢复出的 typeid 如果不在 metadata 列表里，会在 metadata 加载完成后被重置为 `null`。
  final String? selectedTypeId;
  final bool allowNoticeAuthor;
  final bool bbCodeOff;
  final bool smileyOff;
  final bool parseUrlOff;

  /// 主题标签（chip 输入）。空表示用户未填。
  final List<String> tags;

  /// 主题特殊类型；目前只 normal / poll。
  final NewThreadSpecial special;

  /// 投票草稿；仅当 [special] == [NewThreadSpecial.poll] 时非空。
  /// segmented 切到普通帖时由 controller 负责清空。
  final NewThreadPollDraft? poll;

  bool get canPickImages => !isSubmitting && !isUploadingImages;

  bool get canSubmit {
    if (subject.trim().isEmpty || message.trim().isEmpty) {
      return false;
    }
    if (isSubmitting || isUploadingImages || isLoadingMetadata) {
      return false;
    }
    if (metadata == null) {
      return false;
    }
    if (metadata!.typeRequired) {
      final typeid = selectedTypeId?.trim() ?? '';
      if (typeid.isEmpty || typeid == '0') {
        return false;
      }
    }
    // 字数上限——metadata 可能没有声明（hasXxxLimit 已经把 <=0 当成不限制）。
    if (metadata!.hasSubjectLimit &&
        subject.trim().length > metadata!.maxSubjectLength) {
      return false;
    }
    if (metadata!.hasMessageLimit &&
        message.trim().length > metadata!.maxMessageLength) {
      return false;
    }
    if (special == NewThreadSpecial.poll) {
      final p = poll;
      if (p == null) return false;
      final validOptions =
          p.options.where((s) => s.trim().isNotEmpty).toList(growable: false);
      if (validOptions.length < NewThreadPollValidation.minOptions) {
        return false;
      }
      if (p.options.any(
        (option) => option.trim().length > NewThreadPollValidation.maxOptionLength,
      )) {
        return false;
      }
      if (p.multiple && p.maxChoices < 2) return false;
    }
    return true;
  }

  PostingComposerState copyWith({
    String? message,
    String? subject,
    bool? useSignature,
    bool? isSubmitting,
    ComposerEditorMode? mode,
    bool? restoredDraft,
    List<ComposerImageAttachment>? imageAttachments,
    bool? isUploadingImages,
    int? imageUploadCurrent,
    int? imageUploadTotal,
    bool? isLoadingMetadata,
    NewThreadFormMetadata? metadata,
    String? metadataError,
    String? selectedTypeId,
    bool? allowNoticeAuthor,
    bool? bbCodeOff,
    bool? smileyOff,
    bool? parseUrlOff,
    List<String>? tags,
    NewThreadSpecial? special,
    NewThreadPollDraft? poll,
    String? errorMessage,
    String? imageUploadError,
    bool clearMetadata = false,
    bool clearMetadataError = false,
    bool clearSelectedTypeId = false,
    bool clearPoll = false,
    bool clearErrorMessage = false,
    bool clearImageUploadError = false,
  }) {
    return PostingComposerState(
      target: target,
      message: message ?? this.message,
      subject: subject ?? this.subject,
      useSignature: useSignature ?? this.useSignature,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      mode: mode ?? this.mode,
      restoredDraft: restoredDraft ?? this.restoredDraft,
      imageAttachments: imageAttachments ?? this.imageAttachments,
      isUploadingImages: isUploadingImages ?? this.isUploadingImages,
      imageUploadCurrent: imageUploadCurrent ?? this.imageUploadCurrent,
      imageUploadTotal: imageUploadTotal ?? this.imageUploadTotal,
      isLoadingMetadata: isLoadingMetadata ?? this.isLoadingMetadata,
      metadata: clearMetadata ? null : metadata ?? this.metadata,
      metadataError:
          clearMetadataError ? null : metadataError ?? this.metadataError,
      selectedTypeId:
          clearSelectedTypeId ? null : selectedTypeId ?? this.selectedTypeId,
      allowNoticeAuthor: allowNoticeAuthor ?? this.allowNoticeAuthor,
      bbCodeOff: bbCodeOff ?? this.bbCodeOff,
      smileyOff: smileyOff ?? this.smileyOff,
      parseUrlOff: parseUrlOff ?? this.parseUrlOff,
      tags: tags ?? this.tags,
      special: special ?? this.special,
      poll: clearPoll ? null : poll ?? this.poll,
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      imageUploadError: clearImageUploadError
          ? null
          : imageUploadError ?? this.imageUploadError,
    );
  }
}

/// 控制器对外暴露的 submit 结果。
///
/// 与 [ComposerSubmitInvocationResult] 同字段，再补上 tid/pid 让 UI
/// 在发帖成功后能跳转到新帖子（Phase 5/6 使用）。
class PostingComposerResult extends ComposerSubmitInvocationResult {
  const PostingComposerResult({
    required super.sent,
    required super.message,
    this.tid,
    this.pid,
  });

  factory PostingComposerResult.fromInvocation(
    ComposerSubmitInvocationResult invocation, {
    String? tid,
    String? pid,
  }) {
    return PostingComposerResult(
      sent: invocation.sent,
      message: invocation.message,
      tid: tid,
      pid: pid,
    );
  }

  final String? tid;
  final String? pid;
}
