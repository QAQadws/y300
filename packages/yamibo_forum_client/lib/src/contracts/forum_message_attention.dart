/// Source-neutral evidence for the forum's message arrival indicators.
library;

/// What a supported response establishes for one arrival indicator.
enum ForumMessageAttentionState {
  /// No reliable evidence; this must not clear a previously observed indicator.
  unknown,

  /// The supported indicator was explicitly inactive in this response.
  absent,

  /// The supported indicator was explicitly active in this response.
  present,
}

/// Representation from which arrival evidence was extracted.
enum ForumMessageAttentionSource {
  /// A mobile page's public navigation shell.
  mobileHtml,

  /// A desktop page's public navigation shell.
  desktopHtml,

  /// A decoded API response's public variables.
  api,
}

/// Immutable arrival evidence for a verified response viewer.
///
/// Arrival indicators do not establish whether every conversation or
/// notification has been read. Parsing also does not establish network
/// freshness, request ordering, or the current session owner; the publishing
/// host must check those separately before using an observation.
final class ForumMessageAttentionObservation {
  /// Creates evidence without replacing missing fields with inactive values.
  ///
  /// [notificationCount], when supplied, must agree with [notifications].
  /// A combined-only hint does not imply either individual category.
  const ForumMessageAttentionObservation({
    required this.viewerUserId,
    required this.source,
    this.privateMessages = ForumMessageAttentionState.unknown,
    this.notifications = ForumMessageAttentionState.unknown,
    this.combinedHint = ForumMessageAttentionState.unknown,
    this.notificationCount,
  }) : assert(notificationCount == null || notificationCount >= 0),
       assert(
         notificationCount == null ||
             (notificationCount == 0 &&
                 notifications == ForumMessageAttentionState.absent) ||
             (notificationCount > 0 &&
                 notifications == ForumMessageAttentionState.present),
       );

  /// Viewer identity established in the response, never a content author's ID.
  final String viewerUserId;

  /// Representation of this observation; it does not imply freshness.
  final ForumMessageAttentionSource source;

  /// Message-center arrival indicator, independent of conversation unread flags.
  ///
  /// Sources such as Discuz may include announcement flags in this category.
  final ForumMessageAttentionState privateMessages;

  /// Notification arrival indicator, including supported notification categories.
  final ForumMessageAttentionState notifications;

  /// Direct aggregate evidence when a source exposes only a shared indicator.
  final ForumMessageAttentionState combinedHint;

  /// Complete source-reported notification count, or `null` if not established.
  ///
  /// This is never a private-message count or a count inferred from list rows.
  final int? notificationCount;

  /// Aggregate arrival state, retaining partial and conflicting uncertainty.
  ///
  /// Conflicting aggregate and category evidence remains unknown. Otherwise a
  /// known positive category is enough; an inactive aggregate requires either
  /// direct inactive evidence or both inactive categories.
  ForumMessageAttentionState get combined {
    final categoryPresent =
        privateMessages == ForumMessageAttentionState.present ||
        notifications == ForumMessageAttentionState.present;
    final categoriesAbsent =
        privateMessages == ForumMessageAttentionState.absent &&
        notifications == ForumMessageAttentionState.absent;
    if ((combinedHint == ForumMessageAttentionState.absent &&
            categoryPresent) ||
        (combinedHint == ForumMessageAttentionState.present &&
            categoriesAbsent)) {
      return ForumMessageAttentionState.unknown;
    }
    if (combinedHint == ForumMessageAttentionState.present || categoryPresent) {
      return ForumMessageAttentionState.present;
    }
    if (combinedHint == ForumMessageAttentionState.absent || categoriesAbsent) {
      return ForumMessageAttentionState.absent;
    }
    return ForumMessageAttentionState.unknown;
  }
}
