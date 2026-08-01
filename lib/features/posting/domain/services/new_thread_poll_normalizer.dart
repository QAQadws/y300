import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 把用户态投票草稿规整成可以直接进入提交载荷的形态。
///
/// 单一职责：把 UI 端可能松散的输入（空白选项、负的截止天数、单选模式下
/// maxChoices 还是 5 之类）按 Discuz 的语义统一收敛。规则不放进
/// [NewThreadPollDraft] 的 ctor 里，是因为草稿编辑过程中"暂时不合法"是合法状态
/// （比如刚加完一个空白选项还没填字），不应该被构造期间擦掉。
class NewThreadPollNormalizer {
  const NewThreadPollNormalizer();

  /// [raw] 为 null 时返回 [NewThreadPollDraft.empty]，让序列化层得到一个
  /// 完整 invariant 的对象（API 不会因为缺字段直接 500，但会把整张表单当
  /// "投票配置无效"打回）。
  NewThreadPollDraft normalize(NewThreadPollDraft? raw) {
    final source = raw ?? NewThreadPollDraft.empty;

    final cleanedOptions = <String>[];
    for (final option in source.options) {
      final trimmed = option.trim();
      if (trimmed.isEmpty) continue;
      cleanedOptions.add(trimmed);
      if (cleanedOptions.length >= NewThreadPollValidation.maxOptions) break;
    }

    final expirationDays = source.expirationDays < 0
        ? 0
        : source.expirationDays;

    if (!source.multiple) {
      // 单选模式下 maxChoices 始终为 1，避免草稿恢复的旧值串上去。
      return source.copyWith(
        options: cleanedOptions,
        maxChoices: 1,
        expirationDays: expirationDays,
      );
    }

    // 多选模式下 maxChoices 至少 2；超过实际选项数量时夹到选项数量。
    final upperBound = cleanedOptions.isEmpty ? 2 : cleanedOptions.length;
    final maxChoices = source.maxChoices < 2
        ? 2
        : (source.maxChoices > upperBound ? upperBound : source.maxChoices);

    return source.copyWith(
      options: cleanedOptions,
      maxChoices: maxChoices,
      expirationDays: expirationDays,
    );
  }
}
