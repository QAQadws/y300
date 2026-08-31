/// Common result, capability, provenance, pagination, and failure semantics.
library;

/// Describes where a successful read was assembled.
enum DataReadOrigin {
  /// Network.
  network,

  /// Fresh snapshot.
  freshSnapshot,

  /// Cached document fallback.
  cachedDocumentFallback,

  /// Mixed.
  mixed,

  /// Unknown.
  unknown,
}

/// Describes the weakest known freshness of a successful result.
/// Values describing data read freshness.
enum DataReadFreshness {
  /// Current.
  current,

  /// Fresh cache.
  freshCache,

  /// Stale or unknown.
  staleOrUnknown,
}

/// Whether a source can prove support for a business capability.
/// Values describing data capability support.
enum DataCapabilitySupport {
  /// Supported.
  supported,

  /// Unsupported.
  unsupported,

  /// Unknown.
  unknown,
}

/// How precisely a source can describe available pages.
/// Values describing pagination precision.
enum PaginationPrecision {
  /// Exact.
  exact,

  /// Directional.
  directional,

  /// Total based.
  totalBased,

  /// Heuristic.
  heuristic,

  /// Unknown.
  unknown,
}

/// Conservative pagination precision composition.
extension PaginationPrecisionMerge on PaginationPrecision {
  /// Returns the conservative intersection with another value.
  PaginationPrecision intersect(PaginationPrecision other) {
    if (this == other) return this;
    return _rank(this) >= _rank(other) ? this : other;
  }

  static int _rank(PaginationPrecision value) => switch (value) {
    PaginationPrecision.exact => 0,
    PaginationPrecision.directional => 1,
    PaginationPrecision.totalBased => 2,
    PaginationPrecision.heuristic => 3,
    PaginationPrecision.unknown => 4,
  };
}

/// Stable, transport-neutral read failure categories.
enum DataReadFailureKind {
  /// Network.
  network,

  /// Timeout.
  timeout,

  /// Unauthorized.
  unauthorized,

  /// Server.
  server,

  /// Parse.
  parse,

  /// Business.
  business,

  /// Unsupported.
  unsupported,

  /// Cancelled.
  cancelled,

  /// Unknown.
  unknown,
}

/// Provenance attached to every successful read.
final class DataReadMetadata {
  /// Creates explicit provenance metadata.
  const DataReadMetadata({required this.origin, required this.freshness});

  /// Creates metadata for a current network response.
  const DataReadMetadata.network()
    : origin = DataReadOrigin.network,
      freshness = DataReadFreshness.current;

  /// Source or combination of sources used by the result.
  final DataReadOrigin origin;

  /// Weakest known freshness of the result.
  final DataReadFreshness freshness;

  /// Merges paginated or composite reads without overstating provenance.
  DataReadMetadata merge(DataReadMetadata other) => DataReadMetadata(
    origin: origin == other.origin ? origin : DataReadOrigin.mixed,
    freshness: _weakerFreshness(freshness, other.freshness),
  );

  static DataReadFreshness _weakerFreshness(
    DataReadFreshness left,
    DataReadFreshness right,
  ) => _rank(left) >= _rank(right) ? left : right;

  static int _rank(DataReadFreshness value) => switch (value) {
    DataReadFreshness.current => 0,
    DataReadFreshness.freshCache => 1,
    DataReadFreshness.staleOrUnknown => 2,
  };
}

/// Immutable support map for a source-neutral capability enum.
final class DataCapabilitySet<T extends Enum> {
  /// Creates a set from explicit support values.
  DataCapabilitySet(Map<T, DataCapabilitySupport> values)
    : _values = Map<T, DataCapabilitySupport>.unmodifiable(values);

  /// Creates a set in which every supplied capability is supported.
  factory DataCapabilitySet.supported(Iterable<T> capabilities) =>
      DataCapabilitySet<T>({
        for (final capability in capabilities)
          capability: DataCapabilitySupport.supported,
      });

  /// Creates a set from separate supported and unsupported collections.
  factory DataCapabilitySet.from({
    Iterable<T> supported = const <Never>[],
    Iterable<T> unsupported = const <Never>[],
  }) => DataCapabilitySet<T>({
    for (final capability in supported)
      capability: DataCapabilitySupport.supported,
    for (final capability in unsupported)
      capability: DataCapabilitySupport.unsupported,
  });

