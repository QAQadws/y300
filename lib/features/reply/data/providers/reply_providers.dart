import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/profile/data/repositories/profile_repository.dart';
import 'package:y300/features/reply/data/repositories/discuz_reply_api_repository.dart';
import 'package:y300/features/reply/data/services/reply_form_preparation_data_source.dart';
import 'package:y300/features/reply/data/repositories/reply_repository.dart';
import 'package:y300/features/reply/domain/services/reply_draft_validator.dart';
import 'package:y300/features/reply/domain/services/reply_form_parser.dart';

/// reply 模块的 Riverpod 接线。Phase 1 之后，编辑器/上传/草稿/表情/BBCode 等
/// 通用能力都改由 [composer_shared/data/composer_providers.dart] 提供，
/// 这里只保留"提交回复"业务专属的 provider。
///
/// 旧的、已经迁移到 composer_shared 的 provider 命名（例如
/// `replyImageUploadCoordinatorProvider`、`stickerGroupsProvider`）不再
/// 出现在此文件，调用方请直接依赖 composer_shared 的同名 provider。

final replyFormParserProvider = Provider<ReplyFormParser>((_) {
  return const ReplyFormParser();
});

final replyDraftValidatorProvider = Provider<ReplyDraftValidator>((_) {
  return const ReplyDraftValidator();
});

final replyFormPreparationDataSourceProvider =
    Provider<ReplyFormPreparationDataSource>((ref) {
      return DiscuzReplyFormPreparationDataSource(
        gateway: ref.read(yamiboHttpGatewayProvider),
        parser: ref.read(replyFormParserProvider),
      );
    });

final replyRepositoryProvider = Provider<ReplyRepository>((ref) {
  return DiscuzReplyApiRepository(
    profileRepository: ref.read(profileRepositoryProvider),
    cookieStore: ref.read(cookieStoreProvider),
    gateway: ref.read(yamiboHttpGatewayProvider),
    preparationDataSource: ref.read(replyFormPreparationDataSourceProvider),
    validator: ref.read(replyDraftValidatorProvider),
  );
});
