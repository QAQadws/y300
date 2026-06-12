import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 发帖 payload builder 在 Phase 3 阶段（没有 controller / state）需要的输入。
///
/// Phase 4 引入 `PostingComposerState` 之后，由控制器把 state + metadata 翻成
/// [NewThreadDraftInput] 再喂给 builder，避免 builder 直接依赖 presentation 层。
class NewThreadDraftInput {
  const NewThreadDraftInput({
    required this.subject,
    required this.message,
    required this.selectedTypeId,
    required this.useSignature,
    required this.allowNoticeAuthor,
    required this.bbCodeOff,
    required this.smileyOff,
    required this.parseUrlOff,
    this.imageAttachments = const <ComposerImageAttachment>[],
  });

  final String subject;
  final String message;

  /// 用户当前选择的 typeid；`null` 表示尚未选择 / 选择"无分类"。
  final String? selectedTypeId;
  final bool useSignature;
  final bool allowNoticeAuthor;
  final bool bbCodeOff;
  final bool smileyOff;
  final bool parseUrlOff;
  final List<ComposerImageAttachment> imageAttachments;
}

/// Strategy：把 `(input, metadata)` 翻译成发帖 form-urlencoded payload。
///
/// 抽象 + 默认实现的拆分让未来"投票 / 悬赏 / 活动"等 special 不同走不同
/// builder，对外仍然是 `NewThreadPayloadBuilder` 一个接口。
abstract class NewThreadPayloadBuilder {
  NewThreadDraftPayload build({
    required NewThreadDraftInput input,
    required NewThreadFormMetadata metadata,
  });
}

class DefaultNewThreadPayloadBuilder implements NewThreadPayloadBuilder {
  const DefaultNewThreadPayloadBuilder({
    this.attachBbCodeService = const ComposerAttachBbCodeService(),
  });

  final ComposerAttachBbCodeService attachBbCodeService;

  @override
  NewThreadDraftPayload build({
    required NewThreadDraftInput input,
    required NewThreadFormMetadata metadata,
  }) {
    final typeid = _resolveTypeId(
      selected: input.selectedTypeId,
      metadata: metadata,
    );
    return NewThreadDraftPayload(
      fid: metadata.fid,
      formHash: metadata.formHash,
      subject: input.subject.trim(),
      message: input.message.trim(),
      typeid: typeid,
      useSignature: input.useSignature,
      allowNoticeAuthor: input.allowNoticeAuthor,
      bbCodeOff: input.bbCodeOff,
      smileyOff: input.smileyOff,
      parseUrlOff: input.parseUrlOff,
      uploadedAttachmentAids: _resolveUploadedAttachmentAids(input),
    );
  }

  String _resolveTypeId({
    required String? selected,
    required NewThreadFormMetadata metadata,
  }) {
    final trimmed = selected?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '0';
    }
    // 已经从 metadata 列表里被移除的 typeid 不应出现在最终 payload。
    final allowed = metadata.threadTypes.any((type) => type.id == trimmed);
    if (!allowed) {
      return '0';
    }
    return trimmed;
  }

  /// 与 reply 一致：message 中残留 `[attach]aid[/attach]` 与已上传附件取交集，
  /// 按 message 中出现顺序排序，去重后输出。
  List<String> _resolveUploadedAttachmentAids(NewThreadDraftInput input) {
    final validAids = <String>{
      for (final attachment in input.imageAttachments)
        if (attachment.canEnterSubmitPayload) attachment.aid!.trim(),
    };
    if (validAids.isEmpty) {
      return const <String>[];
    }
    final seen = <String>{};
    final resolved = <String>[];
    for (final aid in attachBbCodeService.extractAttachAids(input.message)) {
      if (!validAids.contains(aid) || !seen.add(aid)) {
        continue;
      }
      resolved.add(aid);
    }
    return resolved;
  }
}
