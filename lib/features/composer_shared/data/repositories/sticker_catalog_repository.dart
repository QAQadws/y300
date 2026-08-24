import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    as forum;
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/domain/services/sticker_image_resolver.dart';

abstract class StickerCatalogRepository {
  Future<List<StickerGroup>> loadStickerGroups();

  Future<StickerCatalogRefreshResult> refreshStickerGroups();
}

class StickerCatalogRefreshResult {
  const StickerCatalogRefreshResult({
    required this.groups,
    required this.refreshed,
  });
  final List<StickerGroup> groups;
  final bool refreshed;
}

final class PackageStickerCatalogRepository
    implements StickerCatalogRepository {
  const PackageStickerCatalogRepository({
    required forum.ForumStickerCatalogRepository repository,
    StickerImageResolver imageResolver = const StickerImageResolver(),
  }) : _repository = repository,
       _imageResolver = imageResolver;

  final forum.ForumStickerCatalogRepository _repository;
  final StickerImageResolver _imageResolver;

  @override
  Future<List<StickerGroup>> loadStickerGroups() async {
    final result = await _repository.load(
      const forum.ForumStickerCatalogQuery(),
    );
    return _unwrap(result).groups;
  }

  @override
  Future<StickerCatalogRefreshResult> refreshStickerGroups() async {
    final result = await _repository.load(
      const forum.ForumStickerCatalogQuery(forceRefresh: true),
      cachePolicy: forum.CacheLoadPolicy.networkFirst,
    );
    final value = _unwrap(result);
    return StickerCatalogRefreshResult(
      groups: value.groups,
      refreshed: value.refreshed,
    );
  }

  _ProjectedStickerCatalog _unwrap(
    forum.DataReadResult<
      forum.ForumStickerCatalogData,
      forum.ForumStickerCatalogReadCapabilities
    >
    result,
  ) {
    if (result case forum.DataReadFailure<
      forum.ForumStickerCatalogData,
      forum.ForumStickerCatalogReadCapabilities
    >(
      :final diagnosticMessage,
    )) {
      throw StateError(diagnosticMessage);
    }
    final data =
        (result
                as forum.DataReadSuccess<
                  forum.ForumStickerCatalogData,
                  forum.ForumStickerCatalogReadCapabilities
                >)
            .data;
    return _ProjectedStickerCatalog(
      refreshed: data.refreshed,
      groups: [
        for (final group in data.groups)
          StickerGroup(
            id: group.id,
            title: _title(group.id),
            stickers: [for (final item in group.items) _sticker(item)],
          ),
      ],
    );
  }

  StickerItem _sticker(forum.ForumStickerItem item) {
    final source = _imageResolver.resolve(item.imagePath);
    return StickerItem(
      code: item.insertionCode,
      rawCodePattern: item.rawCodePattern,
      imagePath: source.normalizedPath,
      imageUrl: source.url,
      cacheKey: source.cacheKey,
    );
  }

  String _title(String id) => switch (id) {
    'default' => '默认表情',
    'bugcat' => '貓貓蟲',
    'coolmonkey' => '企鹅表情',
    'gexing' => '个性表情',
    'gexing2' => '孤獨搖滾',
    'azukisan' => '小豆泥',
    _ => id,
  };
}

final class _ProjectedStickerCatalog {
  const _ProjectedStickerCatalog({
    required this.groups,
    required this.refreshed,
  });
  final List<StickerGroup> groups;
  final bool refreshed;
}
