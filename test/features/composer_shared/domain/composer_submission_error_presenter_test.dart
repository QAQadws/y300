import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/services/composer_submission_failure_classifier.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  group('ComposerSubmissionFailureClassifier', () {
    const classifier = ComposerSubmissionFailureClassifier();

    test('classifies transport errors by stable code', () {
      expect(
        classifier
            .classify(
              const ApiError(
                type: ApiErrorType.unauthorized,
                message: 'forbidden',
              ),
            )
            .code,
        ComposerSubmissionFailureCode.authenticationRequired,
      );
      expect(
        classifier
            .classify(
              const ApiError(type: ApiErrorType.timeout, message: 'timeout'),
            )
            .code,
        ComposerSubmissionFailureCode.timeout,
      );
      expect(
        classifier
            .classify(
              const ApiError(type: ApiErrorType.network, message: 'network'),
            )
            .code,
        ComposerSubmissionFailureCode.network,
      );
    });

    test('recognizes English, Simplified, and Traditional responses', () {
      final cases = <(String, ComposerSubmissionFailureCode)>[
        ('formhash error', ComposerSubmissionFailureCode.credentialExpired),
        ('回复间隔太短', ComposerSubmissionFailureCode.rateLimited),
        ('回覆間隔太短', ComposerSubmissionFailureCode.rateLimited),
        ('没有权限', ComposerSubmissionFailureCode.permissionDenied),
        ('沒有權限', ComposerSubmissionFailureCode.permissionDenied),
        (
          'please login first',
          ComposerSubmissionFailureCode.authenticationRequired,
        ),
      ];

      for (final (message, expected) in cases) {
        final failure = classifier.classify(
          ApiError(type: ApiErrorType.business, message: message),
        );
        expect(failure.code, expected, reason: message);
        expect(failure.detail, message);
      }
    });

    test('classifies Discuz posting and poll codes', () {
      final cases = <(String, ComposerSubmissionFailureCode)>[
        ('post_type_isnull', ComposerSubmissionFailureCode.typeRequired),
        ('post_flood_ctrl', ComposerSubmissionFailureCode.rateLimited),
        (
          'postperm_login_nopermission',
          ComposerSubmissionFailureCode.authenticationRequired,
        ),
        ('seccode_invalid', ComposerSubmissionFailureCode.captchaRequired),
        ('post_pollinvalid', ComposerSubmissionFailureCode.pollInvalid),
        (
          'polloption_count_invalid',
          ComposerSubmissionFailureCode.pollOptionCountInvalid,
        ),
      ];

      for (final (code, expected) in cases) {
        final failure = classifier.classify(
          ApiError(type: ApiErrorType.business, code: code, message: code),
          kind: ComposerKind.newThread,
        );
        expect(failure.code, expected, reason: code);
        expect(failure.kind, ComposerKind.newThread);
      }
    });

    test('unknown server detail is retained only as diagnostic data', () {
      final failure = classifier.classify(
        const ApiError(
          type: ApiErrorType.business,
          message: '审核中 Cookie=secret https://example.com/path',
        ),
      );

      expect(failure.code, ComposerSubmissionFailureCode.unknown);
      expect(failure.detail, contains('Cookie=secret'));
      final simplified = ComposerTextResolver.submissionFailure(
        AppLocalizationsZh(),
        failure,
      );
      final traditional = ComposerTextResolver.submissionFailure(
        AppLocalizationsZhTw(),
        failure,
      );
      expect(simplified, isNot(contains('secret')));
      expect(simplified, isNot(contains('example.com')));
      expect(traditional, isNot(contains('secret')));
      expect(traditional, isNot(contains('example.com')));
    });

    test('localized resolver varies by locale without changing the code', () {
      const failure = ComposerSubmissionFailure(
        code: ComposerSubmissionFailureCode.rateLimited,
        kind: ComposerKind.newThread,
      );

      expect(
        ComposerTextResolver.submissionFailure(AppLocalizationsZh(), failure),
        contains('发帖'),
      );
      expect(
        ComposerTextResolver.submissionFailure(AppLocalizationsZhTw(), failure),
        contains('發帖'),
      );
      expect(failure.code, ComposerSubmissionFailureCode.rateLimited);
    });

    test('submit success localizes its prefix and sanitizes raw detail', () {
      const rawDetail =
          '审核完成 Cookie=secret https://bbs.yamibo.com/forum.php?formhash=token';

      final simplified = ComposerTextResolver.submitSuccess(
        AppLocalizationsZh(),
        ComposerKind.newThread,
        rawDetail,
      );
      final traditional = ComposerTextResolver.submitSuccess(
        AppLocalizationsZhTw(),
        ComposerKind.reply,
        rawDetail,
      );

      expect(simplified, startsWith('发布成功：'));
      expect(traditional, startsWith('回覆成功：'));
      expect(simplified, isNot(contains('secret')));
      expect(simplified, isNot(contains('formhash')));
      expect(traditional, isNot(contains('yamibo.com')));
    });
  });
}
