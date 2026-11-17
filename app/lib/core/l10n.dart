import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

/// `context.l10n.someKey` instead of `AppLocalizations.of(context).someKey`.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Delegates for [MaterialApp]. The Material delegate must be the one
/// material_ui uses (not the flutter_localizations copy that
/// `AppLocalizations.localizationsDelegates` lists), or its widgets can't
/// find their localizations.
const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// The app language for the device's locale list: the first language the
/// app has a translation for. English is the source language; Polish is the
/// fallback for every other device language.
Locale resolveAppLocale(Iterable<Locale> device) {
  for (final l in device) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (l.languageCode == supported.languageCode) return supported;
    }
  }
  return const Locale('pl');
}

/// Date/number formatting data for every app language, and the default
/// locale for intl calls that don't pass one explicitly.
Future<void> initAppFormatting(Locale locale) async {
  for (final l in AppLocalizations.supportedLocales) {
    await initializeDateFormatting(l.languageCode);
  }
  Intl.defaultLocale = locale.languageCode;
}
