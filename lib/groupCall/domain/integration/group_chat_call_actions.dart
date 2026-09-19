import 'package:flutter/material.dart';

import '../application/group_call_controller.dart';
import '../domain/call_models.dart';
import '../presentation/screens/group_call_screen.dart';

/// Call this from your group chat's audio/video button.
Future<void> startGroupCallFromChat({
  required BuildContext context,
  required GroupCallController controller,
  required int conversationId,
  required bool video,
}) async {
  try {
    await controller.startGroupCall(
      conversationId: conversationId,
      video: video,
    );

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          controller: controller,
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unable to start call: $e'),
      ),
    );
  }
}

/// Call this from OngoingCallBanner.
Future<void> joinOngoingGroupCall({
  required BuildContext context,
  required GroupCallController controller,
  required CallSessionDto call,
}) async {
  try {
    await controller.joinExistingCall(call);

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          controller: controller,
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unable to join call: $e'),
      ),
    );
  }
}
