// core/call/call_sound_service.dart

import 'package:audioplayers/audioplayers.dart';

class CallSoundService {
  static final CallSoundService instance = CallSoundService._internal();
  CallSoundService._internal();

  AudioPlayer? _player;

  Future<AudioPlayer> get _safePlayer async {
    _player ??= AudioPlayer();
    return _player!;
  }

  Future<void> playIncomingRingtone() async {
    final player = await _safePlayer;
    await stop();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('sounds/incoming_call.mp3'));
  }

  Future<void> playOutgoingTone() async {
    final player = await _safePlayer;
    await stop();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('sounds/outgoing_call.mp3'));
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}