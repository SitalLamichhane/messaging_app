// lib/core/services/app_haptics.dart
//
// Hiddenly haptic diagnostic build.
// Replace your current AppHaptics file with this one temporarily.
//
// Required dependency:
//   vibration: ^3.2.1
//
// Required AndroidManifest.xml permission:
//   <uses-permission android:name="android.permission.VIBRATE"/>

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class AppHaptics {
  AppHaptics._();

  static bool enabled = true;

  static Future<void> selection() =>
      _pulse('selection', durationMs: 45, amplitude: 180);

  static Future<void> light() =>
      _pulse('light', durationMs: 65, amplitude: 210);

  static Future<void> medium() =>
      _pulse('medium', durationMs: 90, amplitude: 235);

  static Future<void> heavy() =>
      _pulse('heavy', durationMs: 130, amplitude: 255);

  static Future<void> vibrate() =>
      _pulse('vibrate', durationMs: 200, amplitude: 255);

  /// Run this from one temporary button.
  ///
  /// Expected log:
  /// [HAPTIC] TEST START
  /// [HAPTIC] hasVibrator=true ...
  /// [HAPTIC] TEST END
  static Future<void> test() async {
    debugPrint('[HAPTIC] TEST START');

    try {
      final hasVibrator = await Vibration.hasVibrator();
      final amplitude = await Vibration.hasAmplitudeControl();
      final custom = await Vibration.hasCustomVibrationsSupport();

      debugPrint(
        '[HAPTIC] hasVibrator=$hasVibrator '
        'amplitudeControl=$amplitude '
        'customSupport=$custom',
      );

      if (hasVibrator) {
        // Deliberately obvious test pulse.
        debugPrint('[HAPTIC] sending 500ms test vibration at amplitude 255');
        await Vibration.vibrate(
          duration: 500,
          amplitude: amplitude ? 255 : -1,
        );
        debugPrint('[HAPTIC] vibration command completed');
      } else {
        debugPrint('[HAPTIC] device reports NO vibrator');
        await HapticFeedback.heavyImpact();
      }
    } catch (error, stackTrace) {
      debugPrint('[HAPTIC] TEST ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      try {
        await HapticFeedback.vibrate();
        debugPrint('[HAPTIC] Flutter fallback executed');
      } catch (fallbackError) {
        debugPrint('[HAPTIC] FALLBACK ERROR: $fallbackError');
      }
    }

    debugPrint('[HAPTIC] TEST END');
  }

  static Future<void> _pulse(
  String name, {
  required int durationMs,
  required int amplitude,
}) async {
  if (!enabled) return;

  debugPrint('[HAPTIC] $name requested');

  try {
    final hasVibrator = await Vibration.hasVibrator();

    if (!hasVibrator) {
      await _flutterFallback(name);
      return;
    }

    final hasAmplitude = await Vibration.hasAmplitudeControl();

    if (hasAmplitude) {
      await Vibration.vibrate(
        duration: durationMs,
        amplitude: amplitude,
      );
    } else {
      // Samsung/device without amplitude control:
      // make duration strong enough to actually feel.
      final strongDuration = switch (name) {
        'selection' => 80,
        'light' => 110,
        'medium' => 160,
        'heavy' => 240,
        _ => 300,
      };

      await Vibration.vibrate(
        duration: strongDuration,
      );
    }

    debugPrint(
      '[HAPTIC] $name sent '
      'hasVibrator=$hasVibrator '
      'amplitudeControl=$hasAmplitude',
    );
  } catch (e) {
    debugPrint('[HAPTIC] ERROR: $e');
    await _flutterFallback(name);
  }
}

  static Future<void> _flutterFallback(String name) async {
    try {
      switch (name) {
        case 'selection':
          await HapticFeedback.selectionClick();
          break;
        case 'light':
          await HapticFeedback.lightImpact();
          break;
        case 'medium':
          await HapticFeedback.mediumImpact();
          break;
        case 'heavy':
          await HapticFeedback.heavyImpact();
          break;
        default:
          await HapticFeedback.vibrate();
      }

      debugPrint('[HAPTIC] $name Flutter fallback sent');
    } catch (error) {
      debugPrint('[HAPTIC] $name Flutter fallback ERROR: $error');
    }
  }
}
