import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

enum _Capability { identity, optional }

void main() {
  test(
    'capabilities intersect fail closed and metadata keeps weakest freshness',
    () {
      final left = DataCapabilitySet<_Capability>.from(
        supported: const <_Capability>[
          _Capability.identity,
          _Capability.optional,
        ],
      );
      final right = DataCapabilitySet<_Capability>.from(
        supported: const <_Capability>[_Capability.identity],
        unsupported: const <_Capability>[_Capability.optional],
      );
      expect(left.intersect(right).supports(_Capability.identity), isTrue);
      expect(left.intersect(right).supports(_Capability.optional), isFalse);
      final merged = const DataReadMetadata.network().merge(
        DataReadMetadata(
          origin: DataReadOrigin.freshSnapshot,
          freshness: DataReadFreshness.staleOrUnknown,
        ),
      );
      expect(merged.origin, DataReadOrigin.mixed);
      expect(merged.freshness, DataReadFreshness.staleOrUnknown);
    },
  );
}
