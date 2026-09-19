import '../application/group_call_controller.dart';
import '../infrastructure/call_api_service.dart';
import '../infrastructure/call_socket_service.dart';
import '../infrastructure/livekit_call_service.dart';

/// Creates one controller per active call screen.
///
/// api can be app-scoped.
/// socket + liveKit should be controller-scoped.
GroupCallController createGroupCallController({
  required CallApiService api,
  required String wsBaseUrl,
  required AccessTokenGetter tokenGetter,
}) {
  return GroupCallController(
    api: api,
    socket: CallSocketService(
      wsBaseUrl: wsBaseUrl,
      accessTokenGetter: tokenGetter,
      tokenInQuery: true,
      tokenQueryKey: 'token',
    ),
    liveKit: LiveKitCallService(),
  );
}
