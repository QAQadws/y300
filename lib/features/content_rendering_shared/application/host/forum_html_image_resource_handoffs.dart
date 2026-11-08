import 'package:y300/features/cache/domain/models/image_cache_models.dart';

/// Host-owned one-shot handoffs, not a cache of displayed images. Values expire
/// independently and hold no Context, provider or bitmap.
final class ForumHtmlImageResourceHandoffs {
  final _entries = <Object, ImageCacheResourceHandoff>{};

  void offer(Object identity, ImageCacheResourceHandoff handoff) {
    _entries.remove(identity);
    _entries[identity] = handoff;
    while (_entries.length > 8) {
      _entries.remove(_entries.keys.first);
    }
  }

  ImageCacheResourceHandoff? take(Object identity) => _entries.remove(identity);
}
