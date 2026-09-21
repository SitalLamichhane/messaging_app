import 'package:flutter/material.dart';
import 'package:hiddenly/groupChat/domain/chat_message_model.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessageDto message;
  final bool isMine;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMine
        ? const Color(0xFFD9FDD3)
        : Theme.of(context).brightness ==
                Brightness.dark
            ? const Color(0xFF202C33)
            : Colors.white;

    final textColor =
        Theme.of(context).brightness ==
                Brightness.dark &&
            !isMine
        ? Colors.white
        : Colors.black87;

    if (message.isDeleted) {
      return _shell(
        bg: bg,
        child: Text(
          'This message was deleted',
          style: TextStyle(
            color: textColor.withOpacity(0.65),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return _shell(
      bg: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine &&
              message.senderName.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.senderName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF128C7E),
                  fontSize: 12,
                ),
              ),
            ),

          if (message.attachments.isNotEmpty)
            _AttachmentGrid(
              attachments: message.attachments,
            ),

          if (message.text.trim().isNotEmpty) ...[
            if (message.attachments.isNotEmpty)
              const SizedBox(height: 7),
            Text(
              message.text,
              style: TextStyle(
                color: textColor,
                fontSize: 15.5,
              ),
            ),
          ],

          const SizedBox(height: 4),

          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _timeLabel(message.createdAt),
              style: TextStyle(
                color: textColor.withOpacity(0.55),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shell({
    required Color bg,
    required Widget child,
  }) {
    return Align(
      alignment: isMine
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 330,
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 3,
        ),
        padding: const EdgeInsets.fromLTRB(
          10,
          8,
          10,
          6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(
              isMine ? 14 : 3,
            ),
            bottomRight: Radius.circular(
              isMine ? 3 : 14,
            ),
          ),
        ),
        child: child,
      ),
    );
  }

  String _timeLabel(DateTime? date) {
    if (date == null) return '';

    final local = date.toLocal();
    final hour = local.hour % 12 == 0
        ? 12
        : local.hour % 12;
    final minute =
        local.minute.toString().padLeft(2, '0');
    final suffix =
        local.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $suffix';
  }
}

class _AttachmentGrid extends StatelessWidget {
  final List<ChatAttachmentDto> attachments;

  const _AttachmentGrid({
    required this.attachments,
  });

  @override
  Widget build(BuildContext context) {
    final visible = attachments.take(4).toList();

    if (visible.length == 1) {
      return _AttachmentTile(
        attachment: visible.first,
        extraCount: attachments.length - 1,
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final extra =
            index == visible.length - 1
                ? attachments.length -
                    visible.length
                : 0;

        return _AttachmentTile(
          attachment: visible[index],
          extraCount: extra,
        );
      },
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final ChatAttachmentDto attachment;
  final int extraCount;

  const _AttachmentTile({
    required this.attachment,
    required this.extraCount,
  });

  @override
  Widget build(BuildContext context) {
    final isImage =
        attachment.type == ChatMessageType.image ||
        attachment.mimeType.startsWith('image/');

    if (!isImage) {
      return Container(
        constraints: const BoxConstraints(
          minHeight: 72,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_rounded),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                attachment.fileName.isEmpty
                    ? 'Attachment'
                    : attachment.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            attachment.url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(
              color: Colors.black12,
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                ),
              ),
            ),
          ),
          if (extraCount > 0)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Text(
                  '+$extraCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
