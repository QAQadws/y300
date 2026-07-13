import 'package:y300/features/novel/domain/models/novel_source_models.dart';

abstract interface class NovelSourceMetadataRecoveryService {
  Future<NovelSourceMetadata> recover(String novelId);
}
