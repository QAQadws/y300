import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/posting/data/services/new_thread_remote_data_source.dart';
import 'package:y300/features/posting/data/repositories/new_thread_repository.dart';
import 'package:y300/features/posting/data/repositories/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/domain/services/new_thread_payload_builder.dart';
import 'package:y300/features/posting/domain/services/new_thread_poll_normalizer.dart';
import 'package:y300/features/posting/domain/services/new_thread_response_parser.dart';
import 'package:y300/features/posting/domain/services/new_thread_tags_normalizer.dart';
import 'package:y300/features/posting/domain/services/posting_draft_extras_codec.dart';
import 'package:y300/features/posting/domain/services/posting_form_metadata_parser.dart';

/// posting 模块的 Riverpod 接线集合。
///
/// Phase 3 仅注册数据层和领域服务，UI / controller 在 Phase 4-5 接入。
/// composer_shared 提供的草稿 / 上传 / BBCode / 表情等通用能力沿用其同名
/// provider，不在本文件重复声明。
///
/// Phase 5+ 增量：tags / poll normalizer + draft extras codec。

final postingFormMetadataParserProvider = Provider<PostingFormMetadataParser>((
  _,
) {
  return const PostingFormMetadataParser();
});

final postingFormMetadataRepositoryProvider =
    Provider<PostingFormMetadataRepository>((ref) {
      return DiscuzPostingFormMetadataRepository(
        ref.watch(apiClientProvider),
        parser: ref.read(postingFormMetadataParserProvider),
      );
    });

final newThreadResponseParserProvider = Provider<NewThreadResponseParser>((_) {
  return const NewThreadResponseParser();
});

final newThreadRemoteDataSourceProvider = Provider<NewThreadRemoteDataSource>((
  ref,
) {
  return DiscuzNewThreadDioRemoteDataSource(
    gateway: ref.read(yamiboHttpGatewayProvider),
  );
});

final newThreadRepositoryProvider = Provider<NewThreadRepository>((ref) {
  return DiscuzNewThreadRepository(
    remoteDataSource: ref.read(newThreadRemoteDataSourceProvider),
    parser: ref.read(newThreadResponseParserProvider),
  );
});

final newThreadTagsNormalizerProvider = Provider<NewThreadTagsNormalizer>((_) {
  return const NewThreadTagsNormalizer();
});

final newThreadPollNormalizerProvider = Provider<NewThreadPollNormalizer>((_) {
  return const NewThreadPollNormalizer();
});

final postingDraftExtrasCodecProvider = Provider<PostingDraftExtrasCodec>((_) {
  return const PostingDraftExtrasCodec();
});

final newThreadPayloadBuilderProvider = Provider<NewThreadPayloadBuilder>((
  ref,
) {
  return DefaultNewThreadPayloadBuilder(
    tagsNormalizer: ref.watch(newThreadTagsNormalizerProvider),
    pollNormalizer: ref.watch(newThreadPollNormalizerProvider),
  );
});
