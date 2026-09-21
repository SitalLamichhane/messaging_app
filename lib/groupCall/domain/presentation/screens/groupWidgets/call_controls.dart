import 'package:flutter/material.dart';

class CallControls extends StatelessWidget {
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool speakerEnabled;

  final VoidCallback onMicrophone;
  final VoidCallback onCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onSpeaker;
  final VoidCallback onLeave;

  const CallControls({
    super.key,
    required this.microphoneEnabled,
    required this.cameraEnabled,
    required this.speakerEnabled,
    required this.onMicrophone,
    required this.onCamera,
    required this.onSwitchCamera,
    required this.onSpeaker,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          8,
          10,
          8,
          14,
        ),
        color: const Color(0xFF111B21),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceEvenly,
          children: [
            _button(
              icon: microphoneEnabled
                  ? Icons.mic_rounded
                  : Icons.mic_off_rounded,
              onTap: onMicrophone,
            ),
            _button(
              icon: cameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              onTap: onCamera,
            ),
            _button(
              icon:
                  Icons.cameraswitch_rounded,
              onTap: cameraEnabled
                  ? onSwitchCamera
                  : null,
            ),
            _button(
              icon: speakerEnabled
                  ? Icons.volume_up_rounded
                  : Icons.hearing_rounded,
              onTap: onSpeaker,
            ),
            _button(
              icon: Icons.call_end_rounded,
              background: Colors.red,
              onTap: onLeave,
            ),
          ],
        ),
      ),
    );
  }

  Widget _button({
    required IconData icon,
    required VoidCallback? onTap,
    Color? background,
  }) {
    return Material(
      color: background ??
          const Color(0xFF2A3942),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder:
            const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(
            icon,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
