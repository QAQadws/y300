import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

class SharedPreferencesReplyDraftRepository implements ReplyDraftRepository {
  SharedPreferencesReplyDraftRepository({
    SharedPreferences? sharedPreferences,
  }) : _sharedPreferences = sharedPreferences;

  static const String _keyPrefix = 'reply_draft.';

  final SharedPreferences? _sharedPreferences;

  @override
  Future<ReplyDraftSnapshot?> loadDraft(ReplyDraftIdentity identity) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_prefsKey(identity));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return _decodeSnapshot(raw);
  }

  @override
  Future<void> saveDraft(ReplyDraftSnapshot draft) async {
    if (draft.isEmpty) {
      await deleteDraft(draft.identity);
      return;
    }

    final prefs = await _prefs();
    await prefs.setString(
      _prefsKey(draft.identity),
      jsonEncode(_encodeSnapshot(draft)),
    );
  }

  @override
  Future<void> deleteDraft(ReplyDraftIdentity identity) async {
    final prefs = await _prefs();
    await prefs.remove(_prefsKey(identity));
  }

  @override
  Future<List<ReplyDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    final prefs = await _prefs();
    final threadKey = _prefsKey(
      ReplyDraftIdentity.thread(fid: fid, tid: tid),
    );
    final postKeyPrefix = '${_keyPrefix}post:$fid:$tid:';
    final drafts = <ReplyDraftSnapshot>[];

    for (final key in prefs.getKeys()) {
      if (key != threadKey && !key.startsWith(postKeyPrefix)) {
        continue;
      }
      final raw = prefs.getString(key);
      if (raw == null) {
        continue;
      }
      final draft = _decodeSnapshot(raw);
      if (draft == null ||
          draft.identity.fid != fid ||
          draft.identity.tid != tid) {
        continue;
      }
      drafts.add(draft);
    }

    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts;
  }

  Future<SharedPreferences> _prefs() async {
    final sharedPreferences = _sharedPreferences;
    if (sharedPreferences != null) {
      return sharedPreferences;
    }
    return SharedPreferences.getInstance();
  }

  String _prefsKey(ReplyDraftIdentity identity) {
    return '$_keyPrefix${identity.storageKey}';
  }

  Map<String, Object?> _encodeSnapshot(ReplyDraftSnapshot snapshot) {
    return <String, Object?>{
      'fid': snapshot.identity.fid,
      'tid': snapshot.identity.tid,
      'repquote': snapshot.identity.repquote,
      'message': snapshot.message,
      'useSignature': snapshot.useSignature,
      'updatedAt': snapshot.updatedAt.toIso8601String(),
    };
  }

  ReplyDraftSnapshot? _decodeSnapshot(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final fid = _stringValue(decoded['fid']);
      final tid = _stringValue(decoded['tid']);
      final message = _stringValue(decoded['message']);
      final updatedAtRaw = _stringValue(decoded['updatedAt']);
      if (fid == null ||
          fid.trim().isEmpty ||
          tid == null ||
          tid.trim().isEmpty ||
          message == null ||
          updatedAtRaw == null) {
        return null;
      }

      final repquote = _stringValue(decoded['repquote']);
      final identity = repquote == null || repquote.trim().isEmpty
          ? ReplyDraftIdentity.thread(fid: fid, tid: tid)
          : ReplyDraftIdentity.post(
              fid: fid,
              tid: tid,
              repquote: repquote,
            );
      return ReplyDraftSnapshot(
        identity: identity,
        message: message,
        useSignature: decoded['useSignature'] is bool
            ? decoded['useSignature'] as bool
            : true,
        updatedAt:
            DateTime.tryParse(updatedAtRaw) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  String? _stringValue(Object? value) {
    if (value is String) {
      return value;
    }
    return null;
  }
}
