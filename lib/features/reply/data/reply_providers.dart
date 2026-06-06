import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/reply/data/discuz_reply_api_repository.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/data/shared_preferences_reply_draft_repository.dart';
import 'package:y300/features/reply/data/sticker_catalog_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/sticker_bbcode_tokenizer.dart';
import 'package:y300/features/reply/domain/services/sticker_code_normalizer.dart';

final stickerCodeNormalizerProvider = Provider<StickerCodeNormalizer>((_) {
  return const StickerCodeNormalizer();
});

final stickerCatalogRepositoryProvider = Provider<StickerCatalogRepository>((
  ref,
) {
  return AssetStickerCatalogRepository(
    normalizer: ref.read(stickerCodeNormalizerProvider),
  );
});

final stickerGroupsProvider = FutureProvider<List<StickerGroup>>((ref) {
  return ref.read(stickerCatalogRepositoryProvider).loadStickerGroups();
});

final stickerBbCodeTokenizerProvider = Provider<StickerBbCodeTokenizer>((_) {
  return const StickerBbCodeTokenizer();
});

final replyDraftRepositoryProvider = Provider<ReplyDraftRepository>((_) {
  return SharedPreferencesReplyDraftRepository();
});

final replyRepositoryProvider = Provider<ReplyRepository>((ref) {
  return DiscuzReplyApiRepository(
    profileRepository: ref.read(profileRepositoryProvider),
    cookieStore: ref.read(cookieStoreProvider),
  );
});
