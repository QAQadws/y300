import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/thread/data/thread_favorite_providers.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

class ThreadDetailArgs {
  const ThreadDetailArgs({required this.tid, this.subject = ''});

  final String tid;
  final String subject;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ThreadDetailArgs && other.tid == tid && other.subject == subject;
  }

  @override
  int get hashCode => Object.hash(tid, subject);
}

final threadDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadDetailController, ThreadDetailPageState, ThreadDetailArgs>(
      (args) => ThreadDetailController(args),
    );

/// viewthread 分页控制器，支持首屏加载和向后翻页。
class ThreadDetailController extends AsyncNotifier<ThreadDetailPageState> {
  ThreadDetailController(this._args);

  final ThreadDetailArgs _args;

  @override
  FutureOr<ThreadDetailPageState> build() async {
    return _loadPage(page: 1, previous: const <ThreadPost>[]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadPage(page: 1, previous: const <ThreadPost>[]),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    final result = await _readRepository().getThreadDetail(
      tid: _args.tid,
      page: current.currentPage + 1,
    );

    state = result.when(
      success: (data) {
        final merged = <ThreadPost>[...current.posts, ...data.posts];
        return AsyncData(
          current.copyWith(
            subject: data.subject.isNotEmpty ? data.subject : current.subject,
            currentPage: data.currentPage,
            hasMore: data.hasMore,
            isLoadingMore: false,
            posts: merged,
            clearError: true,
          ),
        );
      },
      failure: (error) {
        return AsyncData(
          current.copyWith(
            isLoadingMore: false,
            errorMessage: error.message,
          ),
        );
      },
    );
  }

  Future<void> addToShelf() async {
    final current = state.value;
    if (current == null ||
        current.isComicActionLoading ||
        current.contentKind != ThreadContentKind.comic) {
      return;
    }
    final snapshot = current;

    state = AsyncData(snapshot.copyWith(isComicActionLoading: true, clearError: true));
    final comicId = _buildComicId(tid: snapshot.tid);

    try {
      await _readComicRepository().addToShelf(
        comicId: comicId,
        tid: snapshot.tid,
        fid: snapshot.fid,
        sourceTypeId: snapshot.typeid,
        sourceTagName: snapshot.sourceTagName,
        title: snapshot.subject,
        parsedPost: snapshot.parsedComicPost,
      );

      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(
          isComicActionLoading: false,
          isInShelf: true,
        ),
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(
          isComicActionLoading: false,
          errorMessage: '加入书架失败：$error',
        ),
      );
    }
  }

