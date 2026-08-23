import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/domain/repositories/forum_directory_repository.dart';

typedef ForumHomeReadResult =
    DataReadResult<ForumHomePayload, ForumDirectoryReadCapabilities>;

final _capabilities = ForumDirectoryReadCapabilities(
  values: DataCapabilitySet<ForumDirectoryCapability>.supported(
    ForumDirectoryCapability.values,
  ),
);

ForumHomeReadResult forumHomeReadSuccess(
  ForumHomePayload payload, {
  ForumDirectoryReadCapabilities? capabilities,
  DataReadMetadata metadata = const DataReadMetadata.network(),
}) {
  return DataReadSuccess(
    data: payload,
    capabilities: capabilities ?? _capabilities,
    metadata: metadata,
  );
}

ForumDirectoryReadCapabilities get forumHomeTestCapabilities => _capabilities;
