import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';

final class FavoriteForumDirectoryApiMapper {
  const FavoriteForumDirectoryApiMapper();

  FavoriteForumDirectoryData mapVariables(JsonMap variables) {
    final rawItems = variables['list'];
    if (rawItems is! List) {
      throw const FormatException('favorite forum list is missing');
    }

    final forumIds = <String>{};
    final remoteFavoriteIds = <String>{};
    final items = <FavoriteForumEntry>[];
    for (final rawItem in rawItems) {
      final item = _mapForum(_requiredMap(rawItem));
      if (!forumIds.add(item.fid)) {
        throw const FormatException('favorite forum identity is duplicated');
      }
      final remoteFavoriteId = item.remoteFavoriteId;
      if (remoteFavoriteId != null &&
          !remoteFavoriteIds.add(remoteFavoriteId)) {
        throw const FormatException(
          'favorite forum remote identity is duplicated',
        );
      }
      items.add(item);
    }
    return FavoriteForumDirectoryData(items: items);
  }

  FavoriteForumEntry _mapForum(JsonMap json) {
    return FavoriteForumEntry(
      fid: _requiredString(json['id'], 'favorite forum fid'),
      title: _requiredString(json['title'], 'favorite forum title'),
      remoteFavoriteId: _nullableString(json['favid']),
      description: _nullableString(json['description']),
      threadCount: _nullableNonNegativeIntField(
        json,
        'threads',
        'thread count',
      ),
      postCount: _nullableNonNegativeIntField(json, 'posts', 'post count'),
      todayPostCount: _nullableNonNegativeIntField(
        json,
        'todayposts',
        'today post count',
      ),
    );
  }
}

final class FavoriteThreadDirectoryApiMapper {
  const FavoriteThreadDirectoryApiMapper();

  FavoriteThreadDirectoryData mapVariables(
    JsonMap variables, {
    required int requestedPage,
  }) {
    final rawItems = variables['list'];
    if (rawItems is! List) {
      throw const FormatException('favorite thread list is missing');
    }
    final pageSize = _requiredNonNegativeInt(
      variables['perpage'],
      'favorite thread page size',
    );
    if (pageSize == 0) {
      throw const FormatException('favorite thread page size is invalid');
    }
    final totalItems = _requiredNonNegativeInt(
      variables['count'],
      'favorite thread total count',
    );
    final totalPages = totalItems == 0 ? 1 : (totalItems / pageSize).ceil();
    if (requestedPage > totalPages) {
      throw const FormatException('favorite thread page is out of range');
    }
    final expectedItemCount = totalItems == 0
        ? 0
        : requestedPage < totalPages
        ? pageSize
        : totalItems - ((requestedPage - 1) * pageSize);
    if (rawItems.length != expectedItemCount) {
      throw const FormatException('favorite thread pagination is inconsistent');
    }

    final threadIds = <String>{};
    final remoteFavoriteIds = <String>{};
    final items = <FavoriteThreadReference>[];
    for (final rawItem in rawItems) {
      final item = _mapThread(_requiredMap(rawItem));
      if (!threadIds.add(item.tid)) {
        throw const FormatException('favorite thread identity is duplicated');
      }
      final remoteFavoriteId = item.remoteFavoriteId;
      if (remoteFavoriteId != null &&
          !remoteFavoriteIds.add(remoteFavoriteId)) {
        throw const FormatException(
          'favorite thread remote identity is duplicated',
        );
      }
      items.add(item);
    }

    return FavoriteThreadDirectoryData(
      items: items,
      pagination: FavoriteThreadPagination(
        currentPage: requestedPage,
        pageSize: pageSize,
        totalItems: totalItems,
        totalPages: totalPages,
        hasPrevious: requestedPage > 1,
        hasNext: requestedPage * pageSize < totalItems,
      ),
    );
  }

  FavoriteThreadReference _mapThread(JsonMap json) {
    return FavoriteThreadReference(
      tid: _requiredString(json['id'], 'favorite thread tid'),
      title: _requiredString(json['title'], 'favorite thread title'),
      remoteFavoriteId: _nullableString(json['favid']),
      description: _nullableString(json['description']),
      authorName: _nullableString(json['author']),
      replyCount: _nullableNonNegativeIntField(json, 'replies', 'reply count'),
      favoritedAt: _nullableEpochSecondsField(json, 'dateline'),
    );
  }
}

JsonMap _requiredMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
    );
  }
  throw const FormatException('favorite directory item is invalid');
}

String _requiredString(Object? value, String field) {
  final result = _nullableString(value);
  if (result == null) {
    throw FormatException('$field is missing');
  }
  return result;
}

String? _nullableString(Object? value) {
  if (value == null) {
    return null;
  }
  final result = value.toString().trim();
  return result.isEmpty ? null : result;
}

int _requiredNonNegativeInt(Object? value, String field) {
  if (value == null) {
    throw FormatException('$field is missing');
  }
  return _strictNonNegativeInt(value, field);
}

int? _nullableNonNegativeIntField(JsonMap json, String key, String field) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  return _strictNonNegativeInt(json[key], field);
}

int _strictNonNegativeInt(Object? value, String field) {
  final raw = value.toString().trim();
  if (!RegExp(r'^\d+$').hasMatch(raw)) {
    throw FormatException('$field is invalid');
  }
  final parsed = int.tryParse(raw);
  if (parsed == null) {
    throw FormatException('$field is invalid');
  }
  return parsed;
}

DateTime? _nullableEpochSecondsField(JsonMap json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  final seconds = _strictNonNegativeInt(json[key], 'favorite timestamp');
  if (seconds == 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(
    seconds * Duration.millisecondsPerSecond,
    isUtc: true,
  );
}
