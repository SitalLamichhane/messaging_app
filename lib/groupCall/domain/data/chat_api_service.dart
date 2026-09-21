import 'package:dio/dio.dart';
import 'package:hiddenly/groupChat/domain/chat_message_model.dart';
import 'package:image_picker/image_picker.dart';

import 'package:hiddenly/core/api_client.dart';

class ChatApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? data;

  const ChatApiException({
    required this.statusCode,
    required this.message,
    this.data,
  });

  factory ChatApiException.fromDio(
    DioException error,
  ) {
    final data = error.response?.data;

    String message = 'Chat request failed';

    if (data is Map) {
      message = (data['error'] ??
              data['detail'] ??
              data['message'] ??
              message)
          .toString();
    } else if (data != null) {
      message = data.toString();
    } else if (error.message != null) {
      message = error.message!;
    }

    return ChatApiException(
      statusCode: error.response?.statusCode,
      message: message,
      data: data,
    );
  }

  @override
  String toString() =>
      'ChatApiException($statusCode): $message';
}

class ChatApiService {
  final Dio dio;

  ChatApiService({
    Dio? dio,
  }) : dio = dio ?? ApiClient.dio;

  Future<List<ChatMessageDto>> loadMessages(
    int conversationId,
  ) async {
    try {
      final response = await dio.get(
        '/chat/conversations/$conversationId/messages/',
      );

      final data = response.data;

      List<dynamic> items;

      if (data is List) {
        items = data;
      } else if (data is Map && data['results'] is List) {
        items = List<dynamic>.from(
          data['results'] as List,
        );
      } else {
        items = const [];
      }

      return items
          .whereType<Map>()
          .map(
            (item) => ChatMessageDto.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList()
        ..sort(
          (a, b) {
            final aDate =
                a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

            return aDate.compareTo(bDate);
          },
        );
    } on DioException catch (e) {
      throw ChatApiException.fromDio(e);
    }
  }

  Future<ChatMessageDto> sendText({
    required int conversationId,
    required String text,
    int? replyToId,
  }) async {
    try {
      final response = await dio.post(
        '/chat/conversations/$conversationId/send/',
        data: {
          'text': text.trim(),
          'message_type': 'text',
          if (replyToId != null)
            'reply_to': replyToId,
        },
      );

      return ChatMessageDto.fromJson(
        Map<String, dynamic>.from(
          response.data as Map,
        ),
      );
    } on DioException catch (e) {
      throw ChatApiException.fromDio(e);
    }
  }

  Future<ChatMessageDto> sendMedia({
    required int conversationId,
    required List<XFile> files,
    String text = '',
    int? replyToId,
  }) async {
    if (files.isEmpty) {
      return sendText(
        conversationId: conversationId,
        text: text,
        replyToId: replyToId,
      );
    }

    try {
      final formData = FormData();

      formData.fields.add(
        MapEntry('text', text.trim()),
      );

      if (replyToId != null) {
        formData.fields.add(
          MapEntry('reply_to', replyToId.toString()),
        );
      }

      // Using the exact field "media" repeatedly matches
      // request.FILES.getlist("media") in your Django backend.
      for (final file in files) {
        formData.files.add(
          MapEntry(
            'media',
            await MultipartFile.fromFile(
              file.path,
              filename: file.name,
            ),
          ),
        );
      }

      final response = await dio.post(
        '/chat/conversations/$conversationId/send/',
        data: formData,
      );

      return ChatMessageDto.fromJson(
        Map<String, dynamic>.from(
          response.data as Map,
        ),
      );
    } on DioException catch (e) {
      throw ChatApiException.fromDio(e);
    }
  }

  Future<ChatMessageDto> editMessage({
    required int messageId,
    required String text,
  }) async {
    try {
      final response = await dio.patch(
        '/chat/messages/$messageId/edit/',
        data: {
          'text': text,
        },
      );

      return ChatMessageDto.fromJson(
        Map<String, dynamic>.from(
          response.data as Map,
        ),
      );
    } on DioException catch (e) {
      throw ChatApiException.fromDio(e);
    }
  }

  Future<void> deleteMessage(
    int messageId,
  ) async {
    try {
      await dio.delete(
        '/chat/messages/$messageId/delete/',
      );
    } on DioException catch (e) {
      throw ChatApiException.fromDio(e);
    }
  }

  Future<void> markMessageRead(
    int messageId,
  ) async {
    try {
      await dio.post(
        '/chat/messages/$messageId/read/',
      );
    } on DioException catch (e) {
      throw ChatApiException.fromDio(e);
    }
  }

  Future<void> markConversationRead(
    int conversationId,
  ) async {
    try {
      await dio.post(
        '/chat/conversations/$conversationId/read/',
      );
    } on DioException catch (e) {
      throw ChatApiException.fromDio(e);
    }
  }
}
