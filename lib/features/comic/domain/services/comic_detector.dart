import 'package:y300/features/comic/domain/models/comic_models.dart';

/// 漫画识别服务接口，后续可替换成更复杂策略。
abstract class ComicDetector {
  ComicCandidateInfo detect({
    required String fid,
    required String subject,
    required String message,
  });
}
