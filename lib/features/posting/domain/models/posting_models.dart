// 发帖相关领域模型。
//
// 第一期不实装 `sortid` / `tags` / `special!=0` / `seccode`；模型里也不带
// 这些字段，避免假象的"已支持"。后续阶段补上时再扩展，新字段的 default
// 值要保证旧客户端的提交载荷兼容。

class ThreadType {
  const ThreadType({
    required this.id,
    required this.name,
  });

  /// `typeid`，对应 forumdisplay.threadtypes.types map 中的 key。
  final String id;
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ThreadType && other.id == id && other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

class ThreadSort {
  const ThreadSort({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ThreadSort && other.id == id && other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

class NewThreadFormMetadata {
  const NewThreadFormMetadata({
    required this.fid,
    required this.forumName,
    required this.formHash,
    required this.threadTypes,
    required this.threadSorts,
    required this.typeRequired,
    required this.sortRequired,
    this.maxSubjectLength = 0,
    this.maxMessageLength = 0,
  });

  final String fid;
  final String forumName;
  final String formHash;
  final List<ThreadType> threadTypes;
  final List<ThreadSort> threadSorts;
  final bool typeRequired;
  final bool sortRequired;

  /// 标题字符上限。`<=0` 表示版块没有声明上限或 metadata 没解析出，
  /// 上层必须按"无限制"处理——而不是按 0 当成"标题不能写"。
  final int maxSubjectLength;

  /// 正文字符上限。`<=0` 同样表示无限制。Discuz 字段 `forumdisplay.maxpostsize`
  /// 是字节而不是字符；本期暂按字符做近似校验，避免对中文字节数引入二次换算。
  final int maxMessageLength;

  bool get hasSubjectLimit => maxSubjectLength > 0;
  bool get hasMessageLimit => maxMessageLength > 0;
}

/// 发帖提交载荷。
///
/// 由 controller + payload builder 组装，仓储层只负责 form-urlencoded 序列化。
/// `typeid='0'` 表示"无分类"。
class NewThreadDraftPayload {
  const NewThreadDraftPayload({
    required this.fid,
    required this.formHash,
    required this.subject,
    required this.message,
    required this.typeid,
    required this.useSignature,
    required this.allowNoticeAuthor,
    required this.bbCodeOff,
    required this.smileyOff,
    required this.parseUrlOff,
    this.uploadedAttachmentAids = const <String>[],
  });

  final String fid;
  final String formHash;
  final String subject;
  final String message;
  final String typeid;
  final bool useSignature;
  final bool allowNoticeAuthor;
  final bool bbCodeOff;
  final bool smileyOff;
  final bool parseUrlOff;
  final List<String> uploadedAttachmentAids;
}

class NewThreadSubmissionResult {
  const NewThreadSubmissionResult({
    required this.tid,
    required this.pid,
    required this.message,
  });

  final String tid;
  final String pid;
  final String message;
}
