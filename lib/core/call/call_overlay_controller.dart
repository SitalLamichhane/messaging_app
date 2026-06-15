// lib/core/call/call_overlay_controller.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/*
  Messenger-style call UI flags only.

  WebRTC/socket stays inside callProvider + SocketService.
  Do not start/stop WebRTC from this file.

  Final flow:
  - CallScreen visible: callScreenVisible = true
  - Back from CallScreen: in-app mini overlay
  - Tap mini overlay: restore SAME CallScreen, no new push
  - Home/PiP: call-only PiP surface
  - App resume from PiP: in-app mini overlay first
  - Call end/reject/timeout: clear all flags
*/

final callScreenMinimizedProvider = StateProvider<bool>((ref) => false);
final forceCallPipSurfaceProvider = StateProvider<bool>((ref) => false);
final openCallScreenFromPipProvider = StateProvider<bool>((ref) => false);
final callScreenVisibleProvider = StateProvider<bool>((ref) => false);

final openingCallScreenProvider = StateProvider<bool>((ref) => false);
final enteringPipProvider = StateProvider<bool>((ref) => false);
final appWasInPhonePipProvider = StateProvider<bool>((ref) => false);

void markCallScreenVisible(WidgetRef ref) {
  ref.read(callScreenVisibleProvider.notifier).state = true;
  ref.read(callScreenMinimizedProvider.notifier).state = false;
  ref.read(forceCallPipSurfaceProvider.notifier).state = false;
  ref.read(openCallScreenFromPipProvider.notifier).state = false;
  ref.read(openingCallScreenProvider.notifier).state = false;
  ref.read(enteringPipProvider.notifier).state = false;
  ref.read(appWasInPhonePipProvider.notifier).state = false;
}

void minimizeCallInsideApp(WidgetRef ref) {
  ref.read(callScreenVisibleProvider.notifier).state = false;
  ref.read(callScreenMinimizedProvider.notifier).state = true;
  ref.read(forceCallPipSurfaceProvider.notifier).state = false;
  ref.read(openCallScreenFromPipProvider.notifier).state = false;
  ref.read(openingCallScreenProvider.notifier).state = false;
  ref.read(enteringPipProvider.notifier).state = false;
  ref.read(appWasInPhonePipProvider.notifier).state = false;
}

void restoreFromMiniOverlay(WidgetRef ref) {
  // Same existing CallScreen restore.
  // Do NOT push a new CallScreen from mini overlay.
  ref.read(callScreenVisibleProvider.notifier).state = true;
  ref.read(callScreenMinimizedProvider.notifier).state = false;
  ref.read(forceCallPipSurfaceProvider.notifier).state = false;
  ref.read(openCallScreenFromPipProvider.notifier).state = false;
  ref.read(openingCallScreenProvider.notifier).state = false;
  ref.read(enteringPipProvider.notifier).state = false;
  ref.read(appWasInPhonePipProvider.notifier).state = false;
}

void preparePhoneHomePip(WidgetRef ref) {
  ref.read(callScreenVisibleProvider.notifier).state = false;
  ref.read(callScreenMinimizedProvider.notifier).state = false;
  ref.read(forceCallPipSurfaceProvider.notifier).state = true;
  ref.read(openCallScreenFromPipProvider.notifier).state = true;
  ref.read(openingCallScreenProvider.notifier).state = false;
  ref.read(enteringPipProvider.notifier).state = true;
  ref.read(appWasInPhonePipProvider.notifier).state = true;
}

void restoreInAppOverlayFromPip(WidgetRef ref) {
  ref.read(callScreenVisibleProvider.notifier).state = false;
  ref.read(callScreenMinimizedProvider.notifier).state = true;
  ref.read(forceCallPipSurfaceProvider.notifier).state = false;
  ref.read(openCallScreenFromPipProvider.notifier).state = false;
  ref.read(openingCallScreenProvider.notifier).state = false;
  ref.read(enteringPipProvider.notifier).state = false;
  ref.read(appWasInPhonePipProvider.notifier).state = false;
}

bool lockCallScreenOpening(WidgetRef ref) {
  if (ref.read(openingCallScreenProvider)) {
    return false;
  }

  ref.read(openingCallScreenProvider.notifier).state = true;
  return true;
}

void unlockCallScreenOpening(WidgetRef ref) {
  ref.read(openingCallScreenProvider.notifier).state = false;
}

void clearCallOverlayFlags(WidgetRef ref) {
  ref.read(callScreenVisibleProvider.notifier).state = false;
  ref.read(callScreenMinimizedProvider.notifier).state = false;
  ref.read(forceCallPipSurfaceProvider.notifier).state = false;
  ref.read(openCallScreenFromPipProvider.notifier).state = false;
  ref.read(openingCallScreenProvider.notifier).state = false;
  ref.read(enteringPipProvider.notifier).state = false;
  ref.read(appWasInPhonePipProvider.notifier).state = false;
}