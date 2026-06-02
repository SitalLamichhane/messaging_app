// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide ChangeNotifierProvider;
import 'package:messaging_app/core/call/global_call_handler.dart';
import 'package:provider/provider.dart';

import 'package:messaging_app/auth_gate.dart';
import 'package:messaging_app/features/auth/auth_provider.dart';
import 'package:messaging_app/theme_controller.dart';
import 'package:messaging_app/core/chat/chat_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider()..checkLogin(),
          ),
          ChangeNotifierProvider(
            create: (_) => ChatProvider(),
          ),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class AppText {
  static const TextTheme lightTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: Color(0xFF0E1730),
      height: 1.15,
    ),
    displayMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    headlineLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    headlineMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E1730),
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Color(0xFF0E1730),
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Color(0xFF0E1730),
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Color(0xFF64748B),
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFF64748B),
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    labelMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xFF4F7CF3),
    ),
  );

  static const TextTheme darkTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1.15,
    ),
    displayMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    headlineLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    headlineMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Color(0xFFCBD5E1),
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFF94A3B8),
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    labelMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xFF93C5FD),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          navigatorKey: GlobalCallHandler.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'SocialConnect',
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Arial',
            scaffoldBackgroundColor: const Color(0xFFF6F8FC),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4F7CF3),
              brightness: Brightness.light,
            ),
            textTheme: AppText.lightTextTheme,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            dividerColor: const Color(0xFFE5EAF2),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Arial',
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4F7CF3),
              brightness: Brightness.dark,
            ),
            textTheme: AppText.darkTextTheme,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            dividerColor: const Color(0xFF243041),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              elevation: 0,
              centerTitle: false,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}