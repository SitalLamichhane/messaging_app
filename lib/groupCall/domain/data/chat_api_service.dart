import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/groupChat/domain/chat_message_model.dart';
import 'package:image_picker/image_picker.dart';

class ChatApiException implements Exception {
  final int? statusCode;
  final String message;
  final dynamic data;

  const ChatApiException({
    required this.statusCode,
    required this.message,
    this.data,
  });

  factory ChatApiException.fromDio(DioException error) {
    final data = error.response?.data;

    String message = 'Request failed';

    if (data is Map) {
      final candidate =
          data['detail'] ??
          data['error'] ??
          data['message'] ??
          data['non_field_errors'];

      if (candidate is List && candidate.isNotEmpty) {
        message = candidate.first.toString();
      } else if (candidate != null) {
        message = candidate.toString();
      }
    } else if (data is String && data.trim().isNotEmpty) {
      message = data.trim();
    } else if (error.message != null &&
        error.message!.trim().isNotEmpty) {
      message = error.message!.trim();
    }

    return ChatApiException(
      statusCode: error.response?.statusCode,
      message: message,
      data: data,
    );
  }

  @override
  String toString() => message;
}

class ChatApiService {
  final Dio dio;

  ChatApiService({
    Dio? dio,
  }) : dio = dio ?? ApiClient.dio;

  // ============================================================
  // LOAD MESSAGES
  // ============================================================

  Future<List<ChatMessageDto>> loadMessages(
    int conversationId,
  ) async {
    try {
      final response = await dio.get(
        '/chat/conversations/$conversationId/messages/',
      );

      final data = response.data;

      List<dynamic> list = <dynamic>[];

      if (data is List) {
        list = data;
      } else if (data is Map) {
        if (data['results'] is List) {
          list = data['results'] as List;
        } else if (data['messages'] is List) {
          list = data['messages'] as List;
        }
      }

      return list
          .whereType<Map>()
          .map(
            (item) => ChatMessageDto.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((message) => message.id > 0)
          .toList();
    } on DioException catch (error) {
      throw ChatApiException.fromDio(error);
    }
  }

  // ============================================================
  // SEND TEXT
  // ============================================================

  Future<ChatMessageDto> sendText({
    required int conversationId,
    required String text,
    int? replyToId,
  }) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      throw const ChatApiException(
        statusCode: null,
        message: 'Message cannot be empty',
      );
    }

