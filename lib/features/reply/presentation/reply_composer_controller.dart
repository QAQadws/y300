import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

final replyComposerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReplyComposerController, ReplyComposerState, ReplyComposerArgs>(
      (args) => ReplyComposerController(args),
    );

class ReplyComposerController extends AsyncNotifier<ReplyComposerState> {
  ReplyComposerController(this._args);

  static const Duration _saveDebounce = Duration(milliseconds: 700);

  final ReplyComposerArgs _args;
  Timer? _saveTimer;
  ReplyDraftRepository? _draftRepository;
  ReplyRepository? _replyRepository;
  ReplyComposerState? _latestState;

  @override
  FutureOr<ReplyComposerState> build() async {
    _draftRepository = ref.read(replyDraftRepositoryProvider);
    _replyRepository = ref.read(replyRepositoryProvider);
    ref.onDispose(() {
      _saveTimer?.cancel();
      final current = _latestState;
      if (current != null) {
        unawaited(_saveSnapshot(current));
      }
    });

    final snapshot = await _draftRepository!.loadDraft(_args.identity);
    final initialState = ReplyComposerState.initial(
      target: _args.target,
      message: snapshot?.message ?? '',
      useSignature: snapshot?.useSignature ?? true,
      isPreparing: _shouldPreparePostReply,
    );
    _latestState = initialState;
    if (_shouldPreparePostReply) {
      unawaited(Future<void>.microtask(_preparePostReply));
    }
    return initialState;
  }

  void updateMessage(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _setDataState(
      current.copyWith(
        message: value,
        clearErrorMessage: true,
      ),
    );
    _scheduleDraftSave();
  }

  void toggleUseSignature(bool value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    _setDataState(
      current.copyWith(
        useSignature: value,
        clearErrorMessage: true,
      ),
    );
    _scheduleDraftSave();
  }

  void switchMode(ReplyComposerMode mode) {
    final current = state.value;
    if (current == null || current.mode == mode) {
      return;
    }
    _setDataState(current.copyWith(mode: mode));
  }

  Future<void> retryPreparePostReply() {
    return _preparePostReply();
  }

  Future<void> flushDraft() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final current = _latestState;
    if (current == null) {
      return;
    }
    await _saveSnapshot(current);
  }

  Future<void> discardDraft() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _draftRepository?.deleteDraft(_args.identity);
  }

  Future<ReplyComposerResult> submit() async {
    final current = state.value;
    if (current == null || current.isSubmitting) {
      return const ReplyComposerResult(sent: false, message: '');
    }
    final message = current.message.trim();
    if (message.isEmpty) {
      _setDataState(
        current.copyWith(errorMessage: '请输入回复内容'),
      );
      return const ReplyComposerResult(sent: false, message: '请输入回复内容');
    }

    final preparation = current.preparation;
    final missingPostReference =
        current.target.isPostReply &&
        (current.isPreparing || preparation == null);
    if (missingPostReference) {
      _setDataState(
        current.copyWith(errorMessage: '楼层回复引用准备失败，请重试'),
      );
      return const ReplyComposerResult(
        sent: false,
        message: '楼层回复引用准备失败，请重试',
      );
    }

    _saveTimer?.cancel();
    _saveTimer = null;
    _setDataState(
      current.copyWith(
        isSubmitting: true,
        clearErrorMessage: true,
      ),
    );

    final reference = preparation?.reference;
    final result = await _replyRepository!.sendReply(
      draft: ReplyDraft(
        fid: current.target.fid,
        tid: current.target.tid,
        message: message,
        useSignature: current.useSignature,
        formHash: reference?.formHash,
        repPid: reference?.repPid,
        repPost: reference?.repPost,
        noticeAuthor: reference?.noticeAuthor,
        noticeTrimStr: reference?.noticeTrimStr,
        noticeAuthorMsg: reference?.noticeAuthorMsg,
      ),
    );
    final afterSubmit = state.value ?? current;

    if (result case ApiSuccess<ReplySubmissionResult>(:final data)) {
      await discardDraft();
      _setDataState(
        afterSubmit.copyWith(
          isSubmitting: false,
          message: '',
          clearErrorMessage: true,
        ),
      );
      return ReplyComposerResult.sent(
        data.message.isEmpty ? '回复成功' : data.message,
      );
    }

    final error = (result as ApiFailure<ReplySubmissionResult>).error;
    _setDataState(
      afterSubmit.copyWith(
        isSubmitting: false,
        errorMessage: error.message,
      ),
    );
    await _saveSnapshot(afterSubmit.copyWith(isSubmitting: false));
    return ReplyComposerResult(sent: false, message: error.message);
  }

  void _setDataState(ReplyComposerState value) {
    _latestState = value;
    state = AsyncData(value);
  }

  bool get _shouldPreparePostReply {
    return _args.target.isPostReply && _args.replyFormUri != null;
  }

  Future<void> _preparePostReply() async {
    final replyFormUri = _args.replyFormUri;
    if (replyFormUri == null || !_args.target.isPostReply) {
      return;
    }
    final current = state.value ?? _latestState;
    if (current != null) {
      _setDataState(
        current.copyWith(
          isPreparing: true,
          clearPreparation: true,
          clearPreparationError: true,
          clearErrorMessage: true,
        ),
      );
    }

    final result = await _replyRepository!.preparePostReply(
      replyFormUri: replyFormUri,
    );
    final latest = state.value ?? _latestState;
    if (latest == null) {
      return;
    }
    if (result case ApiSuccess<ReplyPreparation>(:final data)) {
      _setDataState(
        latest.copyWith(
          isPreparing: false,
          preparation: data,
          clearPreparationError: true,
        ),
      );
      return;
    }
    final error = (result as ApiFailure<ReplyPreparation>).error;
    _setDataState(
      latest.copyWith(
        isPreparing: false,
        preparationError: error.message,
        errorMessage: error.message,
      ),
    );
  }

  void _scheduleDraftSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      unawaited(flushDraft());
    });
  }

  Future<void> _saveSnapshot(ReplyComposerState value) async {
    try {
      await _draftRepository?.saveDraft(
        ReplyDraftSnapshot(
          identity: _args.identity,
          message: value.message,
          useSignature: value.useSignature,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // 草稿保存失败不阻断编辑或发送；用户仍可继续完成当前回复。
    }
  }
}
