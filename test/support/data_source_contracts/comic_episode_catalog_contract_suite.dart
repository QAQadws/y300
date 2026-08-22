import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/domain/models/comic_episode_image_catalog.dart';
import 'package:y300/features/comic/domain/repositories/comic_episode_catalog_repository.dart';

final class ComicEpisodeCatalogContractDriver {
  const ComicEpisodeCatalogContractDriver({
    required this.name,
    required this.createRepository,
    required this.sourceTid,
  });

  final String name;
  final ComicEpisodeCatalogRepository Function() createRepository;
  final String sourceTid;
}

void runComicEpisodeCatalogContractSuite(
  ComicEpisodeCatalogContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('ComicEpisodeCatalog contract: $suiteName', () {
    test(
      'returns a stable source identity and ordered image references',
      () async {
        final driver = createDriver();
        final result = await driver.createRepository().loadCatalog(
          ComicEpisodeCatalogRequest(sourceTid: driver.sourceTid),
        );

        expect(
          result,
          isA<
            DataReadSuccess<
              ComicEpisodeImageCatalog,
              ComicEpisodeCatalogCapabilities
            >
          >(),
        );
        final success =
            result
                as DataReadSuccess<
                  ComicEpisodeImageCatalog,
                  ComicEpisodeCatalogCapabilities
                >;
        expect(success.data.sourceTid, driver.sourceTid);
        expect(success.data.images, isNotEmpty);
        expect(
          success.data.images.every((image) => image.url.trim().isNotEmpty),
          isTrue,
        );
        expect(
          success.capabilities.supports(
            ComicEpisodeCatalogCapability.stableSourceIdentity,
          ),
          isTrue,
        );
        expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
      },
    );
  });
}
