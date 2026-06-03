
// import 'package:flutter_callkit_incoming/entities/call_event.dart';
// import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
// import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
// import 'package:flutter_callkit_incoming/entities/android_params.dart';
// import 'package:flutter_callkit_incoming/entities/ios_params.dart';
// import 'package:uuid/uuid.dart';

// class CallNotificationService {
//   static final CallNotificationService instance =
//       CallNotificationService._internal();

//   CallNotificationService._internal();

//   String? _currentCallId;

//   Future<void> showIncomingCall({
//     required String callerName,
//     required String callerId,
//     required String conversationId,
//     required bool isVideoCall,
//     String callerAvatar = '',
//   }) async {
//     final callId = const Uuid().v4();
//     _currentCallId = callId;

//     final params = CallKitParams(
//       id: callId,
//       nameCaller: callerName,
//       appName: 'messaging_app',
//       avatar: callerAvatar,
//       handle: callerId,
//       type: isVideoCall ? 1 : 0,
//       textAccept: 'Accept',
//       textDecline: 'Decline',
//       duration: 30000,
//       extra: {
//         'caller_id': callerId,
//         'conversation_id': conversationId,
//         'caller_name': callerName,
//         'caller_avatar': callerAvatar,
//         'is_video_call': isVideoCall,
//       },
//       android: const AndroidParams(
//         isCustomNotification: true,
//         isShowLogo: false,
//         ringtonePath: 'system_ringtone_default',
//         backgroundColor: '#0955fa',
//         actionColor: '#4CAF50',
//         incomingCallNotificationChannelName: 'Incoming Calls',
//         missedCallNotificationChannelName: 'Missed Calls',
//       ),
//       ios: const IOSParams(
//         iconName: 'CallKitLogo',
//         handleType: 'generic',
//         supportsVideo: true,
//       ),
//     );

//     await FlutterCallkitIncoming.showCallkitIncoming(params);
//   }

//   Future<void> endCurrentCall() async {
//     final callId = _currentCallId;
//     if (callId == null) return;

//     await FlutterCallkitIncoming.endCall(callId);
//     _currentCallId = null;
//   }

//   Future<void> endAllCalls() async {
//     await FlutterCallkitIncoming.endAllCalls();
//     _currentCallId = null;
//   }

//   void listenCallActions({
//     required Future<void> Function(Map<String, dynamic> extra) onAccept,
//     required Future<void> Function(Map<String, dynamic> extra) onDecline,
//   }) {
//     FlutterCallkitIncoming.onEvent.listen((event) async {
//       if (event == null) return;

//       final eventName = event.event;
//       final body = event.body;

//       final extraRaw = body['extra'];
//       final extra = extraRaw is Map
//           ? Map<String, dynamic>.from(extraRaw)
//           : <String, dynamic>{};

//       if (eventName == Event.actionCallAccept) {
//         await onAccept(extra);
//       }

//       if (eventName == Event.actionCallDecline ||
//           eventName == Event.actionCallEnded ||
//           eventName == Event.actionCallTimeout) {
//         await onDecline(extra);
//       }
//     });
//   }
// }