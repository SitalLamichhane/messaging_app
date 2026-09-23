import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class MessageComposer extends StatefulWidget {
  final bool sending;
  final Future<void> Function(String text) onSendText;

  /// type must be: image, video, audio, or file.
  final Future<void> Function(
    List<XFile> files,
    String caption,
    String type,
  ) onSendMedia;

  const MessageComposer({
    super.key,
    required this.sending,
    required this.onSendText,
    required this.onSendMedia,
  });

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  bool _showEmoji = false;
  bool _recording = false;
  bool _openingAttachment = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  String? _recordPath;

  // Live microphone levels used by the WhatsApp-style recording waveform.
  final List<double> _recordWaveform = <double>[];
  bool _readingAmplitude = false;

  bool get _busy => widget.sending || _openingAttachment;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (_focusNode.hasFocus && _showEmoji && mounted) {
      setState(() => _showEmoji = false);
    }
  }

  Future<void> _sendText() async {
    if (_busy || _recording) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    try {
      await widget.onSendText(text);
    } catch (_) {
      if (!mounted) return;
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      rethrow;
    }
  }

  Future<void> _sendLike() async {
    if (_busy || _recording) return;
    await widget.onSendText('👍');
  }

  void _toggleEmoji() {
    if (_recording) return;

    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _showEmoji = true);
    }
  }

  void _insertEmoji(Emoji emoji) {
    final text = _controller.text;
    final selection = _controller.selection;

    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    final updated = text.replaceRange(start, end, emoji.emoji);

    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: start + emoji.emoji.length,
      ),
    );
  }

  Future<void> _pickGalleryImages() async {
    if (_busy || _recording) return;

    setState(() => _openingAttachment = true);

    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 88,
      );

      if (files.isEmpty) return;

      final caption = _controller.text.trim();
      _controller.clear();

      try {
        await widget.onSendMedia(files, caption, 'image');
      } catch (_) {
        if (mounted && caption.isNotEmpty) {
          _controller.text = caption;
        }
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _openingAttachment = false);
    }
  }

  Future<void> _takePhoto() async {
    if (_busy || _recording) return;

    setState(() => _openingAttachment = true);

    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );

      if (file == null) return;

      final caption = _controller.text.trim();
      _controller.clear();

      try {
        await widget.onSendMedia([file], caption, 'image');
      } catch (_) {
        if (mounted && caption.isNotEmpty) {
          _controller.text = caption;
        }
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _openingAttachment = false);
    }
  }

  Future<void> _pickVideo() async {
    if (_busy || _recording) return;

    setState(() => _openingAttachment = true);

    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (file == null) return;

      final caption = _controller.text.trim();
      _controller.clear();

      try {
        await widget.onSendMedia([file], caption, 'video');
      } catch (_) {
        if (mounted && caption.isNotEmpty) {
          _controller.text = caption;
        }
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _openingAttachment = false);
    }
  }

  Future<void> _pickFiles() async {
    if (_busy || _recording) return;

    setState(() => _openingAttachment = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      final files = result.files
          .where((item) => item.path != null && item.path!.trim().isNotEmpty)
          .map(
            (item) => XFile(
              item.path!,
              name: item.name,
              mimeType: item.extension,
            ),
          )
          .toList();

      if (files.isEmpty) return;

      final caption = _controller.text.trim();
      _controller.clear();

      try {
        await widget.onSendMedia(files, caption, 'file');
      } catch (_) {
        if (mounted && caption.isNotEmpty) {
          _controller.text = caption;
        }
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _openingAttachment = false);
    }
  }

  Future<void> _showAttachmentSheet() async {
    if (_busy || _recording) return;

    _focusNode.unfocus();
    if (_showEmoji) setState(() => _showEmoji = false);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF202C33)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _AttachmentAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickGalleryImages();
                  },
                ),
                _AttachmentAction(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _takePhoto();
                  },
                ),
                _AttachmentAction(
                  icon: Icons.videocam_rounded,
                  label: 'Video',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickVideo();
                  },
                ),
                _AttachmentAction(
                  icon: Icons.insert_drive_file_rounded,
                  label: 'File',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickFiles();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startRecording() async {
    if (_busy || _recording) return;

    try {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/group_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _recordPath = path;
      _recordDuration = Duration.zero;
      _recordWaveform.clear();
      _recordTimer?.cancel();

      if (mounted) {
        setState(() => _recording = true);
      }

      // A short interval makes the waveform feel live. getAmplitude() is
      // provided by package:record and does not change the recorded audio.
      _recordTimer = Timer.periodic(
        const Duration(milliseconds: 120),
        (_) async {
          if (!mounted || !_recording) return;

          _recordDuration += const Duration(milliseconds: 120);

          if (!_readingAmplitude) {
            _readingAmplitude = true;
            try {
              final amplitude = await _recorder.getAmplitude();
              // current is normally a negative dB value. Convert roughly
              // -60 dB..0 dB into 0.08..1.0 for drawing.
              final normalized =
                  ((amplitude.current + 60.0) / 60.0).clamp(0.08, 1.0);

              if (mounted && _recording) {
                setState(() {
                  _recordWaveform.add(normalized.toDouble());
                  if (_recordWaveform.length > 48) {
                    _recordWaveform.removeAt(0);
                  }
                });
              }
            } catch (_) {
              if (mounted && _recording) {
                setState(() {
                  _recordWaveform.add(0.12);
                  if (_recordWaveform.length > 48) {
                    _recordWaveform.removeAt(0);
                  }
                });
              }
            } finally {
              _readingAmplitude = false;
            }
          } else if (mounted) {
            setState(() {});
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start recording: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_recording) return;

    _recordTimer?.cancel();
    _recordTimer = null;

    try {
      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? _recordPath;

      if (mounted) {
        setState(() {
          _recording = false;
          _recordDuration = Duration.zero;
          _recordPath = null;
          _recordWaveform.clear();
        });
      }

      if (path == null || path.trim().isEmpty) return;

      final file = File(path);
      if (!await file.exists()) return;

      await widget.onSendMedia(
        [XFile(path, name: path.split(Platform.pathSeparator).last)],
        '',
        'audio',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _recordDuration = Duration.zero;
          _recordPath = null;
          _recordWaveform.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send voice message: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;

    _recordTimer?.cancel();
    _recordTimer = null;

    try {
      final path = await _recorder.stop();
      final target = path ?? _recordPath;

      if (target != null) {
        final file = File(target);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _recording = false;
      _recordDuration = Duration.zero;
      _recordPath = null;
    });
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _focusNode.removeListener(_handleFocus);
    _focusNode.dispose();
    _controller.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
            child: _recording
                ? _buildRecordingComposer(dark)
                : _buildNormalComposer(dark),
          ),
        ),
        if (_showEmoji && !_recording)
          SizedBox(
            height: 290,
            child: EmojiPicker(
              textEditingController: _controller,
              onEmojiSelected: (_, emoji) {
                _insertEmoji(emoji);
                if (mounted) setState(() {});
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingComposer(bool dark) {
    return Row(
      children: [
        // WhatsApp-like delete box: stop recording, delete the temp file,
        // and return to the normal composer without sending anything.
        Material(
          color: dark ? const Color(0xFF202C33) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _busy ? null : _cancelRecording,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFE53935),
                size: 25,
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF202C33) : Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const _RecordingPulseDot(),
                const SizedBox(width: 7),
                Text(
                  _durationLabel(_recordDuration),
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFD1D7DB)
                        : const Color(0xFF3B4A54),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: CustomPaint(
                      painter: _LiveRecordingWaveformPainter(
                        samples: List<double>.from(_recordWaveform),
                        color: dark
                            ? const Color(0xFF8696A0)
                            : const Color(0xFF667781),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 7),
        Material(
          color: const Color(0xFF00A884),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _busy ? null : _stopAndSendRecording,
            child: SizedBox(
              width: 50,
              height: 50,
              child: widget.sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalComposer(bool dark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          onPressed: _busy ? null : _showAttachmentSheet,
          icon: const Icon(Icons.attach_file_rounded),
        ),
        IconButton(
          onPressed: _busy ? null : _takePhoto,
          icon: const Icon(Icons.camera_alt_rounded),
        ),
        IconButton(
          onPressed: _busy ? null : _startRecording,
          icon: const Icon(Icons.mic_rounded),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF202C33) : Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 20,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _toggleEmoji,
                  icon: Icon(
                    _showEmoji
                        ? Icons.keyboard_rounded
                        : Icons.emoji_emotions_outlined,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (_controller.text.trim().isEmpty)
          IconButton(
            onPressed: _busy ? null : _sendLike,
            icon: const Icon(
              Icons.thumb_up_rounded,
              color: Color(0xFF128C7E),
            ),
          )
        else
          Material(
            color: const Color(0xFF128C7E),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _busy ? null : _sendText,
              child: const Padding(
                padding: EdgeInsets.all(13),
                child: Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }


}



class _RecordingPulseDot extends StatefulWidget {
  const _RecordingPulseDot();

  @override
  State<_RecordingPulseDot> createState() => _RecordingPulseDotState();
}

class _RecordingPulseDotState extends State<_RecordingPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: 0.35,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
        ),
        child: SizedBox(width: 9, height: 9),
      ),
    );
  }
}

class _LiveRecordingWaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;

  const _LiveRecordingWaveformPainter({
    required this.samples,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    const gap = 4.5;
    final count = (size.width / gap).floor().clamp(1, 60);
    final visible = samples.length > count
        ? samples.sublist(samples.length - count)
        : samples;

    for (var i = 0; i < count; i++) {
      final sampleIndex = i - (count - visible.length);
      final value = sampleIndex >= 0 ? visible[sampleIndex] : 0.08;
      final h = (4.0 + value * (size.height - 7.0))
          .clamp(4.0, size.height);
      final x = i * gap + 1;
      final top = (size.height - h) / 2;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiveRecordingWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.color != color;
  }
}

class _AttachmentAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF128C7E).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: const Color(0xFF128C7E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
