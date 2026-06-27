import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';

class CacheKeyCanonicalizer {
  const CacheKeyCanonicalizer();

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
