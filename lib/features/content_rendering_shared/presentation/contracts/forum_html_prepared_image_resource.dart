/// Host-owned resource binding for an image described by a prepared entry.
///
/// Implementations must be immutable and retain only isolate-safe pure values:
/// no Ref, Widget, BuildContext, services or callback closures. The prepared
/// entry itself keeps the image's DOM source and visual description.
abstract interface class ForumHtmlPreparedImageResource {
  String get cacheKey;
}
