final _participantSuffix = RegExp(
  r'(?:^|[,，]\s*)共有\s*(\d+)\s*人[参參][与與]投票[。.]?'
  r'(?:\s*查看投票[参參][与與]人)?\s*$',
);

/// Extracts Discuz's trailing voterscount independently of option vote totals.
/// Desktop summaries may also append the view-voters link label.
({int? participantCount, String? rulesText}) parseDiscuzThreadPollSummary(
  String summary,
) {
  final match = _participantSuffix.firstMatch(summary);
  final count = int.tryParse(match?.group(1) ?? '');
  if (match == null || count == null) {
    return (participantCount: null, rulesText: null);
  }
  return (
    participantCount: count,
    rulesText: summary.substring(0, match.start).trim(),
  );
}
