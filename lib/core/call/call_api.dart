// lib/core/call/call_api.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddenly/core/api_client.dart';

/// Result returned when Flutter asks Django to create a call.
///
/// Django is the source of truth for:
/// - call id
/// - call uuid
/// - call status
///
/// Flutter must never create/fake its own backend call id.
class CallStartResult {
  final bool created;
  final bool conflict;

  final String? callId;
  final String? callUuid;
  final String? status;
  final String? error;

  final Map<String, dynamic> data;

  const CallStartResult({
    required this.created,
    required this.conflict,
    required this.data,
    this.callId,
    this.callUuid,
    this.status,
    this.error,
  });

  /// True only when Django successfully created a new call.
  bool get canStart {
    return created && (callId?.trim().isNotEmpty ?? false);
  }

  /// True when Django says another call already exists.
  bool get hasExistingCall {
    return conflict && (callId?.trim().isNotEmpty ?? false);
  }

  bool get isRinging {
    return status?.toLowerCase() == 'ringing';
  }

  bool get isAccepted {
    return status?.toLowerCase() == 'accepted';
  }

  bool get isOngoing {
    final value = status?.toLowerCase();

    return value == 'ongoing' ||
        value == 'active' ||
        value == 'connected';
  }

  bool get isFinished {
    final value = status?.toLowerCase();

    return value == 'ended' ||
        value == 'cancelled' ||
        value == 'canceled' ||
        value == 'rejected' ||
        value == 'missed' ||
        value == 'failed';
  }

  @override
  String toString() {
    return '''
CallStartResult(
  created: $created,
  conflict: $conflict,
  callId: $callId,
  callUuid: $callUuid,
  status: $status,
  error: $error
)
''';
  }
}

class CallApi {
  // ============================================================
  // PRIVATE RAW CALL CREATION
  // ============================================================

  /// Raw request used internally.
  ///
  /// Do NOT call this directly from UI/provider.
  /// UI/provider should always use [createCall].
  static Future<Response<dynamic>> _startCall({
    required String receiverId,
    required String conversationId,
    required bool isVideoCall,
  }) async {
    final cleanReceiverId = receiverId.trim();
    final cleanConversationId = conversationId.trim();

    if (cleanReceiverId.isEmpty) {
      throw ArgumentError.value(
        receiverId,
        'receiverId',
        'Receiver id cannot be empty',
      );
    }

    if (cleanConversationId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'Conversation id cannot be empty',
      );
    }

    debugPrint('');
    debugPrint('==========================================');
    debugPrint('CALL API: STARTING CALL');
    debugPrint('receiverId: $cleanReceiverId');
    debugPrint('conversationId: $cleanConversationId');
    debugPrint('isVideoCall: $isVideoCall');
    debugPrint('==========================================');

