import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_render_planner.dart';

class ThreadDetailRenderEntryPlanner {
  ThreadDetailRenderEntryPlanner({
    ThreadPostBodyRenderPlanner bodyRenderPlanner =
        const ThreadPostBodyRenderPlanner(),
    ThreadPostBodyRenderSettings renderSettings =
        ThreadPostBodyRenderSettings.defaults,
  }) : _bodyRenderPlanner = bodyRenderPlanner,
       _renderSettings = renderSettings;

  final ThreadPostBodyRenderPlanner _bodyRenderPlanner;
  final ThreadPostBodyRenderSettings _renderSettings;
  final Map<ThreadDetailPostBodyRenderPlanCacheKey, ThreadPostBodyRenderPlan>
  _bodyRenderPlanCache =
      <ThreadDetailPostBodyRenderPlanCacheKey, ThreadPostBodyRenderPlan>{};

  List<ThreadDetailRenderEntry> buildEntries({
    required List<ThreadPost> posts,
    String? targetPid,
  }) {
    final entries = <ThreadDetailRenderEntry>[];
    for (var index = 0; index < posts.length; index++) {
      final post = posts[index];
      entries.add(
        ThreadDetailRenderEntry.postHeader(
          key: 'thread-post-header-${post.pid}',
          post: post,
          postIndex: index,
        ),
      );
      final plan = planFor(post);
      if (plan.usesListSegments) {
        for (final segment in plan.segments) {
          entries.add(
            ThreadDetailRenderEntry.postBodySegment(
              key: 'thread-post-body-${post.pid}-${segment.index}',
              post: post,
              postIndex: index,
              plan: plan,
              segment: segment,
            ),
          );
        }
      } else {
        entries.add(
          ThreadDetailRenderEntry.postBody(
            key: 'thread-post-body-${post.pid}',
            post: post,
            postIndex: index,
            resolvePlan: () => planFor(post),
          ),
        );
      }
      entries.add(
        ThreadDetailRenderEntry.postFooter(
          key: 'thread-post-footer-${post.pid}',
          post: post,
          postIndex: index,
        ),
      );
    }
    entries.add(const ThreadDetailRenderEntry.pagination());
    if (targetPid?.trim().isNotEmpty == true) {
      entries.add(const ThreadDetailRenderEntry.targetSpacer());
    }
    return List<ThreadDetailRenderEntry>.unmodifiable(entries);
  }

  ThreadPostBodyRenderPlan planFor(ThreadPost post) {
    final key = _cacheKeyFor(post);
    return _bodyRenderPlanCache.putIfAbsent(
      key,
      () => _bodyRenderPlanner.plan(
        post.message,
        renderSettings: _renderSettings,
      ),
    );
  }

  void prune(List<ThreadPost> posts) {
    final activeKeys = posts.map((post) {
      return _cacheKeyFor(post);
    }).toSet();
    _bodyRenderPlanCache.removeWhere((key, _) => !activeKeys.contains(key));
  }

  ThreadDetailPostBodyRenderPlanCacheKey _cacheKeyFor(ThreadPost post) {
    return ThreadDetailPostBodyRenderPlanCacheKey(
      pid: post.pid,
      message: post.message,
      renderSettingsSignature: _renderSettings.signature,
    );
  }
}

enum ThreadDetailRenderEntryKind {
  postHeader,
  postBody,
  postBodySegment,
  postFooter,
  pagination,
  targetSpacer,
}

class ThreadDetailRenderEntry {
  const ThreadDetailRenderEntry._({
    required this.kind,
    required this.key,
    this.post,
    required this.postIndex,
    this.plan,
    this.segment,
    this.resolvePlan,
  });

  ThreadDetailRenderEntry.postHeader({
    required String key,
    required ThreadPost post,
    required int postIndex,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postHeader,
         key: key,
         post: post,
         postIndex: postIndex,
       );

  ThreadDetailRenderEntry.postBody({
    required String key,
    required ThreadPost post,
    required int postIndex,
    required ThreadPostBodyRenderPlan Function() resolvePlan,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postBody,
         key: key,
         post: post,
         postIndex: postIndex,
         resolvePlan: resolvePlan,
       );

  ThreadDetailRenderEntry.postBodySegment({
    required String key,
    required ThreadPost post,
    required int postIndex,
    required ThreadPostBodyRenderPlan plan,
    required ThreadPostBodySegment segment,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postBodySegment,
         key: key,
         post: post,
         postIndex: postIndex,
         plan: plan,
         segment: segment,
       );

  ThreadDetailRenderEntry.postFooter({
    required String key,
    required ThreadPost post,
    required int postIndex,
  }) : this._(
         kind: ThreadDetailRenderEntryKind.postFooter,
         key: key,
         post: post,
         postIndex: postIndex,
       );

  const ThreadDetailRenderEntry.pagination()
    : this._(
        kind: ThreadDetailRenderEntryKind.pagination,
        key: 'thread-detail-pagination',
        postIndex: -1,
      );

  const ThreadDetailRenderEntry.targetSpacer()
    : this._(
        kind: ThreadDetailRenderEntryKind.targetSpacer,
        key: 'thread-detail-target-scroll-spacer',
        postIndex: -1,
      );

  final ThreadDetailRenderEntryKind kind;
  final String key;
  final ThreadPost? post;
  final int postIndex;
  final ThreadPostBodyRenderPlan? plan;
  final ThreadPostBodySegment? segment;
  final ThreadPostBodyRenderPlan Function()? resolvePlan;

  ThreadPostBodyRenderPlan requirePlan() {
    final existingPlan = plan;
    if (existingPlan != null) {
      return existingPlan;
    }
    final resolver = resolvePlan;
    if (resolver != null) {
      return resolver();
    }
    throw StateError('Thread detail render entry has no body render plan.');
  }
}

class ThreadDetailPostBodyRenderPlanCacheKey {
  const ThreadDetailPostBodyRenderPlanCacheKey({
    required this.pid,
    required this.message,
    required this.renderSettingsSignature,
  });

  final String pid;
  final String message;
  final String renderSettingsSignature;

  @override
  bool operator ==(Object other) {
    return other is ThreadDetailPostBodyRenderPlanCacheKey &&
        other.pid == pid &&
        other.message == message &&
        other.renderSettingsSignature == renderSettingsSignature;
  }

  @override
  int get hashCode => Object.hash(pid, message, renderSettingsSignature);
}
