import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/domain/favorite_pipeline_models.dart';

void main() {
  group('FavoriteProcessingLevel', () {
    test('has three levels in ascending order', () {
      const levels = FavoriteProcessingLevel.values;
      expect(levels.length, 3);
      expect(levels[0], FavoriteProcessingLevel.bare);
      expect(levels[1], FavoriteProcessingLevel.light);
      expect(levels[2], FavoriteProcessingLevel.full);
    });

    test('bare is the default for unprocessed records', () {
      expect(FavoriteProcessingLevel.bare.name, 'bare');
    });

    test('light and full can be serialized as strings', () {
      expect(FavoriteProcessingLevel.light.name, 'light');
      expect(FavoriteProcessingLevel.full.name, 'full');
    });
  });

  group('FavoritePipelineProgress', () {
    test('idle returns zero counts', () {
      expect(FavoritePipelineProgress.idle.total, 0);
      expect(FavoritePipelineProgress.idle.classifiedCount, 0);
      expect(FavoritePipelineProgress.idle.ingestedCount, 0);
      expect(FavoritePipelineProgress.idle.isActive, isFalse);
    });

    test('classifyFraction returns 0 when total is 0', () {
      const progress = FavoritePipelineProgress(total: 0, classifiedCount: 0);
      expect(progress.classifyFraction, 0.0);
    });

    test('classifyFraction computes ratio correctly', () {
      const progress = FavoritePipelineProgress(total: 10, classifiedCount: 3);
      expect(progress.classifyFraction, closeTo(0.3, 0.01));
    });

    test('classifyFraction clamps to 1.0', () {
      const progress = FavoritePipelineProgress(total: 10, classifiedCount: 12);
      expect(progress.classifyFraction, 1.0);
    });

    test('ingestFraction computes ratio correctly', () {
      const progress = FavoritePipelineProgress(total: 8, ingestedCount: 5);
      expect(progress.ingestFraction, closeTo(0.625, 0.01));
    });

    test('ingestFraction returns 0 when total is 0', () {
      const progress = FavoritePipelineProgress(ingestedCount: 3);
      expect(progress.ingestFraction, 0.0);
    });

    test('isActive returns true when ingestedCount < total', () {
      const progress = FavoritePipelineProgress(total: 5, ingestedCount: 2);
      expect(progress.isActive, isTrue);
    });

    test('isActive returns false when ingestedCount equals total', () {
      const progress = FavoritePipelineProgress(total: 5, ingestedCount: 5);
      expect(progress.isActive, isFalse);
    });

    test('isActive returns false when total is 0', () {
      const progress = FavoritePipelineProgress(total: 0, ingestedCount: 0);
      expect(progress.isActive, isFalse);
    });

    test('message and currentTid are optional', () {
      const progress = FavoritePipelineProgress(
        total: 1,
        currentTid: '12345',
        message: '正在处理',
      );
      expect(progress.currentTid, '12345');
      expect(progress.message, '正在处理');
    });
  });
}
