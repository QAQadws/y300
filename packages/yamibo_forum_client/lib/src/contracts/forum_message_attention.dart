/// Source-neutral evidence for the forum's message arrival indicators.
library;

import '../network/forum_request.dart';
import 'data_read_contract.dart';

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

/// Host ownership and ordering captured before one network request starts.
///
/// This contains no session secrets or response payload. The host chooses an
/// immutable [ownerToken] that distinguishes account and source generations,
/// and allocates sequences across every observing client for that owner.
final class ForumMessageAttentionRequestContext {
  /// Creates request ownership without inferring it from the response.
  const ForumMessageAttentionRequestContext({
    required this.viewerUserId,
    required this.requestSequence,
    required this.ownerToken,
  }) : assert(requestSequence > 0);

  /// Expected authenticated viewer when the request was issued.
  final String viewerUserId;

  /// Host-allocated increasing request sequence, not a server arrival version.
  final int requestSequence;

  /// Opaque immutable account/source ownership token, checked again on delivery.
  final Object ownerToken;
}

/// Optional host port for fresh, verified message-arrival observations.
///
/// Calls are synchronous. Capture and delivery failures are isolated from
/// ordinary forum reads; the host must check current ownership and reject
/// older evidence by coverage before merging an observation.
abstract interface class ForumMessageAttentionObserver {
  /// Captures the current owner and issues a sequence before transport starts.
  ///
  /// Returning null opts this request out, for example when signed out or
  /// identity verification is still pending.
  ForumMessageAttentionRequestContext? captureRequest();

  /// Delivers supported evidence with its original request ownership.
  ///
  /// A delivery does not itself prove that the captured owner is still current.
  void onObservation(
    ForumMessageAttentionObservation observation, {
    required ForumMessageAttentionRequestContext context,
  });
}

/// An explicit, non-consuming read of one verified viewer's arrival hints.
final class ForumMessageAttentionQuery {
  /// Creates a fresh read without inferring the account from cached session data.
  const ForumMessageAttentionQuery({
    required this.expectedUserId,
    this.cancellation,
  });

  /// Authenticated viewer expected by the caller for this read.
  final String expectedUserId;

  /// Cancels an obsolete owner or calibration read.
  final ForumRequestCancellation? cancellation;
}

/// Evidence supported by an explicit arrival-hint source.
enum ForumMessageAttentionCapability {
  /// The response establishes the expected authenticated viewer.
  viewerIdentity,

  /// The message-center arrival flag, independent of conversation unread state.
  privateMessageArrival,

  /// The notification arrival flag across supported notification categories.
  notificationArrival,

  /// The complete count of supported notification categories.
  notificationCount,
}

/// Arrival-hint capabilities declared by one source.
final class ForumMessageAttentionSourceCapabilities {
  /// Creates the source's explicit support values.
  const ForumMessageAttentionSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumMessageAttentionCapability> values;
}

/// Arrival-hint capabilities proved by one explicit read.
final class ForumMessageAttentionReadCapabilities {
  /// Creates the read's explicit support values.
  const ForumMessageAttentionReadCapabilities({required this.values});

  /// Per-capability support values; missing hint fields remain unknown.
  final DataCapabilitySet<ForumMessageAttentionCapability> values;
}

/// Fresh arrival-hint reads that never open a consuming message list.
///
/// Reads are uncached and do not imply UCenter synchronization or that every
/// conversation has been read. Ownership, single-flight, and trigger policy
/// remain with the calling host. An explicit read returns its evidence to that
/// host and does not also publish it through [ForumMessageAttentionObserver].
abstract interface class ForumMessageAttentionRepository {
  /// Capabilities declared by this source.
  ForumMessageAttentionSourceCapabilities get capabilities;

  /// Loads a verified arrival observation or a safe structured failure.
  Future<
    DataReadResult<
      ForumMessageAttentionObservation,
      ForumMessageAttentionReadCapabilities
    >
  >
  load(ForumMessageAttentionQuery query);
}
