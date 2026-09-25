import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';

final dailySignInRepositoryProvider = Provider<ForumDailySignInRepository>(
  (ref) => ref.watch(yamiboForumClientProvider).dailySignIn!,
);

final dailySignInCommandProvider = Provider<ForumDailySignInCommand>(
  (ref) => ref.watch(yamiboForumClientProvider).dailySignInCommand!,
);
