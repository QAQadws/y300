import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

/// Native thread details remain HTML-first in production.
final threadRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ref.watch(yamiboForumClientProvider).threadDetail!;
});

/// Structured v4 reads used by comic/favorite adapters.
final threadJsonRepositoryProvider = Provider<ThreadRepository>((ref) {
  return ref
      .watch(yamiboForumClientAdapterFactoryProvider)
      .createApiThreadDetail(apiVersion: '4');
});

final threadPostLocatorProvider = Provider<ThreadPostLocator>((ref) {
  return HtmlThreadPostLocator(gateway: ref.watch(yamiboHttpGatewayProvider));
});
