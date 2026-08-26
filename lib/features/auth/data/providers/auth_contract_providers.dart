import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';

final forumSessionRepositoryProvider = Provider<ForumSessionRepository>((ref) {
  final repository = ref.watch(yamiboForumClientProvider).session;
  if (repository == null) {
    throw StateError('forum_session_repository_not_installed');
  }
  return repository;
});

final forumPasswordLoginCommandProvider = Provider<ForumPasswordLoginCommand>((
  ref,
) {
  final command = ref.watch(yamiboForumClientProvider).passwordLogin;
  if (command == null) {
    throw StateError('forum_password_login_not_installed');
  }
  return command;
});

final forumLogoutCommandProvider = Provider<ForumLogoutCommand>((ref) {
  final command = ref.watch(yamiboForumClientProvider).logout;
  if (command == null) {
    throw StateError('forum_logout_not_installed');
  }
  return command;
});
