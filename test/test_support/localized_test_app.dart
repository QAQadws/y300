import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The common application shell for widget tests.
///
/// Keeping framework delegates here makes every test ready for app-level l10n
/// without duplicating localization configuration in individual test files.
/// The app localization delegate can be added here when the ARB phase lands.
class LocalizedTestApp extends MaterialApp {
  const LocalizedTestApp({
    super.key,
    super.navigatorKey,
    super.scaffoldMessengerKey,
    super.home,
    super.routes,
    super.initialRoute,
    super.onGenerateRoute,
    super.onGenerateInitialRoutes,
    super.onUnknownRoute,
    super.onNavigationNotification,
    super.navigatorObservers,
    super.builder,
    super.title,
    super.onGenerateTitle,
    super.color,
    super.theme,
    super.darkTheme,
    super.highContrastTheme,
    super.highContrastDarkTheme,
    super.themeMode,
    super.themeAnimationDuration,
    super.themeAnimationCurve,
    super.locale = const Locale('zh', 'CN'),
    Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates,
    super.localeListResolutionCallback,
    super.localeResolutionCallback,
    super.supportedLocales = _defaultSupportedLocales,
    super.debugShowMaterialGrid,
    super.showPerformanceOverlay,
    super.checkerboardRasterCacheImages,
    super.checkerboardOffscreenLayers,
    super.showSemanticsDebugger,
    super.debugShowCheckedModeBanner,
    super.shortcuts,
    super.actions,
    super.restorationScopeId,
    super.scrollBehavior,
    super.themeAnimationStyle,
  }) : super(
         localizationsDelegates:
             localizationsDelegates ?? _defaultLocalizationsDelegates,
       );

  static const List<Locale> _defaultSupportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
  ];

  static const List<LocalizationsDelegate<dynamic>>
  _defaultLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ];
}

/// Lightweight form for tests that only need a localized home widget.
Widget localizedTestApp({
  required Widget home,
  Locale locale = const Locale('zh', 'CN'),
}) {
  return LocalizedTestApp(locale: locale, home: home);
}