    try {
      final response = await dio.post(
        '/chat/conversations/$conversationId/send/',
        data: {
          'text': cleanText,
          'message_type': 'text',
          if (replyToId != null)
            'reply_to': replyToId,
        },
      );

      return _parseMessage(response.data);
    } on DioException catch (error) {
      throw ChatApiException.fromDio(error);
    }
  }

  // ============================================================
  // SEND MEDIA
  // ============================================================

  Future<ChatMessageDto> sendMedia({
    required int conversationId,
    required List<XFile> files,
    required String messageType,
    String text = '',
    int? replyToId,
    ProgressCallback? onSendProgress,
  }) async {
    if (files.isEmpty) {
      throw const ChatApiException(
        statusCode: null,
        message: 'No files selected',
      );
    }

    try {
      final form = FormData();

      form.fields.add(
        MapEntry(
          'text',
          text.trim(),
        ),
      );

      form.fields.add(
        MapEntry(
          'message_type',
          messageType.trim(),
        ),
      );

      if (replyToId != null) {
        form.fields.add(
          MapEntry(
            'reply_to',
            replyToId.toString(),
          ),
        );
      }

      for (final file in files) {
        form.files.add(
          MapEntry(
            'media',
            await MultipartFile.fromFile(
              file.path,
              filename: file.name.isNotEmpty
                  ? file.name
                  : file.path.split('/').last,
            ),
          ),
        );
      }

      final response = await dio.post(
        '/chat/conversations/$conversationId/send/',
        data: form,
        onSendProgress: onSendProgress,
      );

      return _parseMessage(response.data);
    } on DioException catch (error) {
      throw ChatApiException.fromDio(error);
    }
  }

  // ============================================================
  // IMAGES
  // ============================================================

  Future<ChatMessageDto> sendImages({
    required int conversationId,
    required List<XFile> files,
    String text = '',
    int? replyToId,
  }) {
    return sendMedia(
      conversationId: conversationId,
      files: files,
      messageType: 'image',
      text: text,
      replyToId: replyToId,
    );
  }

  // ============================================================
  // FILES
  // ============================================================

  Future<ChatMessageDto> sendFiles({
    required int conversationId,
    required List<XFile> files,
    String text = '',
    int? replyToId,
  }) {
    return sendMedia(
      conversationId: conversationId,
      files: files,
      messageType: 'file',
      text: text,
      replyToId: replyToId,
    );
  }

  // ============================================================
  // VIDEO
  // ============================================================

  Future<ChatMessageDto> sendVideo({
    required int conversationId,
    required XFile file,
    String text = '',
    int? replyToId,
  }) {
    return sendMedia(
      conversationId: conversationId,
      files: [file],
      messageType: 'video',
      text: text,
      replyToId: replyToId,
    );
  }

  // ============================================================
  // AUDIO
  // ============================================================

  Future<ChatMessageDto> sendAudio({
    required int conversationId,
    required XFile file,
    int? replyToId,
  }) {
    return sendMedia(
      conversationId: conversationId,
      files: [file],
      messageType: 'audio',
      replyToId: replyToId,
    );
  }

  // ============================================================
  // EDIT
  // ============================================================

  Future<ChatMessageDto> editMessage({
    required int messageId,
    required String text,
  }) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      throw const ChatApiException(
        statusCode: null,
        message: 'Message cannot be empty',
      );
    }

    try {
      final response = await dio.patch(
        '/chat/messages/$messageId/edit/',
        data: {
          'text': cleanText,
        },
      );

      return _parseMessage(response.data);
    } on DioException catch (error) {
      throw ChatApiException.fromDio(error);
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> deleteMessage(
    int messageId,
  ) async {
    try {
      await dio.delete(
        '/chat/messages/$messageId/delete/',
      );
    } on DioException catch (error) {
      throw ChatApiException.fromDio(error);
    }
  }

  // ============================================================
  // MARK SINGLE MESSAGE READ
  // ============================================================

  Future<bool> markMessageRead(
  int messageId,
) async {
  try {
    await dio.post(
      '/chat/messages/$messageId/read/',
    );

    return true;
  } on DioException catch (e) {
    debugPrint(
      '[CHAT API] markMessageRead failed: '
      '${e.response?.statusCode} ${e.response?.data}',
    );

    return false;
  } catch (e) {
    debugPrint(
      '[CHAT API] markMessageRead failed: $e',
    );

    return false;
  }
}

  // ============================================================
  // MARK CONVERSATION READ
  // ============================================================

  Future<bool> markConversationRead(
    int conversationId,
  ) async {
    try {
      await dio.post(
        '/chat/conversations/$conversationId/read/',
      );

      return true;
    } on DioException catch (error) {
      debugPrint(
        '[CHAT API] markConversationRead failed '
        'conversation=$conversationId: '
        '${error.message}',
      );

      return false;
    } catch (error) {
      debugPrint(
        '[CHAT API] markConversationRead failed '
        'conversation=$conversationId: $error',
      );

      return false;
    }
  }

  // ============================================================
  // RESPONSE PARSER
  // ============================================================

  ChatMessageDto _parseMessage(
    dynamic data,
  ) {
    if (data is! Map) {
      throw const ChatApiException(
        statusCode: null,
        message: 'Invalid message response',
      );
    }

    final map =
        Map<String, dynamic>.from(data);

    final nested = map['message'];

    if (nested is Map) {
      final message =
          ChatMessageDto.fromJson(
        Map<String, dynamic>.from(nested),
      );

      if (message.id <= 0) {
        throw const ChatApiException(
          statusCode: null,
          message:
              'Server returned an invalid message ID',
        );
      }

      return message;
    }

    final message =
        ChatMessageDto.fromJson(map);

    if (message.id <= 0) {
      throw const ChatApiException(
        statusCode: null,
        message:
            'Server returned an invalid message ID',
      );
    }

    return message;
  }
}