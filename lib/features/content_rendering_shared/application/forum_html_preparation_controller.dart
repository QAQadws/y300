import 'package:flutter/foundation.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_html_preparation_executor.dart';
import 'forum_preparation_consumer.dart';

/// A mounted consumer owns its document and rejects retired asynchronous work.
final class ForumHtmlPreparationController extends ChangeNotifier {
  ForumHtmlPreparationController({ForumHtmlPreparationExecutor? executor})
    : _executor = executor ?? ForumHtmlPreparationExecutor.shared {
    _consumer = ForumPreparationConsumer<ForumHtmlPreparedRenderDocument>(
      _executor,
    )..addListener(notifyListeners);
  }

  final ForumHtmlPreparationExecutor _executor;
  late final ForumPreparationConsumer<ForumHtmlPreparedRenderDocument>
  _consumer;
  bool _closed = false;

  Object? get identity => _consumer.identity;
  bool get hasError => _consumer.hasError;

  ForumHtmlPreparedRenderDocument? resolve(
    ForumHtmlPreparationRequest request,
  ) => _consumer.resolve(
    identity: request.identity,
    admit: () => _executor.tryAcquire(request),
    prepareSynchronously: _executor.usesBackground(request)
        ? null
        : request.prepareSynchronously,
  );

  void reset() => _consumer.reset();

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _consumer.dispose();
    super.dispose();
  }
}
