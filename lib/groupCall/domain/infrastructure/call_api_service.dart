import 'dart:convert';
import 'package:http/http.dart' as http;

import '../domain/call_models.dart';

typedef AccessTokenGetter = Future<String?> Function();

class CallApiException implements Exception {
  final int statusCode;
  final Map<String, dynamic> data;

  const CallApiException(this.statusCode, this.data);

  String get message =>
      (data['error'] ?? data['detail'] ?? 'Request failed').toString();

  @override
  String toString() => 'CallApiException($statusCode): $message';
}

class CallEndpoints {
  /// Change ONLY these path strings if your urls.py uses different paths.
  final String startCall;
  final String liveKitToken;
  final String Function(Object callId) updateStatus;
  final String Function(int conversationId) activeGroupCall;

  const CallEndpoints({
    this.startCall = '/calls/start/',
    this.liveKitToken = '/calls/livekit-token/',
    this.updateStatus = _defaultUpdateStatus,
    this.activeGroupCall = _defaultActiveGroupCall,
  });

  static String _defaultUpdateStatus(Object callId) =>
      '/calls/$callId/status/';

  static String _defaultActiveGroupCall(int conversationId) =>
      '/conversations/$conversationId/active-call/';
}

class CallApiService {
  final String baseUrl;
  final AccessTokenGetter accessTokenGetter;
  final http.Client _client;
  final CallEndpoints endpoints;

  CallApiService({
    required this.baseUrl,
    required this.accessTokenGetter,
    http.Client? client,
    this.endpoints = const CallEndpoints(),
  }) : _client = client ?? http.Client();

  Uri _uri(String path) {
    final root =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final clean = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$root$clean');
  }

  Future<Map<String, String>> _headers() async {
    final token = await accessTokenGetter();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };
  }

  Future<CallSessionDto> startGroupCall({
    required int conversationId,
    required bool isVideo,
  }) async {
    final response = await _client.post(
      _uri(endpoints.startCall),
      headers: await _headers(),
      body: jsonEncode({
        'conversation_id': conversationId,
        'is_video_call': isVideo,
      }),
    );

    final data = _decode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CallApiException(response.statusCode, data);
    }

    return CallSessionDto.fromJson({
      ...data,
      'conversation_type':
          data['conversation_type'] ?? 'group',
      'conversation_id':
          data['conversation_id'] ?? conversationId,
    });
  }

  Future<LiveKitCredentials> getLiveKitToken(
    Object callId,
  ) async {
    final response = await _client.post(
      _uri(endpoints.liveKitToken),
      headers: await _headers(),
      body: jsonEncode({
        'call_id': callId,
      }),
    );

    final data = _decode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CallApiException(response.statusCode, data);
    }

    return LiveKitCredentials.fromJson(data);
  }

  Future<Map<String, dynamic>> updateStatus({
    required Object callId,
    required String action,
  }) async {
    final response = await _client.post(
      _uri(endpoints.updateStatus(callId)),
      headers: await _headers(),
      body: jsonEncode({
        'action': action,
      }),
    );

    final data = _decode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CallApiException(response.statusCode, data);
    }

    return data;
  }

  Future<ActiveCallResult> getActiveGroupCall(
    int conversationId,
  ) async {
    final response = await _client.get(
      _uri(endpoints.activeGroupCall(conversationId)),
      headers: await _headers(),
    );

    final data = _decode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CallApiException(response.statusCode, data);
    }

    return ActiveCallResult.fromJson(data);
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return <String, dynamic>{
      'data': decoded,
    };
  }

  void dispose() {
    _client.close();
  }
}
