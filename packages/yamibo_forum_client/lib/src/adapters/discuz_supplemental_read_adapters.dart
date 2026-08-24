import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/message_directories.dart';
import '../contracts/sticker_catalog.dart';
import '../contracts/thread_supplemental_reads.dart';
import '../contracts/thread_detail_models.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../parsing/loose_json.dart';
import 'discuz_api_client.dart';
import 'thread_detail_api_mapper.dart';
import 'thread_detail_html_parser.dart';

final class DiscuzForumNotificationRepository
    implements ForumNotificationRepository {
  const DiscuzForumNotificationRepository(this._api);
  final DiscuzApiClient _api;

  @override
  ForumNotificationSourceCapabilities get capabilities =>
      _notificationCapabilities;

  @override
  Future<
    DataReadResult<ForumNotificationPage, ForumNotificationReadCapabilities>
  >
  load(
    ForumNotificationQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final response = await _api.get(module: 'mynotelist');
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return _failure(failure);
    }
    try {
      final variables =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body
              .variables;
      final items = LooseJson.list(variables['list'])
          .map(LooseJson.map)
          .where((item) => item.isNotEmpty)
          .map(_notification)
          .toList(growable: false);
      _unique(items.map((item) => item.id), 'notification_identity_invalid');
      final page = _page(variables, items.length);
      return DataReadSuccess(
        data: ForumNotificationPage(
          items: List.unmodifiable(items),
          count: page.$1,
          page: page.$2,
          perPage: page.$3,
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _parseFailure('notification_parse_failed', error);
    }
  }

  ForumNotificationItem _notification(Map<String, Object?> item) {
    final id = LooseJson.string(item['id']).trim();
    if (id.isEmpty) throw const FormatException('notification_id_missing');
    final rawDateline = LooseJson.string(item['dateline']).trim();
    final seconds = int.tryParse(rawDateline);
    return ForumNotificationItem(
      id: id,
      type: LooseJson.string(item['type']).trim(),
      isNew: LooseJson.boolean(item['new']),
      authorId: LooseJson.string(item['authorid']).trim(),
      authorName: LooseJson.string(item['author']).trim(),
      noteMarkup: LooseJson.string(item['note']),
      occurredAt: seconds != null && seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
          : null,
      rawDateline: rawDateline,
    );
  }
}

final class DiscuzForumPrivateMessageRepository
    implements ForumPrivateMessageRepository {
  const DiscuzForumPrivateMessageRepository(this._api);
  final DiscuzApiClient _api;

  @override
  ForumPrivateMessageSourceCapabilities get capabilities =>
      _messageCapabilities;

  @override
  Future<
    DataReadResult<ForumPrivateMessagePage, ForumPrivateMessageReadCapabilities>
  >
  load(
    ForumPrivateMessageQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final response = await _api.get(module: 'mypm');
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return _failure(failure);
    }
    try {
      final variables =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body
              .variables;
      final items = LooseJson.list(variables['list'])
          .map(LooseJson.map)
          .where((item) => item.isNotEmpty)
          .map(_message)
          .toList(growable: false);
      _unique(
        items.map((item) => item.messageId),
        'private_message_identity_invalid',
      );
      final page = _page(variables, items.length);
      return DataReadSuccess(
        data: ForumPrivateMessagePage(
          items: List.unmodifiable(items),
          count: page.$1,
          page: page.$2,
          perPage: page.$3,
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _parseFailure('private_message_parse_failed', error);
    }
  }

  ForumPrivateMessageItem _message(Map<String, Object?> item) {
    final id = LooseJson.string(item['pmid']).trim();
    if (id.isEmpty) throw const FormatException('private_message_id_missing');
    final conversation = LooseJson.string(item['plid']).trim();
    final rawDateline = LooseJson.string(item['vdateline']).trim();
    return ForumPrivateMessageItem(
      messageId: id,
      conversationId: conversation.isEmpty ? null : conversation,
      isNew: LooseJson.boolean(item['isnew']),
      subject: LooseJson.string(item['subject']),
      fromUserId: LooseJson.string(item['msgfromid']).trim(),
      fromUserName: LooseJson.string(item['msgfrom']).trim(),
      toUserId: LooseJson.string(item['touid']).trim(),
      toUserName: LooseJson.string(item['tousername']).trim(),
      message: LooseJson.string(item['message']),
      sentAt: _parseDiscuzDateTime(rawDateline),
      rawDateline: rawDateline,
    );
  }
}

DateTime? _parseDiscuzDateTime(String source) {
  final value = source.trim();
  final seconds = int.tryParse(value);
  if (seconds != null && seconds > 0) {
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
  final match = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$',
  ).firstMatch(value);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.tryParse(match.group(4) ?? '') ?? 0,
    int.tryParse(match.group(5) ?? '') ?? 0,
    int.tryParse(match.group(6) ?? '') ?? 0,
  );
}

final class DiscuzForumStickerCatalogRepository
    implements ForumStickerCatalogRepository {
  DiscuzForumStickerCatalogRepository({
    required this.api,
    required this.config,
    this.store,
    this.freshFor = const Duration(days: 7),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DiscuzApiClient api;
  final ForumClientConfig config;
  final ForumStickerCatalogStore? store;
  final Duration freshFor;
  final DateTime Function() _now;

  @override
  ForumStickerCatalogSourceCapabilities get capabilities =>
      _stickerCapabilities;

  @override
  Future<
    DataReadResult<ForumStickerCatalogData, ForumStickerCatalogReadCapabilities>
  >
  load(
    ForumStickerCatalogQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final cached = await _cached();
    if (!query.forceRefresh &&
        cachePolicy == CacheLoadPolicy.cacheFirst &&
        cached != null &&
        _now().difference(cached.$2) <= freshFor) {
      return _success(cached.$1, refreshed: false, fresh: true);
    }
    final response = await api.get(
      module: 'smiley',
      queryParameters: const {'version': '4'},
    );
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      if (cached != null) {
        return _success(cached.$1, refreshed: false, fresh: false);
      }
      return _failure(failure);
    }
    try {
      final variables =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body
              .variables;
      final data = _mapStickers(variables, refreshed: true);
      await _write(variables);
      return DataReadSuccess(
        data: data,
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      if (cached != null) {
        return _success(cached.$1, refreshed: false, fresh: false);
      }
      return _parseFailure('sticker_catalog_parse_failed', error);
    }
  }

  Future<(Map<String, Object?>, DateTime)?> _cached() async {
    try {
      final encoded = await store?.read();
      if (encoded == null || encoded.trim().isEmpty) return null;
      final root = LooseJson.map(jsonDecode(encoded));
      final raw = LooseJson.map(root['raw']);
      final variables = raw.containsKey('Variables')
          ? LooseJson.map(raw['Variables'])
          : LooseJson.map(root['variables']);
      if (variables.isEmpty) return null;
      final timestamp = LooseJson.integer(root['fetchedAt']);
      return (
        variables,
        timestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(timestamp)
            : DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(Map<String, Object?> variables) async {
    try {
      await store?.write(
        jsonEncode(<String, Object?>{
          'raw': <String, Object?>{'Variables': variables},
          'fetchedAt': _now().millisecondsSinceEpoch,
          'module': 'smiley',
          'version': '4',
        }),
      );
    } catch (_) {}
  }

  DataReadResult<ForumStickerCatalogData, ForumStickerCatalogReadCapabilities>
  _success(
    Map<String, Object?> variables, {
    required bool refreshed,
    required bool fresh,
  }) {
    try {
      return DataReadSuccess(
        data: _mapStickers(variables, refreshed: refreshed),
        capabilities: capabilities.toReadCapabilities(),
        metadata: DataReadMetadata(
          origin: DataReadOrigin.freshSnapshot,
          freshness: fresh
              ? DataReadFreshness.freshCache
              : DataReadFreshness.staleOrUnknown,
        ),
      );
    } on FormatException catch (error) {
      return _parseFailure('sticker_catalog_parse_failed', error);
    }
  }

  ForumStickerCatalogData _mapStickers(
    Map<String, Object?> variables, {
    required bool refreshed,
  }) {
    final groups = <ForumStickerGroup>[];
    final groupIds = <String>{};
    for (final rawGroup in LooseJson.list(variables['smilies'])) {
      final items = <ForumStickerItem>[];
      for (final rawItem in LooseJson.list(rawGroup)) {
        final map = LooseJson.map(rawItem);
        final rawCode = LooseJson.string(map['code']).trim();
        final rawImage = LooseJson.string(map['image']).trim();
        if (rawCode.isEmpty || rawImage.isEmpty) continue;
        final path = _normalizeImagePath(rawImage);
        if (path.isEmpty) continue;
        items.add(
          ForumStickerItem(
            rawCodePattern: rawCode,
            insertionCode: _normalizeCode(rawCode),
            imagePath: path,
            imageUri: config.siteOrigin.replace(
              path: '/static/image/smiley/$path',
            ),
          ),
        );
      }
      if (items.isEmpty) continue;
      final id = items.first.imagePath.split('/').first;
      if (id.isEmpty || !groupIds.add(id)) {
        throw const FormatException('sticker_group_identity_invalid');
      }
      groups.add(ForumStickerGroup(id: id, items: List.unmodifiable(items)));
    }
    return ForumStickerCatalogData(
      groups: List.unmodifiable(groups),
      refreshed: refreshed,
    );
  }

  String _normalizeImagePath(String source) {
    var path = Uri.tryParse(source)?.path ?? source;
    const marker = '/static/image/smiley/';
    final markerIndex = path.indexOf(marker);
    if (markerIndex >= 0) path = path.substring(markerIndex + marker.length);
    return path.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '').trim();
  }

  String _normalizeCode(String raw) {
    var value = raw.trim();
    if (value.length >= 2 && value.startsWith('/') && value.endsWith('/')) {
      value = value.substring(1, value.length - 1);
    }
    return value
        .replaceAll(r'\{', '{')
        .replaceAll(r'\}', '}')
        .replaceAll(r'\:', ':');
  }
}

final class DiscuzThreadPostRatingsRepository
    implements ThreadPostRatingsRepository {
  DiscuzThreadPostRatingsRepository({
    required this.config,
    required this.network,
    required this.requestProfiles,
  });

  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;

  @override
  ThreadPostRatingsSourceCapabilities get capabilities => _ratingsCapabilities;

  @override
  Future<
    DataReadResult<ThreadPostRatingsData, ThreadPostRatingsReadCapabilities>
  >
  load(
    ThreadPostRatingsQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  }) async {
    if (!_positive(query.tid) || !_positive(query.pid)) {
      return _businessFailure('thread_post_ratings_query_invalid');
    }
    final uri = config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: {
        'mod': 'misc',
        'action': 'viewratings',
        'tid': query.tid,
        'pid': query.pid,
        'infloat': 'yes',
        'handlekey': 'viewratings',
        'inajax': '1',
        'ajaxtarget': 'fwin_content_viewratings',
      },
    );
    final referer = config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: {'mod': 'viewthread', 'tid': query.tid, 'mobile': '2'},
    );
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'thread.post.ratings',
          pageKind: 'thread.detail',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.desktopHtml, referer: referer)
            .headers,
      ),
    );
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _failure(failure);
    }
    try {
      final body = (response as ForumTransportSuccess<ForumResponse<Object?>>)
          .response
          .body;
      if (body is! String) throw const FormatException('ratings_text_expected');
      return DataReadSuccess(
        data: _parseRatings(body),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _parseFailure('thread_post_ratings_parse_failed', error);
    }
  }

  ThreadPostRatingsData _parseRatings(String source) {
    final match = RegExp(
      r'<root(?:\s[^>]*)?>[\s\S]*?<!\[CDATA\[([\s\S]*?)\]\]>[\s\S]*?</root\s*>',
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) throw const FormatException('ratings_cdata_missing');
    final document = html_parser.parse(match.group(1)!);
    final table = document.querySelector('.f_c table.list');
    if (table == null) throw const FormatException('ratings_table_missing');
    final rows = table.querySelectorAll('tr');
    final header = _ratingHeader(rows);
    if (header == null) throw const FormatException('ratings_header_missing');
    final ratings = <ThreadPostRating>[];
    final headerIndex = rows.indexOf(header.$1);
    for (final row in rows.skip(headerIndex + 1)) {
      final cells = _cells(row);
      final max = [
        header.$2,
        header.$3,
        header.$4,
      ].reduce((a, b) => a > b ? a : b);
      if (cells.length <= max) continue;
      final score = _clean(cells[header.$2].text);
      final userCell = cells[header.$3];
      final user = _clean(userCell.text);
      if (score.isEmpty || user.isEmpty) continue;
      final profile = userCell.querySelector('a')?.attributes['href'];
      ratings.add(
        ThreadPostRating(
          userName: user,
          userId: RegExp(
            r'(?:uid-|uid=)(\d+)',
          ).firstMatch(profile ?? '')?.group(1),
          score:
              RegExp(
                r'[+-]?\s*\d+',
              ).firstMatch(score)?.group(0)?.replaceAll(' ', '') ??
              score,
          dateline: _clean(cells[header.$4].text),
          reason: header.$5 >= 0 && cells.length > header.$5
              ? _clean(cells[header.$5].text)
              : '',
        ),
      );
    }
    if (ratings.isEmpty) throw const FormatException('ratings_items_missing');
    final total = _clean(
      document.querySelector('.o.pns')?.text ?? '',
    ).replaceFirst(RegExp(r'^总计\s*[:：]?\s*'), '').trim();
    return ThreadPostRatingsData(
      participantCount: ratings.length,
      totalScoreText: total.isEmpty ? _sumRatings(ratings) : total,
      ratings: List.unmodifiable(ratings),
    );
  }

  (html_dom.Element, int, int, int, int)? _ratingHeader(
    List<html_dom.Element> rows,
  ) {
    for (final row in rows) {
      final texts = _cells(row).map((cell) => _clean(cell.text)).toList();
      final score = texts.indexWhere((text) => text == '积分');
      final user = texts.indexWhere((text) => text.contains('用户名'));
      final time = texts.indexWhere((text) => text.contains('时间'));
      final reason = texts.indexWhere((text) => text.contains('理由'));
      if (score >= 0 && user >= 0 && time >= 0) {
        return (row, score, user, time, reason);
      }
    }
    return null;
  }

  List<html_dom.Element> _cells(html_dom.Element row) => row.children
      .where((child) => child.localName == 'td' || child.localName == 'th')
      .toList(growable: false);
  String _clean(String value) =>
      value.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  String _sumRatings(List<ThreadPostRating> ratings) {
    final scores = ratings
        .map(
          (item) => int.tryParse(
            RegExp(r'[+-]?\d+').firstMatch(item.score)?.group(0) ?? '',
          ),
        )
        .whereType<int>()
        .toList();
    if (scores.isEmpty) return '';
    final total = scores.fold<int>(0, (sum, value) => sum + value);
    return '积分 ${total > 0 ? '+$total' : total} 点';
  }
}

