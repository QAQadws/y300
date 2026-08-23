import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';
import 'package:y300/features/forum/domain/repositories/forum_directory_repository.dart';

enum ForumDirectoryContractScenario {
  populated,
  empty,
  missingTodayPosts,
  missingRoot,
  emptySectionIdentity,
  duplicateSectionIdentity,
  duplicateForumIdentity,
  malformed,
  serverFailure,
  timeout,
  cancelled,
}

final class ForumDirectoryRepositoryContractDriver {
  const ForumDirectoryRepositoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.expectsNestedForums,
  });

  final String name;
  final ForumDirectoryRepository Function(
    ForumDirectoryContractScenario scenario,
  )
  createRepository;
  final bool expectsNestedForums;
}

void runForumDirectoryRepositoryContractSuite(
  ForumDirectoryRepositoryContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('ForumDirectoryRepository contract: $suiteName', () {
    test('preserves ordered stable identities and field semantics', () async {
      final driver = createDriver();
      final repository = driver.createRepository(
        ForumDirectoryContractScenario.populated,
      );

      final result = await repository.load(const ForumDirectoryQuery());

      expect(
        result,
        isA<
          DataReadSuccess<ForumDirectoryData, ForumDirectoryReadCapabilities>
        >(),
      );
      final success =
          result
              as DataReadSuccess<
                ForumDirectoryData,
                ForumDirectoryReadCapabilities
              >;
      expect(success.data.sections, isNotEmpty);
      expect(
        success.data.sections.map((section) => section.identity).toSet(),
        hasLength(success.data.sections.length),
      );
      final forumIds = _flattenForums(
        success.data,
      ).map((forum) => forum.fid).toList(growable: false);
      expect(forumIds.every((fid) => fid.trim().isNotEmpty), isTrue);
      expect(forumIds.toSet(), hasLength(forumIds.length));
      expect(
        success.capabilities.supports(
          ForumDirectoryCapability.stableSectionIdentity,
        ),
        isTrue,
      );
      expect(
        success.capabilities.supports(ForumDirectoryCapability.todayPostCount),
        isTrue,
      );
      expect(
        success.capabilities.supports(ForumDirectoryCapability.nestedForums),
        driver.expectsNestedForums,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
    });

    test('returns an explicit empty directory as success', () async {
      final driver = createDriver();
      final result = await driver
          .createRepository(ForumDirectoryContractScenario.empty)
          .load(const ForumDirectoryQuery());

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.sections, isEmpty);
    });

    test('keeps an unavailable today count as null', () async {
      final driver = createDriver();
      final result = await driver
          .createRepository(ForumDirectoryContractScenario.missingTodayPosts)
          .load(const ForumDirectoryQuery());

      expect(result.isSuccess, isTrue);
      expect(
        result.dataOrNull!.sections.single.forums.single.todayPosts,
        isNull,
      );
    });

    for (final scenario in const <ForumDirectoryContractScenario>[
      ForumDirectoryContractScenario.missingRoot,
      ForumDirectoryContractScenario.emptySectionIdentity,
      ForumDirectoryContractScenario.duplicateSectionIdentity,
      ForumDirectoryContractScenario.duplicateForumIdentity,
    ]) {
      test('fails closed for ${scenario.name}', () async {
        final driver = createDriver();
        final result = await driver
            .createRepository(scenario)
            .load(const ForumDirectoryQuery());

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      });
    }

    for (final scenario
        in const <(ForumDirectoryContractScenario, DataReadFailureKind)>[
          (ForumDirectoryContractScenario.malformed, DataReadFailureKind.parse),
          (
            ForumDirectoryContractScenario.serverFailure,
            DataReadFailureKind.server,
          ),
          (ForumDirectoryContractScenario.timeout, DataReadFailureKind.timeout),
          (
            ForumDirectoryContractScenario.cancelled,
            DataReadFailureKind.cancelled,
          ),
        ]) {
      test('classifies ${scenario.$1.name} without source payloads', () async {
        final driver = createDriver();
        final result = await driver
            .createRepository(scenario.$1)
            .load(const ForumDirectoryQuery());

        expect(result.failureOrNull?.kind, scenario.$2);
        expect(result.failureOrNull?.diagnosticMessage, isNotEmpty);
        expect(
          result.failureOrNull?.diagnosticMessage,
          isNot(contains('<html')),
        );
      });
    }
  });
}

List<ForumDirectoryForum> _flattenForums(ForumDirectoryData data) {
  final output = <ForumDirectoryForum>[];
  void add(ForumDirectoryForum forum) {
    output.add(forum);
    forum.children.forEach(add);
  }

  for (final section in data.sections) {
    section.forums.forEach(add);
  }
  return output;
}
