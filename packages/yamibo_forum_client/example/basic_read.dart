import 'dart:io';

import 'package:yamibo_forum_client/yamibo_forum_client.dart';

Future<void> main() async {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://bbs.yamibo.com'),
    apiOrigin: Uri.parse('https://bbs.yamibo.com/api/mobile/index.php'),
    userAgent: 'YamiboForumClientExample/0.1',
  );
  final cookies = MemoryForumCookieStore();
  final network = DioForumClientNetwork(config: config, cookies: cookies);
  final client = YamiboForumClientBuilder(
    config: config,
    network: network,
    sessionStore: MemoryForumSessionStore(),
    documentStore: MemoryForumDocumentStore(),
    snapshotStore: MemoryForumSnapshotStore(),
  ).buildStandardReads();

  final result = await client.loadForumDirectory(const ForumDirectoryQuery());
  switch (result) {
    case DataReadSuccess<ForumDirectoryData, ForumDirectoryReadCapabilities>(
      :final data,
      :final capabilities,
      :final metadata,
    ):
      stdout.writeln(
        'Loaded ${data.sections.length} sections from ${metadata.origin.name}.',
      );
      stdout.writeln(
        'Stable forum identities: '
        '${capabilities.supports(ForumDirectoryCapability.stableForumIdentity)}',
      );
    case DataReadFailure<ForumDirectoryData, ForumDirectoryReadCapabilities>(
      :final kind,
      :final code,
    ):
      stderr.writeln('Forum directory failed: ${kind.name} (${code ?? '-'})');
  }
}
