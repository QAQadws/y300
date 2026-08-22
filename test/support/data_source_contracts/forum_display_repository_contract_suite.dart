import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/forum/domain/models/forum_display_models.dart';
import 'package:y300/features/forum/domain/repositories/forum_display_repository.dart';

final class ForumDisplayRepositoryContractDriver {
  const ForumDisplayRepositoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.fid,
  });

  final String name;
  final ForumDisplayRepository Function() createRepository;
  final String fid;
}

void runForumDisplayRepositoryContractSuite(
  ForumDisplayRepositoryContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('ForumDisplayRepository contract: $suiteName', () {
    test('returns stable forum/thread identities and provenance', () async {
      final driver = createDriver();
      final result = await driver.createRepository().getForumDisplayByQuery(
        ForumDisplayQuery(fid: driver.fid),
      );

      expect(
        result,
        isA<DataReadSuccess<ForumDisplayData, ForumDisplayReadCapabilities>>(),
      );
      final success =
          result
              as DataReadSuccess<
                ForumDisplayData,
                ForumDisplayReadCapabilities
              >;
      expect(success.data.fid, driver.fid);
      expect(
        success.data.threads
            .map((thread) => thread.tid)
            .every((tid) => tid.trim().isNotEmpty),
        isTrue,
      );
      expect(
        success.data.threads.map((thread) => thread.tid).toSet(),
        hasLength(success.data.threads.length),
      );
      expect(
        success.capabilities.supports(ForumDisplayCapability.forumIdentity),
        isTrue,
      );
      expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
    });
  });
}