    return ApiClient.dio.post<dynamic>(
      '/chat/calls/start/',
      data: <String, dynamic>{
        'receiver_id': cleanReceiverId,
        'conversation_id': cleanConversationId,
        'is_video_call': isVideoCall,
      },
    );
  }

  // ============================================================
  // CREATE CALL
  // ============================================================

  /// Main method that should be used by CallNotifier / CallScreen.
  ///
  /// Handles:
  ///
  /// 200/201:
  /// New call successfully created.
  ///
  /// 409:
  /// Another call already exists.
  ///
  /// Other errors:
  /// Re-thrown to caller.
  static Future<CallStartResult> createCall({
    required String receiverId,
    required String conversationId,
    required bool isVideoCall,
  }) async {
    try {
      final response = await _startCall(
        receiverId: receiverId,
        conversationId: conversationId,
        isVideoCall: isVideoCall,
      );

      final data = _asMap(response.data);

      final callId = _nullableString(
        data['call_id'] ?? data['id'],
      );

      final callUuid = _nullableString(
        data['call_uuid'],
      );

      final status = _nullableString(
        data['status'],
      );

      final error = _nullableString(
        data['error'],
      );

      final created = callId != null;

      debugPrint('');
      debugPrint('==========================================');
      debugPrint('CALL API: CREATE SUCCESS');
      debugPrint('HTTP: ${response.statusCode}');
      debugPrint('callId: $callId');
      debugPrint('callUuid: $callUuid');
      debugPrint('status: $status');
      debugPrint('created: $created');
      debugPrint('==========================================');

      return CallStartResult(
        created: created,
        conflict: false,
        callId: callId,
        callUuid: callUuid,
        status: status,
        error: error,
        data: data,
      );
    }

    // ============================================================
    // DIO ERROR
    // ============================================================

    on DioException catch (e) {
      final response = e.response;

      final statusCode = response?.statusCode;

      final data = _asMap(
        response?.data,
      );

      // ============================================================
      // 409 CONFLICT
      // ============================================================

      if (statusCode == 409) {
        final existingCallId = _nullableString(
          data['call_id'] ?? data['id'],
        );

        final existingCallUuid = _nullableString(
          data['call_uuid'],
        );

        final existingStatus = _nullableString(
          data['status'],
        );

        final serverError =
            _nullableString(data['error']) ??
            'A call is already active';

        debugPrint('');
        debugPrint('##########################################');
        debugPrint('CALL API: 409 CONFLICT');
        debugPrint('Existing callId: $existingCallId');
        debugPrint('Existing callUuid: $existingCallUuid');
        debugPrint('Existing status: $existingStatus');
        debugPrint('Server error: $serverError');
        debugPrint('##########################################');

        return CallStartResult(
          created: false,
          conflict: true,
          callId: existingCallId,
          callUuid: existingCallUuid,
          status: existingStatus,
          error: serverError,
          data: data,
        );
      }

      // ============================================================
      // OTHER HTTP ERRORS
      // ============================================================

      debugPrint('');
      debugPrint('##########################################');
      debugPrint('CALL API ERROR');
      debugPrint('HTTP status: $statusCode');
      debugPrint('message: ${e.message}');
      debugPrint('response: ${response?.data}');
      debugPrint('##########################################');

      rethrow;
    }
  }

  // ============================================================
  // CALL LIFECYCLE
  // ============================================================

  /// Backend supported actions:
  ///
  /// accept
  /// reject
  /// ended
  /// leave
  /// missed
  /// cancel
  static Future<Response<dynamic>> updateCallAction({
    required String callId,
    required String action,
  }) async {
    final cleanCallId = callId.trim();
    final cleanAction = action.trim().toLowerCase();

    if (cleanCallId.isEmpty) {
      throw ArgumentError.value(
        callId,
        'callId',
        'Call id cannot be empty',
      );
    }

    const allowedActions = <String>{
      'accept',
      'reject',
      'ended',
      'leave',
      'missed',
      'cancel',
    };

    if (!allowedActions.contains(cleanAction)) {
      throw ArgumentError.value(
        action,
        'action',
        'Unsupported call lifecycle action',
      );
    }

    debugPrint('');
    debugPrint('==========================================');
    debugPrint('CALL API: UPDATE ACTION');
    debugPrint('callId: $cleanCallId');
    debugPrint('action: $cleanAction');
    debugPrint('==========================================');

    try {
      final response = await ApiClient.dio.post<dynamic>(
        '/chat/calls/$cleanCallId/status/',
        data: <String, dynamic>{
          'action': cleanAction,
        },
      );

      debugPrint(
        'CALL API ACTION SUCCESS: '
        'call=$cleanCallId action=$cleanAction',
      );

      return response;
    } on DioException catch (e) {
      debugPrint('');
      debugPrint('##########################################');
      debugPrint('CALL API ACTION ERROR');
      debugPrint('callId: $cleanCallId');
      debugPrint('action: $cleanAction');
      debugPrint('status: ${e.response?.statusCode}');
      debugPrint('data: ${e.response?.data}');
      debugPrint('##########################################');

      rethrow;
    }
  }

  // ============================================================
  // COMPATIBILITY WRAPPER
  // ============================================================

  static Future<Response<dynamic>> updateCallStatus({
    required String callId,
    String? status,
    String? action,
  }) {
    final resolvedAction = (
      action ??
      status ??
      ''
    ).trim().toLowerCase();

    return updateCallAction(
      callId: callId,
      action: resolvedAction,
    );
  }

  // ============================================================
  // ACCEPT
  // ============================================================

  static Future<Response<dynamic>> accept(
    String callId,
  ) {
    return updateCallAction(
      callId: callId,
      action: 'accept',
    );
  }

  // ============================================================
  // REJECT
  // ============================================================

  static Future<Response<dynamic>> reject(
    String callId,
  ) {
    return updateCallAction(
      callId: callId,
      action: 'reject',
    );
  }

  // ============================================================
  // CANCEL
  // ============================================================

  static Future<Response<dynamic>> cancel(
    String callId,
  ) {
    return updateCallAction(
      callId: callId,
      action: 'cancel',
    );
  }

  // ============================================================
  // END
  // ============================================================

  static Future<Response<dynamic>> end(
    String callId,
  ) {
    return updateCallAction(
      callId: callId,
      action: 'ended',
    );
  }

  // ============================================================
  // LEAVE
  // ============================================================

  static Future<Response<dynamic>> leave(
    String callId,
  ) {
    return updateCallAction(
      callId: callId,
      action: 'leave',
    );
  }

  // ============================================================
  // MISSED
  // ============================================================

  static Future<Response<dynamic>> missed(
    String callId,
  ) {
    return updateCallAction(
      callId: callId,
      action: 'missed',
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static Map<String, dynamic> _asMap(
    dynamic value,
  ) {
    if (value == null) {
      return <String, dynamic>{};
    }

    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(
          key.toString(),
          value,
        ),
      );
    }

    return <String, dynamic>{};
  }

  static String _string(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  static String? _nullableString(
    dynamic value,
  ) {
    final cleanValue = _string(value);

    if (cleanValue.isEmpty) {
      return null;
    }

    if (cleanValue.toLowerCase() == 'null') {
      return null;
    }

    return cleanValue;
  }
}