  Future<void> addNovelToShelf() async {
    final current = state.value;
    if (current == null ||
        current.isNovelActionLoading ||
        current.contentKind != ThreadContentKind.novel) {
      return;
    }
    final snapshot = current;

    state = AsyncData(
      snapshot.copyWith(
        isNovelActionLoading: true,
        clearError: true,
      ),
    );

    try {
      final fid = current.fid.trim();
      final tid = current.tid.trim();
      final repository = ref.read(novelRepositoryProvider);
      final novelId = 'novel:$fid:$tid';

      await repository.upsertNovelBySeed(
        seed: NovelRefreshSeed(
          fid: fid,
          tid: tid,
          typeid: current.typeid,
          tagName: current.sourceTagName,
        ),
      );
      await repository.refreshEpisodes(novelId: novelId);

      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(
          isNovelActionLoading: false,
          isNovelInShelf: true,
        ),
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(
          isNovelActionLoading: false,
          errorMessage: '加入小说书架失败：$error',
        ),
      );
    }
  }

  Future<void> favoriteThread() async {
    final current = state.value;
    if (current == null ||
        current.isThreadFavoriteActionLoading ||
        current.isThreadFavorited) {
      return;
    }
    final snapshot = current;

    state = AsyncData(
      snapshot.copyWith(
        isThreadFavoriteActionLoading: true,
        clearThreadFavoriteHint: true,
        clearError: true,
      ),
    );

    final result = await ref.read(threadFavoriteActionServiceProvider).favoriteThread(
          tid: snapshot.tid,
        );
    if (!ref.mounted) {
      return;
    }
    final afterAction = state.value ?? snapshot;
    state = result.when(
      success: (data) => AsyncData(
        afterAction.copyWith(
          isThreadFavoriteActionLoading: false,
          isThreadFavorited: true,
          threadFavoriteHint: data.message,
        ),
      ),
      failure: (error) => AsyncData(
        afterAction.copyWith(
          isThreadFavoriteActionLoading: false,
          threadFavoriteHint: error.message,
        ),
      ),
    );
  }

  void updateReplyText(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        replyText: value,
        clearReplyHint: true,
      ),
    );
  }

  Future<void> submitReply() async {
    final current = state.value;
    if (current == null || current.isReplySubmitting) {
      return;
    }
    final message = current.replyText.trim();
    if (message.isEmpty) {
      state = AsyncData(
        current.copyWith(replyHint: '请输入回复内容'),
      );
      return;
    }

    state = AsyncData(
      current.copyWith(
        isReplySubmitting: true,
        clearReplyHint: true,
      ),
    );

    final result = await ref.read(replyRepositoryProvider).sendReply(
          draft: ReplyDraft(
            fid: current.fid,
            tid: current.tid,
            message: message,
          ),
        );

    final afterSubmit = state.value ?? current;
    state = result.when(
      success: (data) => AsyncData(
        afterSubmit.copyWith(
          isReplySubmitting: false,
          replyText: '',
          replyHint: data.message.isEmpty ? '回复成功' : data.message,
        ),
      ),
      failure: (error) => AsyncData(
        afterSubmit.copyWith(
          isReplySubmitting: false,
          replyHint: error.message,
        ),
      ),
    );

    if (result.isSuccess) {
      final latest = state.value;
      if (latest == null) {
        return;
      }
      final reloaded = await _loadPage(page: 1, previous: const <ThreadPost>[]);
      state = AsyncData(
        reloaded.copyWith(
          replyHint: latest.replyHint,
          replyText: latest.replyText,
          isThreadFavorited: latest.isThreadFavorited,
          threadFavoriteHint: latest.threadFavoriteHint,
        ),
      );
    }
  }

  Future<ThreadDetailPageState> _loadPage({
    required int page,
    required List<ThreadPost> previous,
  }) async {
    final result = await _readRepository().getThreadDetail(tid: _args.tid, page: page);

    if (result case ApiSuccess<ThreadDetailData>(:final data)) {
      final merged = page == 1 ? data.posts : <ThreadPost>[...previous, ...data.posts];
      final aggregation = ref.read(comicPostAggregationServiceProvider).build(merged);
      final subject = data.subject.isNotEmpty ? data.subject : _args.subject;
      final sourceTagName = await _findSourceTagName(
        fid: data.fid,
        typeid: data.typeid,
      );
      final contentKind = ref.read(threadContentClassifierProvider).classify(
            fid: data.fid,
            typeid: data.typeid,
            tagName: sourceTagName,
          );
      final comicMeta = _parseComicWhenTagged(
        isComic: contentKind == ThreadContentKind.comic,
        subject: data.subject.isNotEmpty ? data.subject : _args.subject,
        parseMessage: aggregation.parseMessage,
        attachmentImageUrls: aggregation.attachmentImageUrls,
      );
      // 内容类型由 fid + typeid + 来源标签统一判定，避免漫画/小说入口各自维护规则。
      final comicCandidate = contentKind == ThreadContentKind.comic;
      final comicId = _buildComicId(tid: _args.tid);
      final isInShelf = comicCandidate
          ? await _readComicRepository().isInShelf(comicId: comicId)
          : false;
      final novelCandidate = contentKind == ThreadContentKind.novel;
      var isNovelInShelf = false;
      if (novelCandidate) {
        final novelId = 'novel:${data.fid}:${_args.tid}';
        isNovelInShelf = await ref.read(novelRepositoryProvider).getDetail(novelId: novelId) != null;
      }

      return ThreadDetailPageState(
        tid: _args.tid,
        fid: data.fid,
        typeid: data.typeid,
        sourceTagName: sourceTagName,
        contentKind: contentKind,
        subject: subject,
        currentPage: data.currentPage,
        hasMore: data.hasMore,
        isLoadingInitial: false,
        isLoadingMore: false,
        posts: merged,
        comicCandidateInfo: comicMeta.$1,
        parsedComicPost: comicMeta.$2,
        isInShelf: isInShelf,
        isComicActionLoading: false,
        isNovelCandidate: novelCandidate,
        isNovelInShelf: isNovelInShelf,
        isNovelActionLoading: false,
        isThreadFavorited: false,
        isThreadFavoriteActionLoading: false,
        threadFavoriteHint: null,
        replyText: '',
        isReplySubmitting: false,
        replyHint: null,
      );
    }

    final error = (result as ApiFailure<ThreadDetailData>).error;
    return ThreadDetailPageState(
      tid: _args.tid,
      fid: '',
      typeid: '',
      sourceTagName: null,
      contentKind: ThreadContentKind.forum,
      subject: _args.subject,
      currentPage: page == 1 ? 0 : page,
      hasMore: false,
      isLoadingInitial: false,
      isLoadingMore: false,
      posts: previous,
      comicCandidateInfo: ComicCandidateInfo.notCandidate,
      parsedComicPost: ParsedComicPost.empty,
      isInShelf: false,
      isComicActionLoading: false,
      isNovelCandidate: false,
      isNovelInShelf: false,
      isNovelActionLoading: false,
      isThreadFavorited: false,
      isThreadFavoriteActionLoading: false,
      threadFavoriteHint: null,
      replyText: '',
      isReplySubmitting: false,
      replyHint: null,
      errorMessage: error.message,
    );
  }

  ThreadRepository _readRepository() {
    return ref.read(threadRepositoryProvider);
  }

  ComicRepository _readComicRepository() {
    return ref.read(comicRepositoryProvider);
  }

  (ComicCandidateInfo, ParsedComicPost) _parseComicWhenTagged({
    required bool isComic,
    required String subject,
    required String parseMessage,
    required List<String> attachmentImageUrls,
  }) {
    if (!isComic || (parseMessage.isEmpty && attachmentImageUrls.isEmpty)) {
      return (ComicCandidateInfo.notCandidate, ParsedComicPost.empty);
    }

    final parser = ref.read(comicParserServiceProvider);
    final subjectParser = ref.read(comicSubjectParserProvider);
    final parsed = parser.parseInput(
      ComicPostParseInput(
        messageHtml: parseMessage,
        attachmentImageUrls: attachmentImageUrls,
      ),
    ).copyWith(
          subjectMetadata: subjectParser.parse(subject),
        );
    return (
      const ComicCandidateInfo(
        isCandidate: true,
        score: 100,
        reasons: <String>['tag-rule'],
      ),
      parsed,
    );
  }

  String _buildComicId({required String tid}) {
    return 'yamibo:$tid';
  }

  Future<String?> _findSourceTagName({
    required String fid,
    required String typeid,
  }) async {
    if (fid.trim().isEmpty || typeid.trim().isEmpty) {
      return null;
    }
    try {
      final lookup = await ref.read(forumTagLookupProvider.future);
      return lookup.findName(fid: fid, typeid: typeid);
    } catch (_) {
      // 标签 asset 失败不应阻断帖子正文；分类服务仍会用公告 typeid 兜底。
      return null;
    }
  }
}
