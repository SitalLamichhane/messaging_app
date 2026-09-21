import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MessageComposer extends StatefulWidget {
  final bool sending;
  final Future<void> Function(String text) onSendText;
  final Future<void> Function(
    List<XFile> images,
    String caption,
  ) onSendImages;

  const MessageComposer({
    super.key,
    required this.sending,
    required this.onSendText,
    required this.onSendImages,
  });

  @override
  State<MessageComposer> createState() =>
      _MessageComposerState();
}

class _MessageComposerState
    extends State<MessageComposer> {
  final TextEditingController _controller =
      TextEditingController();

  final ImagePicker _picker = ImagePicker();

  Future<void> _sendText() async {
    if (widget.sending) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    try {
      await widget.onSendText(text);
    } catch (_) {
      if (mounted) {
        _controller.text = text;
      }
    }
  }

  Future<void> _pickImages() async {
    if (widget.sending) return;

    final files = await _picker.pickMultiImage(
      imageQuality: 88,
    );

    if (files.isEmpty) return;

    final caption = _controller.text.trim();
    _controller.clear();

    try {
      await widget.onSendImages(
        files,
        caption,
      );
    } catch (_) {
      if (mounted) {
        _controller.text = caption;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          8,
          5,
          8,
          8,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                              .brightness ==
                          Brightness.dark
                      ? const Color(0xFF202C33)
                      : Colors.white,
                  borderRadius:
                      BorderRadius.circular(24),
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: widget.sending
                          ? null
                          : _pickImages,
                      icon: const Icon(
                        Icons.attach_file_rounded,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !widget.sending,
                        minLines: 1,
                        maxLines: 6,
                        textInputAction:
                            TextInputAction.newline,
                        decoration:
                            const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: const Color(0xFF128C7E),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap:
                    widget.sending ? null : _sendText,
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: widget.sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
