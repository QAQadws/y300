import 'dart:io';

import 'package:yamibo_forum_client/yamibo_forum_client.dart';

Future<void> main() async {
  // This runtime intentionally discards cookies and caches on process exit.
  // Production apps should use standardDio() with persistent Host ports.
  final client = YamiboForumClientBuilder.ephemeralDio().buildStandardClient();

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
