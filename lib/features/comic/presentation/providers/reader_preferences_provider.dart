// 兼容性 re-export：阅读偏好 provider 与 repository 已上移到 `reader_shared`，
// 供漫画与帖子图片阅读器共享。保留本文件以避免大面积 import 抖动；新代码请直接
// 引用 `reader_shared/presentation/reader_preferences/reader_preferences_provider.dart`。
export 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';
