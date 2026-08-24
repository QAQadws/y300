import 'data_read_contract.dart';
import 'thread_detail_models.dart';

enum ThreadDetailCapability {
  threadIdentity,
  forumIdentity,
  forumPresentation,
  orderedPosts,
  firstPostIdentity,
  renderableBody,
  losslessBody,
  avatars,
  attachmentMetadata,
  directionalPagination,
  exactPagination,
  alternateViews,
  threadNavigation,
  replyAction,
  editAction,
  ratingSummary,
  ratingAction,
  comments,
  commentAction,
  pollContent,
  pollVoteAction,
  tagLinks,
  favoriteEntry,
}

final class ThreadDetailQuery {
  const ThreadDetailQuery({
    this.authorId,
    this.reverseOrder = false,
    this.opaqueParameters = const <String, String>{},
  });

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

  final String? authorId;
  final bool reverseOrder;
  final Map<String, String> opaqueParameters;

  bool get isEmpty =>
      (authorId == null || authorId!.isEmpty) &&
      !reverseOrder &&
      opaqueParameters.isEmpty;

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

final class ThreadDetailSourceCapabilities {
  const ThreadDetailSourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ThreadDetailCapability> values;
  final PaginationPrecision paginationPrecision;

  static final full = ThreadDetailSourceCapabilities(
    values: DataCapabilitySet<ThreadDetailCapability>.supported(
      ThreadDetailCapability.values,
    ),
    paginationPrecision: PaginationPrecision.exact,
  );

  bool supports(ThreadDetailCapability capability) {
    return values.supports(capability);
  }

  ThreadDetailReadCapabilities toReadCapabilities() {
    return ThreadDetailReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

final class ThreadDetailReadCapabilities {
  const ThreadDetailReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  final DataCapabilitySet<ThreadDetailCapability> values;
  final PaginationPrecision paginationPrecision;

  bool supports(ThreadDetailCapability capability) {
    return values.supports(capability);
  }

  ThreadDetailReadCapabilities intersect(ThreadDetailReadCapabilities other) {
    return ThreadDetailReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: paginationPrecision.intersect(
        other.paginationPrecision,
      ),
    );
  }
}

abstract interface class ThreadRepository {
  ThreadDetailSourceCapabilities get capabilities;

  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  });
}
