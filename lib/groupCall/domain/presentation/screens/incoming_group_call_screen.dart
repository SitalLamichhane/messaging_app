
import 'package:flutter/material.dart';

import 'package:hiddenly/groupCall/domain/call_models.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/group_call_screen.dart';

import '../../application/group_call_controller.dart';

class IncomingGroupCallScreen extends StatefulWidget {
  final IncomingCallPayload payload;
  final GroupCallController controller;

  const IncomingGroupCallScreen({
    super.key,
    required this.payload,
    required this.controller,
  });

  @override
  State<IncomingGroupCallScreen> createState() =>
      _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState
    extends State<IncomingGroupCallScreen> {
  bool _handling = false;
  bool _finished = false;

  String? _error;

  // ---------------------------------------------------------------------------
  // FIND ACTIVE GROUP CALL
  // ---------------------------------------------------------------------------

  Future<CallSessionDto?> _findActiveCall() async {
    final active = await widget.controller.checkActiveCall(
      widget.payload.conversationId,
    );

    if (active == null) {
      return null;
    }

    // Ignore stale FCM / websocket notification.
    //
    // Example:
    // Push says call 115 but the currently active call is 116.
    // In that case we must not accidentally join 116 from an old notification.
    if (widget.payload.callId > 0 &&
        active.callId > 0 &&
        active.callId != widget.payload.callId) {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'stale push ignored. '
        'push=${widget.payload.callId} '
        'active=${active.callId}',
      );

      return null;
    }

    return active;
  }

  // ---------------------------------------------------------------------------
  // ACCEPT
  // ---------------------------------------------------------------------------

