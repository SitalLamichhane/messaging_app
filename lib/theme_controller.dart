import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> appThemeMode =
    ValueNotifier(ThemeMode.light);

bool get isAppDarkMode => appThemeMode.value == ThemeMode.dark;

void setAppDarkMode(bool value) {
  appThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
}