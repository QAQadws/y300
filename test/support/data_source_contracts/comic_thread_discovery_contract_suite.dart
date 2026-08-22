import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_thread_discovery_repository.dart';

final class ComicThreadDiscoveryContractDriver {
  const ComicThreadDiscoveryContractDriver({
    required this.name,
    required this.createRepository,
    required this.sourceTid,
  });

  final String name;
  final ComicThreadDiscoveryRepository Function() createRepository;
  final String sourceTid;
}

void runComicThreadDiscoveryContractSuite(
  ComicThreadDiscoveryContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('ComicThreadDiscovery contract: $suiteName', () {
    test('projects only stable discovery identities and provenance', () async {
      final driver = createDriver();
      final result = await driver.createRepository().load(
        ComicThreadDiscoveryRequest(sourceTid: driver.sourceTid),
      );

      expect(
        result,
        isA<
          DataReadSuccess<
            ComicThreadDiscoveryDocument,
            ComicThreadDiscoveryCapabilities
          >
        >(),
      );
      final success =
          result
              as DataReadSuccess<
                ComicThreadDiscoveryDocument,
                ComicThreadDiscoveryCapabilities
              >;
      expect(success.data.tid, driver.sourceTid);
      expect(success.data.fid, isNotEmpty);
      expect(success.data.posts, isNotEmpty);
      expect(
        success.data.posts.map((post) => post.pid).toSet(),
        hasLength(success.data.posts.length),
      );
      expect(
        success.capabilities.supports(
          ComicThreadDiscoveryCapability.stableThreadIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}
