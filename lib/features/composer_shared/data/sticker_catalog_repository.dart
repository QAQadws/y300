import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_code_normalizer.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_image_resolver.dart';

abstract class StickerCatalogRepository {
  Future<List<StickerGroup>> loadStickerGroups();

  Future<StickerCatalogRefreshResult> refreshStickerGroups() async {
    final groups = await loadStickerGroups();
    return StickerCatalogRefreshResult(groups: groups, refreshed: false);
  }
}

class StickerCatalogRefreshResult {
  const StickerCatalogRefreshResult({
    required this.groups,
    required this.refreshed,
  });

  final List<StickerGroup> groups;
  final bool refreshed;
}

abstract class StickerCatalogRemoteDataSource {
  Future<StickerCatalogPayload> fetch();
}

class StickerCatalogPayload {
  const StickerCatalogPayload({
    required this.raw,
    required this.fetchedAt,
    required this.module,
    required this.version,
  });

  final Map<String, Object?> raw;
  final DateTime fetchedAt;
  final String module;
  final String version;
}

class YamiboStickerCatalogRemoteDataSource
    implements StickerCatalogRemoteDataSource {
  const YamiboStickerCatalogRemoteDataSource({
    required YamiboHttpGateway gateway,
    this.module = 'smiley',
    this.version = AppConfig.defaultApiVersion,
  }) : _gateway = gateway;

  final YamiboHttpGateway _gateway;
  final String module;
  final String version;

  @override
  Future<StickerCatalogPayload> fetch() async {
    final uri = Uri.parse(AppConfig.apiBaseUrl).replace(
      queryParameters: <String, String>{'module': module, 'version': version},
    );
    final result = await _gateway.getJson(
      uri,
      context: YamiboRequestContext(
        kind: YamiboRequestKind.api,
        operation: 'composer.sticker.catalog',
        module: module,
      ),
    );
    return switch (result) {
      ApiSuccess(:final data) => StickerCatalogPayload(
        raw: ParseUtils.asMap(data.body),
        fetchedAt: DateTime.now(),
        module: module,
        version: version,
      ),
      ApiFailure(:final error) => throw StateError(error.message),
    };
  }
}

abstract class StickerCatalogCacheStore {
  Future<CachedStickerCatalog?> load();

  Future<void> save(CachedStickerCatalog catalog);

  Future<void> clear();
}

class CachedStickerCatalog {
  const CachedStickerCatalog({
    required this.raw,
    required this.fetchedAt,
    required this.module,
    required this.version,
    required this.payloadHash,
  });

  final Map<String, Object?> raw;
  final DateTime fetchedAt;
  final String module;
  final String version;
  final String payloadHash;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'raw': raw,
      'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      'module': module,
      'version': version,
      'payloadHash': payloadHash,
    };
  }

  static CachedStickerCatalog? fromJson(Object? value) {
    final map = ParseUtils.asMap(value);
    final raw = ParseUtils.asMap(map['raw']);
    if (raw.isEmpty) {
      return null;
    }
    final fetchedAt = ParseUtils.asInt(map['fetchedAt']);
    return CachedStickerCatalog(
      raw: raw,
      fetchedAt: fetchedAt <= 0
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(fetchedAt),
      module: ParseUtils.asString(map['module']).trim().isEmpty
          ? 'smiley'
          : ParseUtils.asString(map['module']).trim(),
      version: ParseUtils.asString(map['version']).trim().isEmpty
          ? AppConfig.defaultApiVersion
          : ParseUtils.asString(map['version']).trim(),
      payloadHash: ParseUtils.asString(map['payloadHash']),
    );
  }
}

class FileStickerCatalogCacheStore implements StickerCatalogCacheStore {
  const FileStickerCatalogCacheStore({Future<String> Function()? cacheFilePath})
    : _cacheFilePath = cacheFilePath ?? _defaultCacheFilePath;

  final Future<String> Function() _cacheFilePath;

  @override
  Future<CachedStickerCatalog?> load() async {
    final file = io.File(await _cacheFilePath());
    if (!await file.exists()) {
      return null;
    }
    try {
      return CachedStickerCatalog.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CachedStickerCatalog catalog) async {
    final file = io.File(await _cacheFilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(catalog.toJson()), flush: true);
  }

  @override
  Future<void> clear() async {
    final file = io.File(await _cacheFilePath());
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<String> _defaultCacheFilePath() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'cache', 'catalog', 'yamibo_smiley_v4.json');
  }
}

class RemoteStickerCatalogRepository implements StickerCatalogRepository {
  const RemoteStickerCatalogRepository({
    required StickerCatalogRemoteDataSource remoteDataSource,
    required StickerCatalogCacheStore cacheStore,
    required StickerCodeNormalizer normalizer,
    StickerImageResolver imageResolver = const StickerImageResolver(),
    this.freshFor = const Duration(days: 7),
  }) : _remoteDataSource = remoteDataSource,
       _cacheStore = cacheStore,
       _normalizer = normalizer,
       _imageResolver = imageResolver;

