import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/services/composer_submission_error_presenter.dart';

void main() {
  group('ComposerSubmissionErrorPresenter', () {
    const presenter = ComposerSubmissionErrorPresenter();

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

    group('newThread kind', () {
      test('translates post_type_isnull to "请先选择" guidance', () {
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              code: 'post_type_isnull',
              message: '请选择主题分类',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('请先选择'),
        );
      });

      test('translates post_flood_ctrl to "发帖过于频繁"', () {
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              code: 'post_flood_ctrl',
              message: 'flood',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('发帖过于频繁'),
        );
      });

      test('translates postperm_login_nopermission to "请先登录或检查发帖权限"', () {
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              code: 'postperm_login_nopermission',
              message: 'no permission',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('请先登录'),
        );
      });

      test('uses 发帖 wording for permission errors detected via message text',
          () {
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              message: '没有权限',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('无法发帖'),
        );
      });

      test('uses 发帖 wording for credential errors', () {
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              message: 'formhash error',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('发帖凭证'),
        );
      });

      test('seccode requires fallback to web', () {
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              code: 'seccode_invalid',
              message: 'seccode',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('验证码'),
        );
      });

      test('maps poll-specific business codes to friendly text', () {
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              code: 'post_pollinvalid',
              message: 'invalid poll',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('投票配置无效'),
        );
        expect(
          presenter.present(
            const ApiError(
              type: ApiErrorType.business,
              code: 'polloption_count_invalid',
              message: 'wrong count',
            ),
            kind: ComposerKind.newThread,
          ),
          contains('选项数量不合法'),
        );
      });
    });
  });
}
