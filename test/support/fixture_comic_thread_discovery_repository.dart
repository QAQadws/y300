import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Test-only source-neutral adapter used by comic service tests. Production
/// adapter behavior is covered inside the package contract suites.
final class FixtureComicThreadDiscoveryRepository
    implements ComicThreadDiscoveryRepository {
  const FixtureComicThreadDiscoveryRepository({
    required this.threadRepository,
    this.projector = const ComicThreadDiscoveryProjector(),
  });

  final ThreadRepository threadRepository;
  final ComicThreadDiscoveryProjector projector;

  @override
  ComicThreadDiscoverySourceCapabilities get capabilities =>
      ComicThreadDiscoverySourceCapabilities(
        DataCapabilitySet<ComicThreadDiscoveryCapability>.supported(
          ComicThreadDiscoveryCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<
      ComicThreadDiscoveryDocument,
      ComicThreadDiscoveryCapabilities
    >
  >
  load(ComicThreadDiscoveryRequest request) async {
    final result = await threadRepository.getThreadDetail(
      tid: request.sourceTid,
      page: 1,
    );
    return result.when(
      success: (data, _, metadata) => DataReadSuccess(
        data: projector.project(data),
        capabilities: ComicThreadDiscoveryCapabilities(capabilities.values),
        metadata: metadata,
      ),
      failure: (failure) => failure.retype(),
    );
  }
}
