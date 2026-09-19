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
          12,
          10,
          12,
          14,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF111B21),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceEvenly,
          children: [
            _ControlButton(
              icon: microphoneEnabled
                  ? Icons.mic
                  : Icons.mic_off,
              label: microphoneEnabled ? 'Mute' : 'Unmute',
              onTap: onMicrophone,
            ),
            _ControlButton(
              icon: cameraEnabled
                  ? Icons.videocam
                  : Icons.videocam_off,
              label: cameraEnabled ? 'Camera' : 'Camera',
              onTap: onCamera,
            ),
            _ControlButton(
              icon: Icons.cameraswitch,
              label: 'Flip',
              onTap: cameraEnabled
                  ? onSwitchCamera
                  : null,
            ),
            _ControlButton(
              icon: speakerEnabled
                  ? Icons.volume_up
                  : Icons.hearing,
              label: 'Audio',
              onTap: onSpeaker,
            ),
            _ControlButton(
              icon: Icons.call_end,
              label: 'Leave',
              background: Colors.red,
              onTap: onLeave,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? background;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: background ??
                const Color(0xFF2A3942),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Icon(
                  icon,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
