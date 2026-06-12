import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/posting/data/new_thread_remote_data_source.dart';
import 'package:y300/features/posting/data/new_thread_repository.dart';
import 'package:y300/features/posting/data/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/domain/services/new_thread_payload_builder.dart';
import 'package:y300/features/posting/domain/services/new_thread_response_parser.dart';
import 'package:y300/features/posting/domain/services/posting_form_metadata_parser.dart';

/// posting 模块的 Riverpod 接线集合。
///
/// Phase 3 仅注册数据层和领域服务，UI / controller 在 Phase 4-5 接入。
/// composer_shared 提供的草稿 / 上传 / BBCode / 表情等通用能力沿用其同名
/// provider，不在本文件重复声明。

final postingFormMetadataParserProvider =
    Provider<PostingFormMetadataParser>((_) {
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

final newThreadRemoteDataSourceProvider =
    Provider<NewThreadRemoteDataSource>((ref) {
  return DiscuzNewThreadDioRemoteDataSource(
    cookieStore: ref.read(cookieStoreProvider),
  );
});

final newThreadRepositoryProvider = Provider<NewThreadRepository>((ref) {
  return DiscuzNewThreadRepository(
    cookieStore: ref.read(cookieStoreProvider),
    remoteDataSource: ref.read(newThreadRemoteDataSourceProvider),
    parser: ref.read(newThreadResponseParserProvider),
  );
});

final newThreadPayloadBuilderProvider = Provider<NewThreadPayloadBuilder>((_) {
  return const DefaultNewThreadPayloadBuilder();
});
