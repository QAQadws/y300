/// Thread detail query, capability, and repository contracts.
library;

import 'data_read_contract.dart';
import 'thread_detail_models.dart';

/// Capabilities exposed by thread detail.
enum ThreadDetailCapability {
  /// Thread identity.
  threadIdentity,

  /// Forum identity.
  forumIdentity,

  /// Forum presentation.
  forumPresentation,

  /// Ordered posts.
  orderedPosts,

  /// First post identity.
  firstPostIdentity,

  /// Renderable body.
  renderableBody,

  /// Lossless body.
  losslessBody,

  /// Avatars.
  avatars,

  /// Attachment metadata.
  attachmentMetadata,

  /// Directional pagination.
  directionalPagination,

  /// Exact pagination.
  exactPagination,

  /// Alternate views.
  alternateViews,

  /// Thread navigation.
  threadNavigation,

  /// Reply action.
  replyAction,

  /// Edit action.
  editAction,

  /// Rating summary.
  ratingSummary,

  /// Rating action.
  ratingAction,

  /// Comments.
  comments,

  /// Comment action.
  commentAction,

  /// Poll content.
  pollContent,

  /// Tag links.
  tagLinks,

  /// Favorite entry.
  favoriteEntry,
}

/// Query parameters for thread detail.
final class ThreadDetailQuery {
  /// Creates a [ThreadDetailQuery].
  const ThreadDetailQuery({
    this.authorId,
    this.reverseOrder = false,
    this.opaqueParameters = const <String, String>{},
  });

  /// Creates a [ThreadDetailQuery].
  factory ThreadDetailQuery.fromLegacyParameters(
    Map<String, String> parameters,
  ) {
    final authorId = parameters['authorid']?.trim();
    return ThreadDetailQuery(
      authorId: authorId == null || authorId.isEmpty ? null : authorId,
      reverseOrder: parameters['ordertype']?.trim() == '1',
      opaqueParameters: Map<String, String>.unmodifiable({
        for (final entry in parameters.entries)
          if (entry.key != 'authorid' &&
              (entry.key != 'ordertype' || entry.value.trim() != '1') &&
              entry.value.trim().isNotEmpty)
            entry.key: entry.value.trim(),
      }),
    );
  }

  /// Stable author identifier.
  final String? authorId;

  /// Reverse order.
  final bool reverseOrder;

  /// Opaque parameters.
  final Map<String, String> opaqueParameters;

  /// Whether the query has no filtering, ordering, or opaque parameters.
  bool get isEmpty =>
      (authorId == null || authorId!.isEmpty) &&
      !reverseOrder &&
      opaqueParameters.isEmpty;

  /// Converts this value to request parameters.
  Map<String, String> toRequestParameters() {
    return Map<String, String>.unmodifiable(<String, String>{
      ...opaqueParameters,
      if (authorId != null && authorId!.isNotEmpty) 'authorid': authorId!,
      if (reverseOrder) 'ordertype': '1',
    });
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ThreadDetailQuery &&
        other.authorId == authorId &&
        other.reverseOrder == reverseOrder &&
        _mapsEqual(other.opaqueParameters, opaqueParameters);
  }

  @override
  int get hashCode => Object.hash(
    authorId,
    reverseOrder,
    Object.hashAllUnordered(
      opaqueParameters.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );

  static bool _mapsEqual(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) {
      return false;
    }
    return left.entries.every((entry) => right[entry.key] == entry.value);
  }
}

/// Capabilities declared by the thread detail source.
final class ThreadDetailSourceCapabilities {
  /// Creates a [ThreadDetailSourceCapabilities].
  const ThreadDetailSourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ThreadDetailCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Complete capability set used by the verified full source.
  static final full = ThreadDetailSourceCapabilities(
    values: DataCapabilitySet<ThreadDetailCapability>.supported(
      ThreadDetailCapability.values,
    ),
    paginationPrecision: PaginationPrecision.exact,
  );

  /// Whether the requested capability is supported.
  bool supports(ThreadDetailCapability capability) {
    return values.supports(capability);
  }

  /// Converts this value to read capabilities.
  ThreadDetailReadCapabilities toReadCapabilities() {
    return ThreadDetailReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

/// Capabilities effective for one thread detail read.
final class ThreadDetailReadCapabilities {
  /// Creates a [ThreadDetailReadCapabilities].
  const ThreadDetailReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ThreadDetailCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(ThreadDetailCapability capability) {
    return values.supports(capability);
  }

  /// Returns the conservative intersection with another value.
  ThreadDetailReadCapabilities intersect(ThreadDetailReadCapabilities other) {
    return ThreadDetailReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: paginationPrecision.intersect(
        other.paginationPrecision,
      ),
    );
  }
}

/// Loads thread data through a source-neutral contract.
abstract interface class ThreadRepository {
  /// Capabilities declared by this source.
  ThreadDetailSourceCapabilities get capabilities;

  /// Loads one thread-detail page with source-neutral query semantics.
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  });
}
