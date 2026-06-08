import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/reply/data/discuz_reply_api_repository.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_image_picker.dart';
import 'package:y300/features/reply/data/reply_image_upload_remote_data_source.dart';
import 'package:y300/features/reply/data/reply_image_upload_repository.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/data/reply_upload_notification_service.dart';
import 'package:y300/features/reply/data/shared_preferences_reply_draft_repository.dart';
import 'package:y300/features/reply/data/sticker_catalog_repository.dart';
import 'package:y300/features/reply/data/sticker_picker_preferences_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_attach_bbcode_service.dart';
import 'package:y300/features/reply/domain/services/reply_image_upload_coordinator.dart';
import 'package:y300/features/reply/domain/services/reply_submission_error_presenter.dart';
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

final stickerPickerPreferencesRepositoryProvider =
    Provider<StickerPickerPreferencesRepository>((_) {
  return SharedPreferencesStickerPickerPreferencesRepository();
});

final stickerPickerLastGroupIdProvider = FutureProvider.autoDispose<String?>((
  ref,
) {
  return ref
      .read(stickerPickerPreferencesRepositoryProvider)
      .loadLastGroupId();
});

final stickerBbCodeTokenizerProvider = Provider<StickerBbCodeTokenizer>((_) {
  return const StickerBbCodeTokenizer();
});

final replySubmissionErrorPresenterProvider =
    Provider<ReplySubmissionErrorPresenter>((_) {
  return const ReplySubmissionErrorPresenter();
});

final replyDraftRepositoryProvider = Provider<ReplyDraftRepository>((_) {
  return SharedPreferencesReplyDraftRepository();
});

final replyImagePickerProvider = Provider<ReplyImagePicker>((_) {
  return ImagePickerReplyImagePicker();
});

final replyImageUploadRemoteDataSourceProvider =
    Provider<ReplyImageUploadRemoteDataSource>((ref) {
  return DiscuzReplyImageUploadDioDataSource(
    cookieStore: ref.read(cookieStoreProvider),
  );
});

final replyImageUploadRepositoryProvider =
    Provider<ReplyImageUploadRepository>((ref) {
  return DiscuzReplyImageUploadRepository(
    remoteDataSource: ref.read(replyImageUploadRemoteDataSourceProvider),
  );
});

final replyAttachBbCodeServiceProvider = Provider<ReplyAttachBbCodeService>((_) {
  return const ReplyAttachBbCodeService();
});

final replyImageUploadCoordinatorProvider =
    Provider<ReplyImageUploadCoordinator>((ref) {
  return SerialReplyImageUploadCoordinator(
    repository: ref.read(replyImageUploadRepositoryProvider),
  );
});

final replyUploadNotificationServiceProvider =
    Provider<ReplyUploadNotificationService>((_) {
  return FlutterLocalReplyUploadNotificationService();
});

final replyRepositoryProvider = Provider<ReplyRepository>((ref) {
  return DiscuzReplyApiRepository(
    profileRepository: ref.read(profileRepositoryProvider),
    cookieStore: ref.read(cookieStoreProvider),
  );
});
