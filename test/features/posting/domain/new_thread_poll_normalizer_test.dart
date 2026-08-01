import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/services/new_thread_poll_normalizer.dart';

void main() {
  const normalizer = NewThreadPollNormalizer();

  group('NewThreadPollNormalizer', () {
    test('returns empty draft when input is null', () {
      final result = normalizer.normalize(null);
      expect(result.options, isEmpty);
      expect(result.multiple, isFalse);
      expect(result.maxChoices, 1);
      expect(result.expirationDays, 0);
    });

    test('trims options and drops empties', () {
      final result = normalizer.normalize(
        const NewThreadPollDraft(options: ['  A ', '', '  ', 'B']),
      );
      expect(result.options, ['A', 'B']);
    });

    test('caps options at maxOptions', () {
      final tooMany = List<String>.generate(
        NewThreadPollValidation.maxOptions + 5,
        (i) => 'opt$i',
      );
      final result = normalizer.normalize(NewThreadPollDraft(options: tooMany));
      expect(result.options.length, NewThreadPollValidation.maxOptions);
    });

    test('single mode forces maxChoices to 1 even if input lied', () {
      final result = normalizer.normalize(
        const NewThreadPollDraft(
          options: ['A', 'B', 'C'],
          multiple: false,
          maxChoices: 5,
        ),
      );
      expect(result.maxChoices, 1);
    });

    test('multiple mode bumps maxChoices to >= 2', () {
      final result = normalizer.normalize(
        const NewThreadPollDraft(
          options: ['A', 'B', 'C'],
          multiple: true,
          maxChoices: 1,
        ),
      );
      expect(result.maxChoices, greaterThanOrEqualTo(2));
    });

    test('multiple mode clamps maxChoices to options count', () {
      final result = normalizer.normalize(
        const NewThreadPollDraft(
          options: ['A', 'B'],
          multiple: true,
          maxChoices: 99,
        ),
      );
      expect(result.maxChoices, 2);
    });

    test('negative expirationDays floor to 0', () {
      final result = normalizer.normalize(
        const NewThreadPollDraft(options: ['A', 'B'], expirationDays: -3),
      );
      expect(result.expirationDays, 0);
    });

    test('passes overt and visibilityPoll through unchanged', () {
      final result = normalizer.normalize(
        const NewThreadPollDraft(
          options: ['A', 'B'],
          overt: true,
          visibilityPoll: true,
        ),
      );
      expect(result.overt, isTrue);
      expect(result.visibilityPoll, isTrue);
    });
  });
}
