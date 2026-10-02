// ignore_for_file: public_member_api_docs

import '../cache/forum_cache.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';

typedef AccountSummarySnapshot =
    DataReadSuccess<CurrentUserProfileData, CurrentUserProfileReadCapabilities>;

/// Only the validated projection is stored, never the private source page.
final class AccountSummarySnapshotCodec
    implements ForumSnapshotCodec<AccountSummarySnapshot> {
  const AccountSummarySnapshotCodec();

  @override
  String get snapshotType => 'profile.account.summary';
  @override
  int get codecVersion => 1;
  @override
  int get parserVersion => 1;
  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) => codecVersion == 1 && parserVersion == 1;

  @override
  Object encode(AccountSummarySnapshot value) => {
    'uid': value.data.identity.userId,
    'name': value.data.identity.displayName,
    'avatar': value.data.avatarUrl,
    'groupId': value.data.groupId,
    'groupName': value.data.groupName,
    'credits': value.data.creditTotal,
    'threads': value.data.threadCount,
    'replies': value.data.replyCount,
    'capabilities': {
      for (final entry in value.capabilities.values.values.entries)
        entry.key.name: entry.value.name,
    },
  };

  @override
  AccountSummarySnapshot decode(Object? json) {
    final map = json as Map<String, dynamic>;
    final uid = map['uid'] as String;
    final threads = map['threads'] as int?;
    final replies = map['replies'] as int?;
    if (!RegExp(r'^[1-9]\d*$').hasMatch(uid) ||
        (threads != null && threads < 0) ||
        (replies != null && replies < 0)) {
      throw const FormatException('invalid_account_summary_snapshot');
    }
    final caps = map['capabilities'] as Map<String, dynamic>;
    return DataReadSuccess(
      data: CurrentUserProfileData(
        identity: ProfileUserIdentity(
          userId: uid,
          displayName: map['name'] as String?,
        ),
        avatarUrl: map['avatar'] as String?,
        groupId: map['groupId'] as String?,
        groupName: map['groupName'] as String?,
        creditTotal: map['credits'] as int?,
        threadCount: threads,
        replyCount: replies,
      ),
      capabilities: CurrentUserProfileReadCapabilities(
        values: DataCapabilitySet({
          for (final entry in caps.entries)
            CurrentUserProfileCapability.values.byName(entry.key):
                DataCapabilitySupport.values.byName(entry.value as String),
        }),
      ),
      metadata: const DataReadMetadata(
        origin: DataReadOrigin.freshSnapshot,
        freshness: DataReadFreshness.staleOrUnknown,
      ),
    );
  }
}
