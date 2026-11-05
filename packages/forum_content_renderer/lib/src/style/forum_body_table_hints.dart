import 'forum_body_length.dart';

final _dimension = RegExp(r'^[\t\n\f\r ]*([0-9]+(?:\.[0-9]*)?)(%)?');
final _integer = RegExp(r'^[\t\n\f\r ]*([+-]?[0-9]+)');

/// Table presentation attributes have their own HTML dimension syntax. CSS
/// declarations continue to use the shared CSS length parser and cascade.
ForumBodyLength? forumBodyTableDimension(
  String? raw, {
  bool ignoreZero = false,
}) {
  final match = raw == null ? null : _dimension.firstMatch(raw);
  final number = match == null ? null : double.tryParse(match[1]!);
  if (number == null || !number.isFinite || (ignoreZero && number == 0)) {
    return null;
  }
  return ForumBodyLength(
    number,
    match![2] == null ? ForumBodyLengthUnit.px : ForumBodyLengthUnit.percent,
  );
}

double? forumBodyTablePixelAttribute(String? raw) {
  final token = raw == null ? null : _integer.firstMatch(raw)?[1];
  final number = token == null ? null : double.tryParse(token);
  return number != null && number.isFinite && number >= 0 ? number : null;
}

ForumBodyLength forumBodyTableCellPadding(String? raw) =>
    ForumBodyLength(forumBodyTablePixelAttribute(raw) ?? 1);
