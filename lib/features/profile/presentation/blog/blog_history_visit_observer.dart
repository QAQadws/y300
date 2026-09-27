import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/blog_history_target.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_history_visit_mapper.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Lives outside the account-keyed read view, so an account change or a refresh
/// cannot turn the same visible route into another visit.
class BlogHistoryVisitObserver extends ConsumerStatefulWidget {
  const BlogHistoryVisitObserver({
    super.key,
    required this.controller,
    required this.child,
  });

  final ProfileBlogDetailController controller;
  final Widget child;

  @override
  ConsumerState<BlogHistoryVisitObserver> createState() =>
      _BlogHistoryVisitObserverState();
}

class _BlogHistoryVisitObserverState
    extends ConsumerState<BlogHistoryVisitObserver> {
  final _attempted = <HistoryTargetKey>{};
  bool _active = true;
  bool _routeIsCurrent = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onReadChanged);
  }

  @override
  void didUpdateWidget(covariant BlogHistoryVisitObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onReadChanged);
      widget.controller.addListener(_onReadChanged);
    }
  }

  @override
  void deactivate() {
    // Descendant read views cancel during teardown while this State is still
    // mounted; their notifications must not consult a deactivated provider scope.
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onReadChanged);
    super.dispose();
  }

  void _onReadChanged() {
    if (!mounted || !_active || !_routeIsCurrent) return;
    // The child activates reads during mounting. Listening without setState
    // avoids marking its already-building ancestor dirty on that notification.
    _schedule(
      controller: widget.controller,
      state: widget.controller.value,
      accountOwner: ref.read(blogMutationBusProvider),
      recorder: ref.read(historyVisitRecorderProvider),
      navigation: ref.read(userBlogNavigationProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountOwner = ref.watch(blogMutationBusProvider);
    final recorder = ref.watch(historyVisitRecorderProvider);
    final navigation = ref.watch(userBlogNavigationProvider);
    _routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeIsCurrent) {
      _schedule(
        controller: widget.controller,
        state: widget.controller.value,
        accountOwner: accountOwner,
        recorder: recorder,
        navigation: navigation,
      );
    }
    return widget.child;
  }

  void _schedule({
    required ProfileBlogDetailController controller,
    required UserBlogDetailPageState state,
    required Object accountOwner,
    required HistoryVisitRecorder recorder,
    required UserBlogNavigation? navigation,
  }) {
    if (state.isLoading || state.failure != null || state.data == null) return;
    final data = state.data!;
    final HistoryTargetKey target;
    try {
      target = BlogHistoryTarget(
        ownerUserId: data.ownerUserId,
        blogId: data.blogId,
      ).key;
      final expected = BlogHistoryTarget(
        ownerUserId: state.query.ownerUserId,
        blogId: state.query.blogId,
      ).key;
      if (target != expected || _attempted.contains(target)) return;
    } on FormatException {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          !_active ||
          !identical(widget.controller, controller) ||
          !identical(ref.read(blogMutationBusProvider), accountOwner) ||
          ModalRoute.of(context)?.isCurrent == false ||
          !identical(controller.value, state) ||
          !_attempted.add(target)) {
        return;
      }
      try {
        await recorder.record(
          const BlogHistoryVisitMapper().map(
            data: data,
            navigation: navigation,
          ),
        );
      } catch (error) {
        // History is best-effort, and a rebuild must not replay a failed write.
        debugPrint(
          '[BlogDetail][history_record_failure] error=${error.runtimeType}',
        );
      }
    });
  }
}
