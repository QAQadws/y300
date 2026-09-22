import 'package:y300/core/network/api_result.dart';

class ThreadPostLocation {
  const ThreadPostLocation({
    required this.tid,
    required this.pid,
    required this.page,
    required this.url,
  });

  final String tid;
  final String pid;
  final int page;
  final String url;
}

abstract class ThreadPostLocator {
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  });
}
