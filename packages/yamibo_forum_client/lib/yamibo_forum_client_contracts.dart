/// Source-neutral contracts, models, capabilities, and read results.
///
/// Application domain and presentation code should depend on this library
/// rather than concrete Discuz adapters. Unsupported or unknown capabilities
/// must be handled fail closed.
library;

export 'src/contracts/cache_load_policy.dart';
export 'src/contracts/comic_contracts.dart';
export 'src/contracts/data_read_contract.dart';
export 'src/contracts/data_command_contract.dart';
export 'src/contracts/favorite_directories.dart';
export 'src/contracts/favorite_commands.dart';
export 'src/contracts/forum_directory.dart';
export 'src/contracts/forum_home.dart';
export 'src/contracts/forum_authentication.dart';
export 'src/contracts/forum_display_models.dart';
export 'src/contracts/forum_display_repository.dart';
export 'src/contracts/forum_resource.dart';
export 'src/contracts/forum_image_attachments.dart';
export 'src/network/forum_request.dart' show ForumRequestCancellation;
export 'src/network/forum_multipart.dart'
    show
        ForumMultipartClient,
        ForumMultipartFile,
        ForumMultipartRequest,
        ForumMultipartResponse;
export 'src/contracts/forum_search.dart';
export 'src/contracts/forum_tag_directory.dart';
export 'src/contracts/profile_and_blog.dart';
export 'src/contracts/message_directories.dart';
export 'src/contracts/sticker_catalog.dart';
export 'src/contracts/thread_detail_models.dart';
export 'src/contracts/thread_reply_page.dart';
export 'src/contracts/thread_repository.dart';
export 'src/contracts/thread_interaction_commands.dart';
export 'src/contracts/thread_poll_vote_command.dart';
export 'src/contracts/thread_composer_commands.dart';
export 'src/contracts/thread_post_edit.dart';
export 'src/contracts/thread_supplemental_reads.dart';
export 'src/references/comic_thread_discovery_projector.dart';
export 'src/references/forum_reference_resolver.dart';
export 'src/references/forum_post_image_extractor.dart';
