// THIS IS AN INTEGRATION EXAMPLE, NOT A SECOND main.dart.
//
// Put the relevant pieces into your existing app startup.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../application/group_call_controller.dart';
import '../infrastructure/call_api_service.dart';
import '../infrastructure/call_push_service.dart';
import 'call_push_router.dart';
import 'group_call_factory.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// Replace this with your existing secure auth/token service.
Future<String?> getAccessToken() async {
  // Example:
  // return await SecureStorage.read(key: 'access_token');
  throw UnimplementedError(
    'Connect this to your existing access-token storage.',
  );
}

late final CallApiService callApi;
late final CallPushRouter callPushRouter;

Future<void> initializeCalls() async {
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  callApi = CallApiService(
    // IMPORTANT:
    // If your start endpoint is https://api.example.com/api/calls/start/
    // use baseUrl: https://api.example.com/api
    baseUrl: 'https://YOUR_API_DOMAIN/api',
    accessTokenGetter: getAccessToken,
    endpoints: const CallEndpoints(
      // Change these only if urls.py differs.
      startCall: '/calls/start/',
      liveKitToken: '/calls/livekit-token/',
    ),
  );

  callPushRouter = CallPushRouter(
    navigatorKey: navigatorKey,
    pushService: CallPushService(),
    controllerFactory: () {
      return createGroupCallController(
        api: callApi,
        wsBaseUrl: 'wss://YOUR_API_DOMAIN',
        tokenGetter: getAccessToken,
      );
    },
  );

  await callPushRouter.initialize();
}

// In MaterialApp:
// navigatorKey: navigatorKey,
//
// Then from group chat page create ONE controller for that page/screen:
//
// late final GroupCallController callController;
//
// callController = createGroupCallController(
//   api: callApi,
//   wsBaseUrl: 'wss://YOUR_API_DOMAIN',
//   tokenGetter: getAccessToken,
// );
//
// Audio button:
// startGroupCallFromChat(
//   context: context,
//   controller: callController,
//   conversationId: widget.conversationId,
//   video: false,
// );
//
// Video button:
// startGroupCallFromChat(
//   context: context,
//   controller: callController,
//   conversationId: widget.conversationId,
//   video: true,
// );
//
// At the top of the group chat UI:
//
// OngoingCallBanner(
//   conversationId: widget.conversationId,
//   api: callApi,
//   onJoin: (call) => joinOngoingGroupCall(
//     context: context,
//     controller: callController,
//     call: call,
//   ),
// );
