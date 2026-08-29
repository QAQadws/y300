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

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
