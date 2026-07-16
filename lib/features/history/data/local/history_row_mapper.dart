import 'package:y300/features/history/domain/models/history_models.dart';

class HistoryRowMapper {
  const HistoryRowMapper();

  Map<String, Object?> toRow(HistoryEntry entry) {
    return <String, Object?>{
      'target_type': encodeTargetType(entry.target.type),
      'target_id': entry.target.id,
      'title': entry.title,
      'context_label': entry.contextLabel,
      'thumbnail_local_path': entry.thumbnail?.localPath,
      'thumbnail_remote_url': entry.thumbnail?.remoteUrl,
      'thumbnail_focus_x': entry.thumbnail?.focusX,
      'thumbnail_focus_y': entry.thumbnail?.focusY,
      'source_tid': entry.sourceTid,
      'canonical_url': entry.canonicalUri?.toString(),
      'last_page': entry.lastPage,
      'forum_name': entry.forumName,
      'last_surface': encodeVisitSurface(entry.lastSurface),
      'first_visited_at': entry.firstVisitedAt.toUtc().millisecondsSinceEpoch,
      'last_visited_at': entry.lastVisitedAt.toUtc().millisecondsSinceEpoch,
      'visit_count': entry.visitCount,
    };
  }

  HistoryEntry fromRow(Map<String, Object?> row) {
    final localPath = row['thumbnail_local_path'] as String?;
    final remoteUrl = row['thumbnail_remote_url'] as String?;
    final thumbnail = localPath == null && remoteUrl == null
        ? null
        : HistoryThumbnailSnapshot(
            localPath: localPath,
            remoteUrl: remoteUrl,
            focusX: _nullableDouble(row['thumbnail_focus_x']),
            focusY: _nullableDouble(row['thumbnail_focus_y']),
          );
    final canonicalValue = row['canonical_url'] as String?;
    final canonicalUri = canonicalValue == null
        ? null
        : Uri.tryParse(canonicalValue);

    return HistoryEntry(
      target: HistoryTargetKey(
        type: decodeTargetType(_requiredString(row, 'target_type')),
        id: _requiredString(row, 'target_id'),
      ),
      title: _requiredString(row, 'title'),
      contextLabel: _requiredString(row, 'context_label'),
      thumbnail: thumbnail,
      sourceTid: row['source_tid'] as String?,
      canonicalUri: canonicalUri,
      lastPage: _nullableInt(row['last_page']),
      forumName: row['forum_name'] as String?,
      lastSurface: decodeVisitSurface(_requiredString(row, 'last_surface')),
      firstVisitedAt: _dateTime(row, 'first_visited_at'),
      lastVisitedAt: _dateTime(row, 'last_visited_at'),
      visitCount: _requiredInt(row, 'visit_count'),
    );
  }

  String encodeTargetType(HistoryTargetType value) => value.name;

  HistoryTargetType decodeTargetType(String value) {
    for (final candidate in HistoryTargetType.values) {
      if (candidate.name == value) {
        return candidate;
      }
    }
    throw FormatException('Unknown history target type: $value');
  }

  String encodeVisitSurface(HistoryVisitSurface value) => value.name;

  HistoryVisitSurface decodeVisitSurface(String value) {
    for (final candidate in HistoryVisitSurface.values) {
      if (candidate.name == value) {
        return candidate;
      }
    }
    throw FormatException('Unknown history visit surface: $value');
  }

  String _requiredString(Map<String, Object?> row, String column) {
    final value = row[column];
    if (value is String) {
      return value;
    }
    throw FormatException('Invalid $column in history row');
  }

  int _requiredInt(Map<String, Object?> row, String column) {
    final value = _nullableInt(row[column]);
    if (value != null) {
      return value;
    }
    throw FormatException('Invalid $column in history row');
  }

  int? _nullableInt(Object? value) => value is num ? value.toInt() : null;

  double? _nullableDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  DateTime _dateTime(Map<String, Object?> row, String column) {
    return DateTime.fromMillisecondsSinceEpoch(
      _requiredInt(row, column),
      isUtc: true,
    );
  }
}