  final StickerCatalogRemoteDataSource _remoteDataSource;
  final StickerCatalogCacheStore _cacheStore;
  final StickerCodeNormalizer _normalizer;
  final StickerImageResolver _imageResolver;
  final Duration freshFor;

  @override
  Future<List<StickerGroup>> loadStickerGroups() async {
    final cached = await _cacheStore.load();
    if (cached != null && !_isStale(cached)) {
      return _parseCatalog(cached.raw);
    }
    try {
      return (await _refresh()).groups;
    } catch (_) {
      if (cached != null) {
        return _parseCatalog(cached.raw);
      }
      rethrow;
    }
  }

  @override
  Future<StickerCatalogRefreshResult> refreshStickerGroups() {
    return _refresh();
  }

  Future<StickerCatalogRefreshResult> _refresh() async {
    final payload = await _remoteDataSource.fetch();
    final raw = payload.raw;
    await _cacheStore.save(
      CachedStickerCatalog(
        raw: raw,
        fetchedAt: payload.fetchedAt,
        module: payload.module,
        version: payload.version,
        payloadHash: _hashPayload(raw),
      ),
    );
    return StickerCatalogRefreshResult(
      groups: _parseCatalog(raw),
      refreshed: true,
    );
  }

  bool _isStale(CachedStickerCatalog catalog) {
    final age = DateTime.now().difference(catalog.fetchedAt);
    return age > freshFor;
  }

  List<StickerGroup> _parseCatalog(Map<String, Object?> payload) {
    final variables = ParseUtils.asMap(payload['Variables']);
    final groups = ParseUtils.asList(variables['smilies']);
    return groups
        .map(_parseGroup)
        .where((group) => group.stickers.isNotEmpty)
        .toList(growable: false);
  }

  StickerGroup _parseGroup(Object? rawGroup) {
    final stickers = ParseUtils.asList(
      rawGroup,
    ).map(_parseSticker).whereType<StickerItem>().toList(growable: false);
    final imagePath = stickers.isEmpty ? null : stickers.first.imagePath;
    final groupId = imagePath == null
        ? 'unknown'
        : _groupIdFromImagePath(imagePath);
    final metadata = _metadataForGroupId(groupId);
    return StickerGroup(
      id: metadata.id,
      title: metadata.title,
      stickers: stickers,
    );
  }

  StickerItem? _parseSticker(Object? rawSticker) {
    final map = ParseUtils.asMap(rawSticker);
    final rawCodePattern = ParseUtils.asString(map['code']).trim();
    final imagePath = ParseUtils.asString(map['image']).trim();
    if (rawCodePattern.isEmpty || imagePath.isEmpty) {
      return null;
    }
    final imageSource = _imageResolver.resolve(imagePath);
    return StickerItem(
      code: _normalizer.normalize(rawCodePattern),
      rawCodePattern: rawCodePattern,
      imagePath: imageSource.normalizedPath,
      imageUrl: imageSource.url,
      cacheKey: imageSource.cacheKey,
    );
  }

  _StickerGroupMetadata _metadataForGroupId(String groupId) {
    for (final metadata in _knownGroupMetadata) {
      if (metadata.id == groupId) {
        return metadata;
      }
    }
    return _StickerGroupMetadata(id: groupId, title: groupId);
  }

  String _groupIdFromImagePath(String imagePath) {
    final normalized = _imageResolver.resolve(imagePath).normalizedPath;
    final slash = normalized.indexOf('/');
    if (slash <= 0) {
      return normalized.isEmpty ? 'unknown' : normalized;
    }
    return normalized.substring(0, slash);
  }

  String _hashPayload(Map<String, Object?> payload) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(jsonEncode(payload))) {
      hash = (hash ^ byte) * 0x100000001b3;
      hash = hash.toUnsigned(64);
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

const _knownGroupMetadata = <_StickerGroupMetadata>[
  _StickerGroupMetadata(id: 'default', title: '默认表情'),
  _StickerGroupMetadata(id: 'bugcat', title: '貓貓蟲'),
  _StickerGroupMetadata(id: 'coolmonkey', title: '企鹅表情'),
  _StickerGroupMetadata(id: 'gexing', title: '个性表情'),
  _StickerGroupMetadata(id: 'gexing2', title: '孤獨搖滾'),
  _StickerGroupMetadata(id: 'azukisan', title: '小豆泥'),
];

class _StickerGroupMetadata {
  const _StickerGroupMetadata({required this.id, required this.title});

  final String id;
  final String title;
}
