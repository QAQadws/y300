import '../network/forum_request.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_api_client.dart';

/// Reads only a verified thread identity and its current permission value.
final class DiscuzThreadReadAccessReader {
  /// Uses the existing authenticated API transport.
  const DiscuzThreadReadAccessReader(this.api);

  /// API facade sharing the host session.
  final DiscuzApiClient api;

  /// Returns null if identity, response version or access cannot be proved.
  Future<int?> load({
    required String tid,
    String? fid,
    ForumRequestCancellation? cancellation,
  }) async {
    final result = await api.get(
      module: 'viewthread',
      queryParameters: {'version': '4', 'tid': tid, 'page': 1},
      cancellation: cancellation,
    );
    if (cancellation?.isCancelled ?? false) return null;
    if (result case ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
      :final response,
    )) {
      final variables = response.body.variables;
      final thread = variables['thread'];
      if (response.body.version != '4' ||
          thread is! Map ||
          thread['tid']?.toString() != tid ||
          (fid != null &&
              (variables['fid'] ?? thread['fid'])?.toString() != fid)) {
        return null;
      }
      final value = int.tryParse(thread['readperm']?.toString() ?? '');
      if (value != null && value >= 0 && value <= 255) return value;
    }
    return null;
  }
}