final class DiscuzThreadPostLocatorRepository
    implements ThreadPostLocatorRepository {
  DiscuzThreadPostLocatorRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    ThreadDetailHtmlParser? parser,
  }) : _config = config,
       _parser =
           parser ?? ThreadDetailHtmlParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final ThreadDetailHtmlParser _parser;

  @override
  ThreadPostLocatorSourceCapabilities get capabilities => _locatorCapabilities;

  @override
  Future<
    DataReadResult<ThreadPostLocationData, ThreadPostLocatorReadCapabilities>
  >
  locate(
    ThreadPostLocationQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  }) async {
    if (!_positive(query.tid) || !_positive(query.pid)) {
      return _businessFailure('thread_post_location_query_invalid');
    }
    final uri = _config.siteOrigin.replace(
      path: '/forum.php',
      queryParameters: {
        'mod': 'redirect',
        'goto': 'findpost',
        'ptid': query.tid,
        'pid': query.pid,
      },
    );
    final response = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'thread.post.locate',
          pageKind: 'thread.detail',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml)
            .headers,
      ),
    );
    if (response case ForumTransportError<ForumResponse<Object?>>(
      :final failure,
    )) {
      return _failure(failure);
    }
    try {
      final value =
          (response as ForumTransportSuccess<ForumResponse<Object?>>).response;
      if (!_sameSite(value.uri)) {
        throw const FormatException('thread_post_location_cross_site');
      }
      if (value.body is! String) {
        throw const FormatException('thread_post_location_text_expected');
      }
      final detail = _parser.parse(
        value.body as String,
        fallbackTid: query.tid,
        fallbackPage: _pageFromUri(value.uri) ?? 1,
      );
      if (detail.tid.trim() != query.tid ||
          !detail.posts.any((post) => post.pid.trim() == query.pid)) {
        throw const FormatException('thread_post_location_identity_mismatch');
      }
      return DataReadSuccess(
        data: ThreadPostLocationData(
          tid: query.tid,
          pid: query.pid,
          page: detail.currentPage <= 0 ? 1 : detail.currentPage,
          resolvedUri: value.uri,
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _parseFailure('thread_post_location_parse_failed', error);
    }
  }

  bool _sameSite(Uri uri) =>
      uri.scheme.toLowerCase() == _config.siteOrigin.scheme.toLowerCase() &&
      uri.host.toLowerCase() == _config.siteOrigin.host.toLowerCase() &&
      uri.port == _config.siteOrigin.port;

  int? _pageFromUri(Uri uri) {
    final queryPage = int.tryParse(uri.queryParameters['page'] ?? '');
    if (queryPage != null && queryPage > 0) return queryPage;
    final pathPage = RegExp(
      r'thread-\d+-(\d+)-',
    ).firstMatch(uri.path)?.group(1);
    final parsed = int.tryParse(pathPage ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

final class DiscuzThreadAuthorPostRepository
    implements ThreadAuthorPostRepository {
  const DiscuzThreadAuthorPostRepository(
    this._api, {
    this.mapper = const ThreadDetailApiMapper(),
  });

  final DiscuzApiClient _api;
  final ThreadDetailApiMapper mapper;

  @override
  ThreadAuthorPostSourceCapabilities get capabilities => _authorCapabilities;

  @override
  Future<DataReadResult<ThreadAuthorPostPage, ThreadAuthorPostReadCapabilities>>
  load(
    ThreadAuthorPostQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  }) async {
    if (!_positive(query.tid) ||
        !_positive(query.authorId) ||
        query.page < 1 ||
        query.pageSize < 1) {
      return _businessFailure('thread_author_post_query_invalid');
    }
    final response = await _api.get(
      module: 'viewthread',
      queryParameters: {
        'version': '1',
        'tid': query.tid,
        'page': query.page,
        'ppp': query.pageSize,
        'authorid': query.authorId,
      },
    );
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return _failure(failure);
    }
    try {
      final variables =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body
              .variables;
      final detail = mapper.mapVariables(variables, page: query.page);
      final ids = <String>{};
      final valid =
          detail.tid.trim() == query.tid &&
          detail.currentPage == query.page &&
          detail.posts.every(
            (post) =>
                post.pid.trim().isNotEmpty &&
                ids.add(post.pid.trim()) &&
                post.authorId.trim() == query.authorId,
          );
      if (!valid) {
        throw const FormatException('thread_author_post_identity_invalid');
      }
      return DataReadSuccess(
        data: ThreadAuthorPostPage(
          tid: detail.tid,
          subject: detail.subject,
          posts: List.unmodifiable(detail.posts),
          currentPage: detail.currentPage,
          pageSize: detail.perPage <= 0 ? query.pageSize : detail.perPage,
          totalReplyHint: detail.replies,
          hasNext: detail.hasMore,
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException catch (error) {
      return _parseFailure('thread_author_post_parse_failed', error);
    }
  }
}

(int, int, int) _page(Map<String, Object?> variables, int itemCount) {
  final count = LooseJson.integer(variables['count'], fallback: itemCount);
  final page = LooseJson.integer(variables['page'], fallback: 1);
  final perPage = LooseJson.integer(variables['perpage']);
  if (count < 0 || page < 1 || perPage < 0 || count < itemCount) {
    throw const FormatException('directory_pagination_invalid');
  }
  return (count, page, perPage);
}

void _unique(Iterable<String> ids, String code) {
  final seen = <String>{};
  for (final id in ids) {
    if (id.trim().isEmpty || !seen.add(id.trim())) throw FormatException(code);
  }
}

bool _positive(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value.trim());

DataReadFailure<T, C> _failure<T, C>(ForumTransportFailure failure) =>
    DataReadFailure(
      kind: toReadFailureKind(failure.kind),
      code: failure.code,
      statusCode: failure.statusCode,
      diagnosticMessage: failure.code,
    );
DataReadFailure<T, C> _parseFailure<T, C>(String code, Object error) =>
    DataReadFailure(
      kind: DataReadFailureKind.parse,
      code: code,
      diagnosticMessage: error is FormatException
          ? error.message.toString()
          : code,
    );
DataReadFailure<T, C> _businessFailure<T, C>(String code) => DataReadFailure(
  kind: DataReadFailureKind.business,
  code: code,
  diagnosticMessage: code,
);

final _notificationCapabilities = ForumNotificationSourceCapabilities(
  values: DataCapabilitySet.supported(ForumNotificationCapability.values),
);
final _messageCapabilities = ForumPrivateMessageSourceCapabilities(
  values: DataCapabilitySet.supported(ForumPrivateMessageCapability.values),
);
final _stickerCapabilities = ForumStickerCatalogSourceCapabilities(
  values: DataCapabilitySet.supported(ForumStickerCatalogCapability.values),
);
final _ratingsCapabilities = ThreadPostRatingsSourceCapabilities(
  values: DataCapabilitySet.supported(ThreadPostRatingsCapability.values),
);
final _locatorCapabilities = ThreadPostLocatorSourceCapabilities(
  values: DataCapabilitySet.supported(ThreadPostLocatorCapability.values),
);
final _authorCapabilities = ThreadAuthorPostSourceCapabilities(
  values: DataCapabilitySet.supported(ThreadAuthorPostCapability.values),
);