  Future<void> _accept() async {
    if (_handling || _finished) {
      return;
    }

    setState(() {
      _handling = true;
      _error = null;
    });

    try {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'accept pressed. '
        'conversation=${widget.payload.conversationId} '
        'call=${widget.payload.callId}',
      );

      // -----------------------------------------------------------------------
      // 1. Verify that the group call is still active.
      // -----------------------------------------------------------------------

      final call = await _findActiveCall();

      if (!mounted) {
        return;
      }

      if (call == null || !call.isActive) {
        debugPrint(
          '[INCOMING GROUP CALL] '
          'accept failed: active call not found.',
        );

        setState(() {
          _handling = false;
          _error = 'This group call is no longer active.';
        });

        return;
      }

      debugPrint(
        '[INCOMING GROUP CALL] '
        'active call found. '
        'call=${call.callId}',
      );

      // -----------------------------------------------------------------------
      // 2. Join the existing group call through GroupCallController.
      //
      // This will:
      //   - request LiveKit credentials
      //   - connect to LiveKit
      //   - enable microphone
      //   - enable camera when required
      //   - update controller state
      //
      // DO NOT use the private CallProvider/WebRTC signaling flow here.
      // -----------------------------------------------------------------------

      await widget.controller.joinExistingCall(call);

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // 3. Make sure LiveKit actually connected.
      // -----------------------------------------------------------------------

      if (!widget.controller.connected) {
        debugPrint(
          '[INCOMING GROUP CALL] '
          'LiveKit join returned but controller is not connected. '
          'error=${widget.controller.error}',
        );

        setState(() {
          _handling = false;
          _error =
              widget.controller.error ??
              'Unable to join group call.';
        });

        return;
      }

      debugPrint(
        '[INCOMING GROUP CALL] '
        'LiveKit connected successfully. '
        'Opening GroupCallScreen.',
      );

      _finished = true;

      // -----------------------------------------------------------------------
      // IMPORTANT LIFECYCLE FIX
      // -----------------------------------------------------------------------
      //
      // DO NOT USE:
      //
      // Navigator.pushReplacement(...)
      //
      // GlobalCallHandler owns:
      //
      //   GroupCallController
      //   ConversationRealtimeService
      //
      // GlobalCallHandler is awaiting the IncomingGroupCallScreen route.
      //
      // If we use pushReplacement(), this IncomingGroupCallScreen route is
      // removed immediately. That makes GlobalCallHandler's await complete,
      // causing its finally block to run:
      //
      //   controller.dispose();
      //   realtime.dispose();
      //
      // GroupCallScreen would then receive an already-disposed controller.
      //
      // Instead:
      //
      // IncomingGroupCallScreen
      //          |
      //          +---- push GroupCallScreen
      //                       |
      //                       | call remains active
      //                       |
      //                       +---- GroupCallScreen closes
      //          |
      //          +---- pop IncomingGroupCallScreen
      //
      // Only after that will GlobalCallHandler dispose the resources.
      // -----------------------------------------------------------------------

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => GroupCallScreen(
            controller: widget.controller,
          ),
        ),
      );

      // -----------------------------------------------------------------------
      // 4. GroupCallScreen has ACTUALLY closed.
      // -----------------------------------------------------------------------

      debugPrint(
        '[INCOMING GROUP CALL] '
        'GroupCallScreen closed.',
      );

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // 5. Close the hidden IncomingGroupCallScreen.
      //
      // This allows GlobalCallHandler's navigator.push() to finish.
      // Its finally block can now safely dispose controller + realtime.
      // -----------------------------------------------------------------------

      debugPrint(
        '[INCOMING GROUP CALL] '
        'closing incoming group call route.',
      );

      Navigator.of(context).pop();
    } catch (e, stackTrace) {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'accept error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _handling = false;
        _finished = false;

        _error =
            widget.controller.error ??
            'Unable to join group call.';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // DECLINE
  // ---------------------------------------------------------------------------

  Future<void> _decline() async {
    if (_handling || _finished) {
      return;
    }

    setState(() {
      _handling = true;
      _error = null;
    });

    try {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'decline pressed. '
        'conversation=${widget.payload.conversationId} '
        'call=${widget.payload.callId}',
      );

      final call = await _findActiveCall();

      if (call != null && call.isActive) {
        debugPrint(
          '[INCOMING GROUP CALL] '
          'declining active call=${call.callId}',
        );

        await widget.controller.declineIncoming(call);
      }

      if (!mounted) {
        return;
      }

      _finished = true;

      debugPrint(
        '[INCOMING GROUP CALL] '
        'decline complete. Closing screen.',
      );

      Navigator.of(context).pop();
    } catch (e, stackTrace) {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'decline error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _handling = false;

        _error =
            widget.controller.error ??
            'Unable to decline call.';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;

    final groupName = payload.conversationName.trim();
    final callerName = payload.callerName.trim();

    return PopScope(
      // Prevent back navigation while accept/decline is being processed.
      canPop: !_handling,

      child: Scaffold(
        backgroundColor: Colors.black,

        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),

            child: Column(
              children: [
                const Spacer(),

                // ----------------------------------------------------------------
                // GROUP ICON
                // ----------------------------------------------------------------

                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),

                const SizedBox(
                  height: 28,
                ),

                // ----------------------------------------------------------------
                // GROUP NAME
                // ----------------------------------------------------------------

                Text(
                  groupName.isNotEmpty
                      ? groupName
                      : 'Group call',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 10,
                ),

                // ----------------------------------------------------------------
                // CALL TYPE
                // ----------------------------------------------------------------

                Text(
                  payload.isVideo
                      ? 'Incoming group video call'
                      : 'Incoming group audio call',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),

                // ----------------------------------------------------------------
                // CALLER NAME
                // ----------------------------------------------------------------

                if (callerName.isNotEmpty) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'From $callerName',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                ],

                // ----------------------------------------------------------------
                // ERROR
                // ----------------------------------------------------------------

                if (_error != null) ...[
                  const SizedBox(
                    height: 20,
                  ),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                    ),
                  ),
                ],

                const Spacer(),

                // ----------------------------------------------------------------
                // LOADING / CALL BUTTONS
                // ----------------------------------------------------------------

                if (_handling)
                  const Padding(
                    padding: EdgeInsets.only(
                      bottom: 30,
                    ),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceEvenly,
                    children: [
                      // ----------------------------------------------------------
                      // DECLINE
                      // ----------------------------------------------------------

                      _CallButton(
                        icon: Icons.call_end,
                        label: 'Decline',
                        backgroundColor: Colors.red,
                        onPressed: _decline,
                      ),

                      // ----------------------------------------------------------
                      // ACCEPT
                      // ----------------------------------------------------------

                      _CallButton(
                        icon: payload.isVideo
                            ? Icons.videocam
                            : Icons.call,
                        label: 'Accept',
                        backgroundColor: Colors.green,
                        onPressed: _accept,
                      ),
                    ],
                  ),

                const SizedBox(
                  height: 40,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CALL BUTTON
// =============================================================================

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback? onPressed;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),

        const SizedBox(
          height: 10,
        ),

        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
