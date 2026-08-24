import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/thread/data/services/thread_detail_document_decoder.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Native thread details remain HTML-first in production.
final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ref.watch(yamiboForumClientProvider).threadDetail!;
});

/// Source-neutral structured detail used by ingestion and metadata recovery.
/// Production composition currently binds this role to Discuz v4.
final threadIngestionRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ref.watch(yamiboForumClientProvider).threadIngestionDetail!;
});

final threadReplyPageRepositoryProvider = Provider<ThreadReplyPageRepository>((
  ref,
) {
  return ref.watch(yamiboForumClientProvider).threadReplyPage!;
});

final threadDetailDocumentDecoderProvider =
    Provider<ThreadDetailDocumentDecoder>((ref) {
      return ThreadDetailDocumentDecoder(
        ref.watch(yamiboThreadDetailHtmlDecoderProvider),
      );
    });

final threadPostLocatorProvider = Provider<ThreadPostLocator>((ref) {
  return HtmlThreadPostLocator(
    gateway: ref.watch(yamiboHttpGatewayProvider),
    decoder: ref.watch(threadDetailDocumentDecoderProvider),
  );
});
