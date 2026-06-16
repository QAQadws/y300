/// 把用户态 tags（来自 chip 输入或草稿恢复）规整成可以直接进入提交载荷的列表。
///
/// 规则集中放在这里，避免 controller / page widget / payload builder 各自
/// 复述一遍 trim / dedupe / 截断的边界条件。规则：
///
/// 1. 每个 tag 先 trim；空字符串丢弃。
/// 2. 单 tag 长度超过 [maxTagLength] 整条丢弃（不截断——避免悄无声息地改写
///    用户输入；UI 端按 maxTagLength 校验拒绝输入更友好）。
/// 3. 保序去重——按"首次出现"保留。Discuz `tags` 字段不允许重复，重复会
///    被服务端忽略；本地 dedupe 让 chip 计数与最终发出的一致。
/// 4. 数量超过 [maxTagsCount] 时只保留前 [maxTagsCount] 个。
class NewThreadTagsNormalizer {
  const NewThreadTagsNormalizer({
    this.maxTagLength = 16,
    this.maxTagsCount = 5,
  });

  /// 单 tag 最大字符数。Discuz 不同站点上限不一，16 是常见设置；
  /// 真站点要求更短时仍由服务端兜底（响应里会回退到自动截断的 tag）。
  final int maxTagLength;

  /// 最多保留几个 tag。
  final int maxTagsCount;

  List<String> normalize(Iterable<String> raw) {
    final result = <String>[];
    final seen = <String>{};
    for (final tag in raw) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length > maxTagLength) continue;
      if (!seen.add(trimmed)) continue;
      result.add(trimmed);
      if (result.length >= maxTagsCount) break;
    }
    return result;
  }
}
