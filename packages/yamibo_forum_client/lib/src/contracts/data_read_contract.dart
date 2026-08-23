enum DataReadOrigin {
  network,
  freshSnapshot,
  cachedDocumentFallback,
  mixed,
  unknown,
}

enum DataReadFreshness { current, freshCache, staleOrUnknown }

enum DataCapabilitySupport { supported, unsupported, unknown }

enum PaginationPrecision { exact, directional, totalBased, heuristic, unknown }

extension PaginationPrecisionMerge on PaginationPrecision {
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

enum DataReadFailureKind {
  network,
  timeout,
  unauthorized,
  server,
  parse,
  business,
  unsupported,
  cancelled,
  unknown,
}

final class DataReadMetadata {
  const DataReadMetadata({required this.origin, required this.freshness});
  const DataReadMetadata.network()
    : origin = DataReadOrigin.network,
      freshness = DataReadFreshness.current;

  final DataReadOrigin origin;
  final DataReadFreshness freshness;

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

final class DataCapabilitySet<T extends Enum> {
  DataCapabilitySet(Map<T, DataCapabilitySupport> values)
    : _values = Map<T, DataCapabilitySupport>.unmodifiable(values);

  factory DataCapabilitySet.supported(Iterable<T> capabilities) =>
      DataCapabilitySet<T>({
        for (final capability in capabilities)
          capability: DataCapabilitySupport.supported,
      });

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
  DataCapabilitySupport supportOf(T capability) =>
      _values[capability] ?? DataCapabilitySupport.unknown;
  bool supports(T capability) =>
      supportOf(capability) == DataCapabilitySupport.supported;
  Map<T, DataCapabilitySupport> get values => _values;

  DataCapabilitySet<T> intersect(DataCapabilitySet<T> other) {
    final keys = <T>{..._values.keys, ...other._values.keys};
    return DataCapabilitySet<T>({
      for (final key in keys)
        key: _intersectSupport(supportOf(key), other.supportOf(key)),
    });
  }

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

sealed class DataReadResult<T, C> {
  const DataReadResult();
  bool get isSuccess => this is DataReadSuccess<T, C>;
  bool get isFailure => this is DataReadFailure<T, C>;
  T? get dataOrNull => switch (this) {
    DataReadSuccess<T, C>(:final data) => data,
    DataReadFailure<T, C>() => null,
  };
  DataReadFailure<T, C>? get failureOrNull => switch (this) {
    DataReadSuccess<T, C>() => null,
    final DataReadFailure<T, C> failure => failure,
  };

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

final class DataReadSuccess<T, C> extends DataReadResult<T, C> {
  const DataReadSuccess({
    required this.data,
    required this.capabilities,
    required this.metadata,
  });
  final T data;
  final C capabilities;
  final DataReadMetadata metadata;
}

final class DataReadFailure<T, C> extends DataReadResult<T, C> {
  const DataReadFailure({
    required this.kind,
    required this.diagnosticMessage,
    this.code,
    this.statusCode,
  });
  final DataReadFailureKind kind;
  final String? code;
  final int? statusCode;
  final String diagnosticMessage;

  DataReadFailure<R, D> retype<R, D>() => DataReadFailure<R, D>(
    kind: kind,
    code: code,
    statusCode: statusCode,
    diagnosticMessage: diagnosticMessage,
  );
}
