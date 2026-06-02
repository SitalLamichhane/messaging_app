// core/call/call_sound_service.dart

import 'package:audioplayers/audioplayers.dart';

class CallSoundService {
  static final CallSoundService instance = CallSoundService._internal();
  CallSoundService._internal();

  final AudioPlayer _player = AudioPlayer();

  Future<void> playIncomingRingtone() async {
    await stop();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('sounds/incoming_call.mp3'));
  }

  Future<void> playOutgoingTone() async {
    await stop();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('sounds/outgoing_call.mp3'));
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}