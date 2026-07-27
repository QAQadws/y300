// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appLanguageSectionTitle => '界面语言';

  @override
  String get appLanguageSystem => '跟随系统';

  @override
  String get appLanguageSimplifiedChinese => '简体中文';

  @override
  String get appLanguageTraditionalChinese => '繁体中文';

  @override
  String appLanguageSaveFailed(String error) {
    return '语言设置保存失败：$error';
  }
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appLanguageSectionTitle => '介面語言';

  @override
  String get appLanguageSystem => '跟隨系統';

  @override
  String get appLanguageSimplifiedChinese => '簡體中文';

  @override
  String get appLanguageTraditionalChinese => '繁體中文';

  @override
  String appLanguageSaveFailed(String error) {
    return '語言設定儲存失敗：$error';
  }
}
