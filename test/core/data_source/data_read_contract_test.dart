import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';

enum _Capability { identity, richContent, action }

void main() {
  group('DataCapabilitySet', () {
    test('unknown capabilities fail closed', () {
      final capabilities = DataCapabilitySet<_Capability>.supported(
        const <_Capability>[_Capability.identity],
      );

      expect(capabilities.supports(_Capability.identity), isTrue);
      expect(capabilities.supports(_Capability.richContent), isFalse);
      expect(
        capabilities.supportOf(_Capability.richContent),
        DataCapabilitySupport.unknown,
      );
    });

    test('intersection keeps only mutually supported capabilities', () {
      final left = DataCapabilitySet<_Capability>.from(
        supported: const <_Capability>[
          _Capability.identity,
          _Capability.richContent,
        ],
        unsupported: const <_Capability>[_Capability.action],
      );
      final right = DataCapabilitySet<_Capability>.from(
        supported: const <_Capability>[
          _Capability.identity,
          _Capability.action,
        ],
      );

      final intersection = left.intersect(right);

      expect(intersection.supports(_Capability.identity), isTrue);
      expect(
        intersection.supportOf(_Capability.richContent),
        DataCapabilitySupport.unknown,
      );
      expect(
        intersection.supportOf(_Capability.action),
        DataCapabilitySupport.unsupported,
      );
    });
  });

  test('metadata merge uses mixed origin and weakest freshness', () {
    const network = DataReadMetadata.network();
    const fallback = DataReadMetadata(
      origin: DataReadOrigin.cachedDocumentFallback,
      freshness: DataReadFreshness.staleOrUnknown,
    );

    final merged = network.merge(fallback);

    expect(merged.origin, DataReadOrigin.mixed);
    expect(merged.freshness, DataReadFreshness.staleOrUnknown);
  });

  test('failure contains diagnostics but no transport raw payload', () {
    const result = DataReadFailure<String, DataCapabilitySet<_Capability>>(
      kind: DataReadFailureKind.parse,
      code: 'invalid_shape',
      statusCode: 200,
      diagnosticMessage: 'Expected a stable identity.',
    );

    expect(result.isFailure, isTrue);
    expect(result.dataOrNull, isNull);
    expect(result.diagnosticMessage, 'Expected a stable identity.');
  });

  test('pagination precision intersection keeps the weaker guarantee', () {
    expect(
      PaginationPrecision.exact.intersect(PaginationPrecision.directional),
      PaginationPrecision.directional,
    );
    expect(
      PaginationPrecision.totalBased.intersect(PaginationPrecision.heuristic),
      PaginationPrecision.heuristic,
    );
    expect(
      PaginationPrecision.exact.intersect(PaginationPrecision.unknown),
      PaginationPrecision.unknown,
    );
  });

  test('failure retyping preserves source-neutral diagnostics', () {
    const source = DataReadFailure<int, DataCapabilitySet<_Capability>>(
      kind: DataReadFailureKind.timeout,
      code: 'read_timeout',
      statusCode: 504,
      diagnosticMessage: 'The source did not respond in time.',
    );

    final redirected = source.retype<String, _Capability>();

    expect(redirected.kind, DataReadFailureKind.timeout);
    expect(redirected.code, 'read_timeout');
    expect(redirected.statusCode, 504);
    expect(redirected.diagnosticMessage, 'The source did not respond in time.');
  });

  test('stable cancellation code maps without changing ApiError type', () {
    const legacyError = ApiError(
      type: ApiErrorType.network,
      code: 'request_cancelled',
      message: 'Request cancelled.',
    );

    final failure = dataReadFailureFromApiError<String, _Capability>(
      legacyError,
    );

    expect(legacyError.type, ApiErrorType.network);
    expect(failure.kind, DataReadFailureKind.cancelled);
    expect(failure.code, 'request_cancelled');
  });
}
