import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';

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
}
