// lib/core/chat/chat_api.dart

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:messaging_app/core/api_client.dart';

class ChatApi {
  static Future<Response> startPrivateChat({
    required int userId,
  }) {
    return ApiClient.dio.post(
      '/chat/private/start/',
      data: {
        'user_id': userId,
      },
    );
  }

  static Future<Response> searchUser({
    required String phone,
  }) {
    return ApiClient.dio.get(
      '/chat/search-user/',
      queryParameters: {
        'phone': phone.trim(),
      },
    );
  }

  static Future<Response> createGroup({
    required String name,
    required List<int> memberIds,
    File? groupImage,
  }) async {
    final formData = FormData.fromMap({
      'name': name.trim(),
      'member_ids': memberIds,
      if (groupImage != null)
        'group_image': await MultipartFile.fromFile(
          groupImage.path,
          filename: groupImage.path.split('/').last,
        ),
    });

    return ApiClient.dio.post(
      '/chat/groups/create/',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
  }

  static Future<Response> getConversations() {
    return ApiClient.dio.get(
      '/chat/conversations/',
      options: Options(
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    );
  }

  static Future<Response> getMessages({
    required int conversationId,
  }) {
    return ApiClient.dio.get(
      '/chat/conversations/$conversationId/messages/',
    );
  }

  static Future<Response> sendText({
    required int conversationId,
    required String text,
  }) {
    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/send/',
      data: {
        'message_type': 'text',
        'text': text.trim(),
      },
    );
  }

  static Future<Response> sendReply({
    required int conversationId,
    required String text,
    required int replyTo,
  }) {
    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/send/',
      data: {
        'message_type': 'text',
        'text': text.trim(),
        'reply_to': replyTo,
      },
    );
  }

  static Future<Response> sendReaction({
    required int conversationId,
    required int reactionTo,
    required String reaction,
  }) {
    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/send/',
      data: {
        'message_type': 'reaction',
        'reaction_to': reactionTo,
        'reaction': reaction,
      },
    );
  }

  static Future<Response> sendImage({
    required int conversationId,
    required File image,
    String? caption,
  }) async {
    final formData = FormData.fromMap({
      'message_type': 'image',
      'media': await MultipartFile.fromFile(
        image.path,
        filename: image.path.split('/').last,
      ),
      if (caption != null && caption.trim().isNotEmpty) 'text': caption.trim(),
    });

    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/send/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

static Future<Response> sendImages({
  required int conversationId,
  required List<File> images,
  String? caption,
}) async {
  if (images.isEmpty) {
    throw Exception('No images selected');
  }

  final formData = FormData();

  formData.fields.add(
    const MapEntry('message_type', 'media_album'),
  );

  if (caption != null && caption.trim().isNotEmpty) {
    formData.fields.add(
      MapEntry('text', caption.trim()),
    );
  }

  for (final image in images) {
    formData.files.add(
      MapEntry(
        'media',
        await MultipartFile.fromFile(
          image.path,
          filename: image.path.split('/').last,
        ),
      ),
    );
  }

  return ApiClient.dio.post(
    '/chat/conversations/$conversationId/send/',
    data: formData,
    options: Options(
      contentType: 'multipart/form-data',
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ),
  );
}

  static Future<Response> sendVideo({
    required int conversationId,
    required File video,
    required double duration,
    String? caption,
  }) async {
    final formData = FormData.fromMap({
      'message_type': 'video',
      'media': await MultipartFile.fromFile(
        video.path,
        filename: video.path.split('/').last,
      ),
      'duration': duration,
      if (caption != null && caption.trim().isNotEmpty) 'text': caption.trim(),
    });

    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/send/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  static Future<Response> sendAudio({
    required int conversationId,
    required File audio,
    required double duration,
  }) async {
    final formData = FormData.fromMap({
      'message_type': 'audio',
      'media': await MultipartFile.fromFile(
        audio.path,
        filename: audio.path.split('/').last,
      ),
      'duration': duration,
    });

    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/send/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  static Future<Response> sendFile({
    required int conversationId,
    required File file,
  }) async {
    final formData = FormData.fromMap({
      'message_type': 'file',
      'media': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
    });

    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/send/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  static Future<Response> deleteMessageForMe({
    required int conversationId,
    required int messageId,
  }) {
    return ApiClient.dio.delete(
      '/chat/conversations/$conversationId/messages/$messageId/delete-for-me/',
    );
  }

  static Future<Response> deleteMessageForEveryone({
    required int conversationId,
    required int messageId,
  }) {
    return ApiClient.dio.delete(
      '/chat/conversations/$conversationId/messages/$messageId/delete-for-everyone/',
    );
  }

  static Future<Response> togglePinMessage({
    required int conversationId,
    required int messageId,
  }) {
    return ApiClient.dio.post(
      '/chat/conversations/$conversationId/messages/$messageId/pin/',
    );
  }
}