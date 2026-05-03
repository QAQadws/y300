import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/profile/data/profile_repository.dart';
import 'package:y300/features/reply/data/discuz_reply_api_repository.dart';
import 'package:y300/features/reply/data/reply_repository.dart';

final replyRepositoryProvider = Provider<ReplyRepository>((ref) {
  return DiscuzReplyApiRepository(
    profileRepository: ref.read(profileRepositoryProvider),
    cookieStore: ref.read(cookieStoreProvider),
  );
});
