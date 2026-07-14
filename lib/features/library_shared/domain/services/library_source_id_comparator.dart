/// 按数值语义比较论坛来源标识，兼容缺失或非数字的旧数据。
int compareLibrarySourceIds(String? left, String? right) {
  final normalizedLeft = left?.trim() ?? '';
  final normalizedRight = right?.trim() ?? '';
  final leftNumber = int.tryParse(normalizedLeft);
  final rightNumber = int.tryParse(normalizedRight);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  if (leftNumber != null) {
    return -1;
  }
  if (rightNumber != null) {
    return 1;
  }
  return normalizedLeft.compareTo(normalizedRight);
}
