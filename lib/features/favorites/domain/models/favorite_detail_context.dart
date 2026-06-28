import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

class FavoriteDetailContext {
  const FavoriteDetailContext({
    required this.record,
    required this.detail,
    required this.kind,
    this.tagName,
  });

  final FavoriteThreadCacheRecord record;
  final ThreadDetailData detail;
  final ThreadContentKind kind;
  final String? tagName;
}
