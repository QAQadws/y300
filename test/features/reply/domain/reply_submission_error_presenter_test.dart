import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/domain/services/reply_submission_error_presenter.dart';

void main() {
  group('ReplySubmissionErrorPresenter', () {
    const presenter = ReplySubmissionErrorPresenter();

    test('maps unauthorized to relogin message', () {
      expect(
        presenter.present(
          const ApiError(type: ApiErrorType.unauthorized, message: 'forbidden'),
        ),
        contains('重新登录'),
      );
    });

    test('maps formhash and session errors', () {
      expect(
        presenter.present(
          const ApiError(type: ApiErrorType.business, message: 'formhash error'),
        ),
        contains('回复凭证'),
      );
    });

    test('maps rate limit errors', () {
      expect(
        presenter.present(
          const ApiError(type: ApiErrorType.business, message: '回复间隔太短'),
        ),
        contains('稍后再试'),
      );
    });

    test('maps permission errors', () {
      expect(
        presenter.present(
          const ApiError(type: ApiErrorType.business, message: '没有权限'),
        ),
        contains('权限不足'),
      );
    });

    test('maps network and timeout errors', () {
      expect(
        presenter.present(
          const ApiError(type: ApiErrorType.timeout, message: 'timeout'),
        ),
        contains('网络超时'),
      );
      expect(
        presenter.present(
          const ApiError(type: ApiErrorType.network, message: 'network'),
        ),
        contains('网络异常'),
      );
    });

    test('keeps unmatched business message', () {
      expect(
        presenter.present(
          const ApiError(type: ApiErrorType.business, message: '回复需要审核'),
        ),
        '回复需要审核',
      );
    });
  });
}
