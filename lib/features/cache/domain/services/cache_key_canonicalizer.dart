import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

class CacheKeyCanonicalizer {
  const CacheKeyCanonicalizer();

  static const String forumDisplaySnapshotType = 'forum.display';
  static const String forumHomeSnapshotType = 'forum.home';
  static const String threadDetailSnapshotType = 'thread.detail';

  DocumentCacheDescriptor forumHome({
    DocumentRequestProfile requestProfile = DocumentRequestProfile.loggedIn,
  }) {
    final canonicalParameters = _canonicalQueryParameters(
      const <String, String>{'mobile': '2'},
    );
    final uri = Uri.parse(
      AppConfig.siteBaseUrl,
    ).replace(path: '/index.php', queryParameters: canonicalParameters);
    return DocumentCacheDescriptor(
      cacheKey: _canonicalKey(
        namespace: CacheNamespace.document,
        ownerType: CacheOwnerType.forum,
        ownerId: 'home',
        requestProfile: requestProfile,
        uri: uri,
      ),
      ownerType: CacheOwnerType.forum,
      ownerId: 'home',
      sourceUrl: uri.toString(),
      requestProfile: requestProfile,
    );
  }

  DocumentCacheDescriptor threadDetail({
    required String tid,
    required int page,
    Map<String, String> queryParameters = const <String, String>{},
    DocumentRequestProfile requestProfile = DocumentRequestProfile.loggedIn,
  }) {
    final canonicalParameters = _canonicalQueryParameters(<String, String>{
      ...queryParameters,
      'mod': 'viewthread',
      'tid': tid,
      'page': page.toString(),
      'mobile': '2',
    });
    final uri = Uri.parse(
      AppConfig.siteBaseUrl,
    ).replace(path: '/forum.php', queryParameters: canonicalParameters);
    final key = _canonicalKey(
      namespace: CacheNamespace.document,
      ownerType: CacheOwnerType.thread,
      ownerId: _threadOwnerId(
        tid: tid,
        page: page,
        params: canonicalParameters,
      ),
      requestProfile: requestProfile,
      uri: uri,
    );
    return DocumentCacheDescriptor(
      cacheKey: key,
      ownerType: CacheOwnerType.thread,
      ownerId: _threadOwnerId(
        tid: tid,
        page: page,
        params: canonicalParameters,
      ),
      sourceUrl: uri.toString(),
      requestProfile: requestProfile,
    );
  }

  DocumentCacheDescriptor forumDisplay({
    required String fid,
    required int page,
    Map<String, String> queryParameters = const <String, String>{},
    DocumentRequestProfile requestProfile = DocumentRequestProfile.loggedIn,
  }) {
    final canonicalParameters = _canonicalQueryParameters(<String, String>{
      ...queryParameters,
      'mod': 'forumdisplay',
      'fid': fid,
      'mobile': '2',
      if (page > 1) 'page': page.toString(),
    });
    final uri = Uri.parse(
      AppConfig.siteBaseUrl,
    ).replace(path: '/forum.php', queryParameters: canonicalParameters);
    final ownerId = _forumDisplayOwnerId(
      fid: fid,
      page: page,
      params: canonicalParameters,
    );
    return DocumentCacheDescriptor(
      cacheKey: _canonicalKey(
        namespace: CacheNamespace.document,
        ownerType: CacheOwnerType.forumDisplay,
        ownerId: ownerId,
        requestProfile: requestProfile,
        uri: uri,
      ),
      ownerType: CacheOwnerType.forumDisplay,
      ownerId: ownerId,
      sourceUrl: uri.toString(),
      requestProfile: requestProfile,
    );
  }

  SnapshotCacheDescriptor threadDetailSnapshot({
    required String tid,
    required int page,
    Map<String, String> queryParameters = const <String, String>{},
    DocumentRequestProfile requestProfile = DocumentRequestProfile.loggedIn,
  }) {
    final document = threadDetail(
      tid: tid,
      page: page,
      queryParameters: queryParameters,
      requestProfile: requestProfile,
    );
    return SnapshotCacheDescriptor(
      cacheKey: document.cacheKey.replaceFirst(
        '${CacheNamespace.document.id}|',
        '${CacheNamespace.snapshot.id}|',
      ),
      ownerType: document.ownerType,
      ownerId: document.ownerId,
      snapshotType: threadDetailSnapshotType,
      sourceDocumentKey: document.cacheKey,
    );
  }

  SnapshotCacheDescriptor forumHomeSnapshot({
    DocumentRequestProfile requestProfile = DocumentRequestProfile.loggedIn,
  }) {
    final document = forumHome(requestProfile: requestProfile);
    return SnapshotCacheDescriptor(
      cacheKey: document.cacheKey.replaceFirst(
        '${CacheNamespace.document.id}|',
        '${CacheNamespace.snapshot.id}|',
      ),
      ownerType: document.ownerType,
      ownerId: document.ownerId,
      snapshotType: forumHomeSnapshotType,
      sourceDocumentKey: document.cacheKey,
    );
  }

  SnapshotCacheDescriptor forumDisplaySnapshot({
    required String fid,
    required int page,
    Map<String, String> queryParameters = const <String, String>{},
    DocumentRequestProfile requestProfile = DocumentRequestProfile.loggedIn,
  }) {
    final document = forumDisplay(
      fid: fid,
      page: page,
      queryParameters: queryParameters,
      requestProfile: requestProfile,
    );
    return SnapshotCacheDescriptor(
      cacheKey: document.cacheKey.replaceFirst(
        '${CacheNamespace.document.id}|',
        '${CacheNamespace.snapshot.id}|',
      ),
      ownerType: document.ownerType,
      ownerId: document.ownerId,
      snapshotType: forumDisplaySnapshotType,
      sourceDocumentKey: document.cacheKey,
    );
  }

  Map<String, String> _canonicalQueryParameters(Map<String, String> params) {
    final normalized = <String, String>{};
    for (final entry in params.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      normalized[key] = value;
    }
    final sortedKeys = normalized.keys.toList()..sort();
    return <String, String>{
      for (final key in sortedKeys) key: normalized[key]!,
    };
  }

  String _threadOwnerId({
    required String tid,
    required int page,
    required Map<String, String> params,
  }) {
    final variants = <String>[
      'tid=$tid',
      'page=$page',
      if (params.containsKey('authorid')) 'authorid=${params['authorid']}',
      if (params.containsKey('ordertype')) 'ordertype=${params['ordertype']}',
    ];
    return variants.join('&');
  }

  String _forumDisplayOwnerId({
    required String fid,
    required int page,
    required Map<String, String> params,
  }) {
    final variants = <String>[
      'fid=$fid',
      'page=$page',
      for (final entry in params.entries)
        if (entry.key != 'mod' &&
            entry.key != 'mobile' &&
            entry.key != 'fid' &&
            entry.key != 'page')
          '${entry.key}=${entry.value}',
    ];
    return variants.join('&');
  }

  String _canonicalKey({
    required CacheNamespace namespace,
    required CacheOwnerType ownerType,
    required String ownerId,
    required DocumentRequestProfile requestProfile,
    required Uri uri,
  }) {
    return [
      namespace.id,
      ownerType.id,
      ownerId,
      requestProfile.id,
      uri.replace(
        queryParameters: _canonicalQueryParameters(uri.queryParameters),
      ),
    ].join('|');
  }
}
