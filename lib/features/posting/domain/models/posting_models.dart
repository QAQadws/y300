// 发帖相关领域模型。
//
// Phase 5+ 在原"普通发帖"基础上新增了两条扩展轴：
//   1. tags：主题标签，独立于 special 类型；普通帖与投票帖都可携带。
//   2. special：主题特殊类型；本期只覆盖 normal / poll，预留 enum 让未来加
//      goods / reward / activity 时 payload builder 走多分支而非到处 if-else。
//
// `sortid` / `typeoption[...]` / `pollimage[...]` / 验证码仍未实装：模型不持有
// 这些字段，避免假象的"已支持"，落点见 `docs/发帖资料搜集.md`。

/// 主题"特殊类型"。映射到 Discuz `special` 表单字段。
enum NewThreadSpecial {
  /// 普通主题（special=0）。
  normal,

  /// 投票主题（special=1）。
  poll,
  // 预留：goods=2 / reward=3 / activity=4 / debate=5
}

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

/// 投票草稿。仅当 [NewThreadSpecial.poll] 时才被构造与序列化。
///
/// 字段命名贴合 Discuz form：
/// - [options]：用户当前键入的选项（按列表顺序），UI 删除后立刻从列表移除；
///   trim / 丢空 / 数量截断等"边界规整"由 [NewThreadPollNormalizer] 在
///   payload builder 阶段统一做，state 只持有"原始可编辑状态"。
/// - [multiple]：true → 多选（form 字段 maxchoices ≥ 2）；false → 单选
///   （强制 maxchoices=1）。
/// - [maxChoices]：[multiple] 为 true 时生效，对应 form `maxchoices`。
/// - [expirationDays]：截止天数，0 = 不过期，对应 form `expiration`。
/// - [overt]：是否公开投票人，对应 form `overt`。
/// - [visibilityPoll]：是否投票后才能看结果，对应 form `visibilitypoll`。
class NewThreadPollDraft {
  const NewThreadPollDraft({
    this.options = const <String>[],
    this.multiple = false,
    this.maxChoices = 1,
    this.expirationDays = 0,
    this.overt = false,
    this.visibilityPoll = false,
  });

  final List<String> options;
  final bool multiple;
  final int maxChoices;
  final int expirationDays;
  final bool overt;
  final bool visibilityPoll;

  /// 空白草稿；segmented 切到投票时由 controller 用作初始值。
  static const NewThreadPollDraft empty = NewThreadPollDraft();

  NewThreadPollDraft copyWith({
    List<String>? options,
    bool? multiple,
    int? maxChoices,
    int? expirationDays,
    bool? overt,
    bool? visibilityPoll,
  }) {
    return NewThreadPollDraft(
      options: options ?? this.options,
      multiple: multiple ?? this.multiple,
      maxChoices: maxChoices ?? this.maxChoices,
      expirationDays: expirationDays ?? this.expirationDays,
      overt: overt ?? this.overt,
      visibilityPoll: visibilityPoll ?? this.visibilityPoll,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! NewThreadPollDraft) return false;
    return other.multiple == multiple &&
        other.maxChoices == maxChoices &&
        other.expirationDays == expirationDays &&
        other.overt == overt &&
        other.visibilityPoll == visibilityPoll &&
        _listEquals(other.options, options);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(options),
        multiple,
        maxChoices,
        expirationDays,
        overt,
        visibilityPoll,
      );
}

/// 投票领域校验阈值。集中放在值对象上，让 state.canSubmit 与
/// preflight / normalizer / 测试共享同一组常量。
abstract class NewThreadPollValidation {
  /// Discuz 投票最少 2 个选项，少于 2 个发不了。
  static const int minOptions = 2;

  /// 上限 20 是 Discuz 默认配置，不同站点可能允许更多；本地兜底防误传，
  /// 真发出去超过站点上限时由服务端报 `post_pollinvalid` 接管。
  static const int maxOptions = 20;

  /// 单选项最大字符数；过长服务端会截断，本地兜底校验给用户更清晰的反馈。
  static const int maxOptionLength = 80;
}

/// 发帖提交载荷。
///
/// 由 controller + payload builder 组装，仓储层只负责 form-urlencoded 序列化。
/// `typeid='0'` 表示"无分类"。`tags` 为空时序列化层不写 `tags=` 字段。
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
    this.tags = const <String>[],
    this.special = NewThreadSpecial.normal,
    this.poll,
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

  /// 主题标签；空表示用户未填。表单层只在非空时写 `tags=join(',')`。
  final List<String> tags;

  /// 主题特殊类型；表单层据此走两条 strategy。默认 normal 保证旧调用方零回归。
  final NewThreadSpecial special;

  /// 投票配置；仅当 [special] == [NewThreadSpecial.poll] 时非空。
  /// builder 强制保证 invariant，序列化层信任之。
  final NewThreadPollDraft? poll;
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

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