  final Map<T, DataCapabilitySupport> _values;

  /// Returns the explicit support state, defaulting to unknown.
  DataCapabilitySupport supportOf(T capability) =>
      _values[capability] ?? DataCapabilitySupport.unknown;

  /// Whether [capability] is explicitly supported.
  bool supports(T capability) =>
      supportOf(capability) == DataCapabilitySupport.supported;

  /// Unmodifiable explicit support values.
  Map<T, DataCapabilitySupport> get values => _values;

  /// Returns the conservative intersection with another value.
  DataCapabilitySet<T> intersect(DataCapabilitySet<T> other) {
    final keys = <T>{..._values.keys, ...other._values.keys};
    return DataCapabilitySet<T>({
      for (final key in keys)
        key: _intersectSupport(supportOf(key), other.supportOf(key)),
    });
  }

  /// Returns a copy with one capability support value replaced.
  DataCapabilitySet<T> withSupport(
    T capability,
    DataCapabilitySupport support,
  ) => DataCapabilitySet<T>({..._values, capability: support});

  static DataCapabilitySupport _intersectSupport(
    DataCapabilitySupport left,
    DataCapabilitySupport right,
  ) {
    if (left == DataCapabilitySupport.unsupported ||
        right == DataCapabilitySupport.unsupported) {
      return DataCapabilitySupport.unsupported;
    }
    if (left == DataCapabilitySupport.unknown ||
        right == DataCapabilitySupport.unknown) {
      return DataCapabilitySupport.unknown;
    }
    return DataCapabilitySupport.supported;
  }
}

/// Transport-neutral result envelope for package read contracts.
sealed class DataReadResult<T, C> {
  const DataReadResult();

  /// Whether this value is a [DataReadSuccess].
  bool get isSuccess => this is DataReadSuccess<T, C>;

  /// Whether this value is a [DataReadFailure].
  bool get isFailure => this is DataReadFailure<T, C>;

  /// Successful data or `null` for a failure.
  T? get dataOrNull => switch (this) {
    DataReadSuccess<T, C>(:final data) => data,
    DataReadFailure<T, C>() => null,
  };

  /// Failure details or `null` for a success.
  DataReadFailure<T, C>? get failureOrNull => switch (this) {
    DataReadSuccess<T, C>() => null,
    final DataReadFailure<T, C> failure => failure,
  };

  /// Exhaustively maps success and failure without exposing source DTOs.
  R when<R>({
    required R Function(T data, C capabilities, DataReadMetadata metadata)
    success,
    required R Function(DataReadFailure<T, C> failure) failure,
  }) {
    return switch (this) {
      DataReadSuccess<T, C>(
        :final data,
        :final capabilities,
        :final metadata,
      ) =>
        success(data, capabilities, metadata),
      final DataReadFailure<T, C> value => failure(value),
    };
  }
}

/// Successful read with data, effective capabilities, and provenance.
final class DataReadSuccess<T, C> extends DataReadResult<T, C> {
  /// Creates a successful read result.
  const DataReadSuccess({
    required this.data,
    required this.capabilities,
    required this.metadata,
  });

  /// Source-neutral business data.
  final T data;

  /// Effective capabilities proved for this result.
  final C capabilities;

  /// Origin and freshness of this result.
  final DataReadMetadata metadata;
}

/// Failed read containing only safe, stable diagnostic information.
final class DataReadFailure<T, C> extends DataReadResult<T, C> {
  /// Creates a failed read result.
  const DataReadFailure({
    required this.kind,
    required this.diagnosticMessage,
    this.code,
    this.statusCode,
  });

  /// Stable failure category.
  final DataReadFailureKind kind;

  /// Optional protocol-safe diagnostic code.
  final String? code;

  /// Optional HTTP status associated with the failure.
  final int? statusCode;

  /// Safe diagnostic text that must not contain response payloads or secrets.
  final String diagnosticMessage;

  /// Reuses this failure across another data and capability type.
  DataReadFailure<R, D> retype<R, D>() => DataReadFailure<R, D>(
    kind: kind,
    code: code,
    statusCode: statusCode,
    diagnosticMessage: diagnosticMessage,
  );
}
