class ReplyAttachBbCodeService {
  const ReplyAttachBbCodeService();

  static final RegExp _attachPattern = RegExp(
    r'\[attach\]([^\[]*)\[/attach\]',
    caseSensitive: false,
  );

  String attachCode(String aid) {
    return '[attach]${aid.trim()}[/attach]';
  }

  List<String> extractAttachAids(String message) {
    if (message.isEmpty) {
      return const <String>[];
    }
    return [
      for (final match in _attachPattern.allMatches(message))
        if ((match.group(1) ?? '').trim().isNotEmpty)
          (match.group(1) ?? '').trim(),
    ];
  }

  String appendAttachCodes(String message, List<String> aids) {
    final normalizedAids = aids
        .map((aid) => aid.trim())
        .where((aid) => aid.isNotEmpty)
        .toList(growable: false);
    if (normalizedAids.isEmpty) {
      return message;
    }

    final attachLines = normalizedAids.map(attachCode).join('\n');
    if (message.isEmpty) {
      return attachLines;
    }
    if (message.endsWith('\n')) {
      return '$message$attachLines';
    }
    return '$message\n$attachLines';
  }

  String removeAttachCodes(String message, Iterable<String> aids) {
    final normalizedAids = aids
        .map((aid) => aid.trim())
        .where((aid) => aid.isNotEmpty)
        .toSet();
    if (message.isEmpty || normalizedAids.isEmpty) {
      return message;
    }

    final lines = message.split('\n');
    final kept = <String>[];
    for (final line in lines) {
      final aid = _exclusiveAttachAid(line);
      if (aid != null && normalizedAids.contains(aid)) {
        continue;
      }
      kept.add(line);
    }
    return kept.join('\n');
  }

  String? _exclusiveAttachAid(String line) {
    final match = RegExp(
      r'^\s*\[attach\]([^\[]+)\[/attach\]\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    return match?.group(1)?.trim();
  }
}
