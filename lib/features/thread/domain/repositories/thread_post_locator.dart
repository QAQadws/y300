import 'package:y300/core/network/api_result.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class ThreadPostLocation {
  const ThreadPostLocation({
    required this.tid,
    required this.pid,
    required this.page,
    required this.url,
    this.detailHandoff,
  });

  final String tid;
  final String pid;
  final int page;
  final String url;
  final ThreadDetailHandoff? detailHandoff;
}

abstract class ThreadPostLocator {
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  });
}
