// lib/core/call/call_api.dart

import 'package:dio/dio.dart';
import 'package:hiddenly/core/api_client.dart';
// ready to lUNCH HIDDENLY
class CallApi {
  static Future<Response> startCall({
    required String receiverId,
    required String conversationId,
    required bool isVideoCall,
  }) {
    return ApiClient.dio.post(
      '/chat/calls/start/',
      data: {
        'receiver_id': receiverId,
        'conversation_id': conversationId,
        'is_video_call': isVideoCall,
      },
    );
  }

  static Future<Response> updateCallStatus({
    required String callId,
    required String status,
  }) {
    return ApiClient.dio.post(
      '/chat/calls/$callId/status/',
      data: {
        // Backend now accepts both action/status if you used my fixed view.
        // Keeping both makes it safe.
        'action': status,
        'status': status,
      },
    );
  }
}