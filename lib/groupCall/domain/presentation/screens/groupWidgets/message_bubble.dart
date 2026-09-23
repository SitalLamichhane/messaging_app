import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddenly/groupChat/domain/chat_message_model.dart';
import 'package:just_audio/just_audio.dart';

import 'image_viewer.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessageDto message;
  final bool isMine;
  final VoidCallback? onDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // WhatsApp-style colors.
    final bubbleColor = isMine
        ? (dark
            ? const Color(0xFF005C4B)
            : const Color(0xFFD9FDD3))
        : (dark
            ? const Color(0xFF202C33)
            : Colors.white);

    final textColor = dark
        ? Colors.white
        : const Color(0xFF111B21);

    final secondaryColor = dark
        ? const Color(0xFF8696A0)
        : const Color(0xFF667781);

    return Align(
      alignment:
          isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: isMine && !message.isDeleted
            ? () => _showDeleteSheet(context)
            : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          margin: EdgeInsets.only(
            left: isMine ? 56 : 8,
            right: isMine ? 8 : 56,
            top: 2,
            bottom: 2,
          ),
          padding: EdgeInsets.fromLTRB(
            message.attachments.isNotEmpty && !message.isDeleted
                ? 4
                : 9,
            message.attachments.isNotEmpty && !message.isDeleted
                ? 4
                : 7,
            message.attachments.isNotEmpty && !message.isDeleted
                ? 4
                : 8,
            5,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(8),
              topRight: const Radius.circular(8),
              bottomLeft: Radius.circular(
                isMine ? 8 : 2,
              ),
              bottomRight: Radius.circular(
                isMine ? 2 : 8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: _buildContent(
            context: context,
            textColor: textColor,
            secondaryColor: secondaryColor,
          ),
        ),
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required Color textColor,
    required Color secondaryColor,
  }) {
    if (message.isDeleted) {
      return _DeletedMessage(
        message: message,
        isMine: isMine,
        secondaryColor: secondaryColor,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMine && message.senderName.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              message.attachments.isNotEmpty ? 5 : 0,
              0,
              message.attachments.isNotEmpty ? 5 : 0,
              4,
            ),
            child: Text(
              message.senderName.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _senderColor(message.senderName),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

        if (message.attachments.isNotEmpty)
          AttachmentGrid(
            attachments: message.attachments,
          ),

        if (message.text.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              message.attachments.isNotEmpty ? 5 : 0,
              message.attachments.isNotEmpty ? 6 : 0,
              message.attachments.isNotEmpty ? 5 : 0,
              0,
            ),
            child: _buildTextAndMeta(
              textColor: textColor,
              secondaryColor: secondaryColor,
            ),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(
              message.attachments.isNotEmpty ? 5 : 0,
              3,
              message.attachments.isNotEmpty ? 5 : 0,
              0,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: _MessageMeta(
                message: message,
                isMine: isMine,
                secondaryColor: secondaryColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTextAndMeta({
    required Color textColor,
    required Color secondaryColor,
  }) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(
          message.text.trim(),
          style: TextStyle(
            color: textColor,
            fontSize: 15.5,
            height: 1.28,
          ),
        ),
        _MessageMeta(
          message: message,
          isMine: isMine,
          secondaryColor: secondaryColor,
        ),
      ],
    );
  }

  void _showDeleteSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.red,
            ),
            title: const Text(
              'Delete message',
              style: TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onDelete?.call();
            },
          ),
        );
      },
    );
  }

  Color _senderColor(String name) {
    const colors = <Color>[
      Color(0xFF00A884),
      Color(0xFFE17076),
      Color(0xFF7E90D2),
      Color(0xFFBB7ACD),
      Color(0xFFDFA12C),
      Color(0xFF2D9CDB),
      Color(0xFF1AA260),
    ];

    if (name.trim().isEmpty) {
      return colors.first;
    }

    return colors[name.hashCode.abs() % colors.length];
  }
}

class _DeletedMessage extends StatelessWidget {
  final ChatMessageDto message;
  final bool isMine;
  final Color secondaryColor;

  const _DeletedMessage({
    required this.message,
    required this.isMine,
    required this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block_rounded,
              size: 16,
              color: secondaryColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'This message was deleted',
                style: TextStyle(
                  color: secondaryColor,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Align(
          alignment: Alignment.centerRight,
          child: _MessageMeta(
            message: message,
            isMine: isMine,
            secondaryColor: secondaryColor,
            showEdited: false,
          ),
        ),
      ],
    );
  }
}

class _MessageMeta extends StatelessWidget {
  final ChatMessageDto message;
  final bool isMine;
  final Color secondaryColor;
  final bool showEdited;

  const _MessageMeta({
    required this.message,
    required this.isMine,
    required this.secondaryColor,
    this.showEdited = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEdited && message.isEdited) ...[
          Text(
            'edited',
            style: TextStyle(
              color: secondaryColor,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4),
        ],

        Text(
          _timeLabel(message.createdAt),
          style: TextStyle(
            color: secondaryColor,
            fontSize: 10.5,
          ),
        ),

        if (isMine) ...[
          const SizedBox(width: 3),
          _MessageTicks(
            message: message,
            secondaryColor: secondaryColor,
          ),
        ],
      ],
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

class _MessageTicks extends StatelessWidget {
  final ChatMessageDto message;
  final Color secondaryColor;

  const _MessageTicks({
    required this.message,
    required this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    /*
     * WhatsApp-like state:
     *
     * seen      => blue double tick
     * delivered => grey double tick
     * otherwise => grey single tick
     *
     * This requires ChatMessageDto to contain:
     *
     * bool delivered;
     * bool seen;
     */

    if (message.seen) {
      return const Icon(
        Icons.done_all_rounded,
        size: 16,
        color: Color(0xFF53BDEB),
      );
    }

    if (message.delivered) {
      return Icon(
        Icons.done_all_rounded,
        size: 16,
        color: secondaryColor,
      );
    }

    return Icon(
      Icons.done_rounded,
      size: 16,
      color: secondaryColor,
    );
  }
}

class AttachmentGrid extends StatelessWidget {
  final List<ChatAttachmentDto> attachments;

  const AttachmentGrid({
    super.key,
    required this.attachments,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }

    final images = attachments
        .where(_isImage)
        .toList();

    final audios = attachments
        .where(_isAudio)
        .toList();

    final files = attachments
        .where(
          (attachment) =>
              !_isImage(attachment) &&
              !_isAudio(attachment),
        )
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // =========================
        // IMAGES
        // =========================

        if (images.isNotEmpty)
          _ImageGrid(
            images: images,
          ),

        if (images.isNotEmpty &&
            (audios.isNotEmpty ||
                files.isNotEmpty))
          const SizedBox(height: 4),

        // =========================
        // AUDIO / VOICE
        // =========================

        for (int i = 0;
            i < audios.length;
            i++) ...[
          _AudioAttachmentTile(
            attachment: audios[i],
          ),

          if (i != audios.length - 1)
            const SizedBox(height: 4),
        ],

        if (audios.isNotEmpty &&
            files.isNotEmpty)
          const SizedBox(height: 4),

        // =========================
        // OTHER FILES
        // =========================

        for (int i = 0;
            i < files.length;
            i++) ...[
          _FileAttachmentTile(
            attachment: files[i],
          ),

          if (i != files.length - 1)
            const SizedBox(height: 4),
        ],
      ],
    );
  }

  static bool _isImage(
    ChatAttachmentDto attachment,
  ) {
    return attachment.type ==
            ChatMessageType.image ||
        attachment.mimeType
            .toLowerCase()
            .startsWith('image/');
  }

  static bool _isAudio(
    ChatAttachmentDto attachment,
  ) {
    final mime =
        attachment.mimeType
            .toLowerCase()
            .trim();

    final name =
        attachment.fileName
            .toLowerCase()
            .trim();

    return attachment.type ==
            ChatMessageType.audio ||
        mime.startsWith('audio/') ||
        name.endsWith('.m4a') ||
        name.endsWith('.mp3') ||
        name.endsWith('.aac') ||
        name.endsWith('.wav') ||
        name.endsWith('.ogg') ||
        name.endsWith('.opus');
  }
}

class _ImageGrid extends StatelessWidget {
  final List<ChatAttachmentDto> images;

  const _ImageGrid({
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    final visible = images.take(4).toList();

    if (visible.length == 1) {
      return SizedBox(
        height: 220,
        width: double.infinity,
        child: _ImageTile(
          attachment: visible.first,
          index: 0,
          allImages: images,
          extraCount: 0,
        ),
      );
    }

    if (visible.length == 2) {
      return SizedBox(
        height: 190,
        child: Row(
          children: [
            Expanded(
              child: _ImageTile(
                attachment: visible[0],
                index: 0,
                allImages: images,
                extraCount: 0,
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: _ImageTile(
                attachment: visible[1],
                index: 1,
                allImages: images,
                extraCount: 0,
              ),
            ),
          ],
        ),
      );
    }

    if (visible.length == 3) {
      return SizedBox(
        height: 220,
        child: Row(
          children: [
            Expanded(
              child: _ImageTile(
                attachment: visible[0],
                index: 0,
                allImages: images,
                extraCount: 0,
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _ImageTile(
                      attachment: visible[1],
                      index: 1,
                      allImages: images,
                      extraCount: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Expanded(
                    child: _ImageTile(
                      attachment: visible[2],
                      index: 2,
                      allImages: images,
                      extraCount: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics:
            const NeverScrollableScrollPhysics(),
        itemCount: visible.length,
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemBuilder: (context, index) {
          final extra = index == 3
              ? images.length - 4
              : 0;

          return _ImageTile(
            attachment: visible[index],
            index: index,
            allImages: images,
            extraCount: extra,
          );
        },
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  final ChatAttachmentDto attachment;
  final int index;
  final int extraCount;
  final List<ChatAttachmentDto> allImages;

  const _ImageTile({
    required this.attachment,
    required this.index,
    required this.allImages,
    required this.extraCount,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        _mediaUrl(attachment.url);

    return Material(
      color: Colors.black12,
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final urls = allImages
              .map((item) => _mediaUrl(item.url))
              .where((url) => url.isNotEmpty)
              .toList();

          if (urls.isEmpty) {
            return;
          }

          final safeIndex =
              index.clamp(0, urls.length - 1);

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImageViewer(
                images: urls,
                initialIndex: safeIndex,
              ),
            ),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (
                  context,
                  child,
                  progress,
                ) {
                  if (progress == null) {
                    return child;
                  }

                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                  );
                },
                errorBuilder: (
                  context,
                  error,
                  stackTrace,
                ) {
                  return const _BrokenImage();
                },
              )
            else
              const _BrokenImage(),

            if (extraCount > 0)
              Container(
                color:
                    Colors.black.withOpacity(0.58),
                alignment: Alignment.center,
                child: Text(
                  '+$extraCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE1E5E7),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 36,
          color: Color(0xFF667781),
        ),
      ),
    );
  }
}
class _AudioAttachmentTile extends StatefulWidget {
  final ChatAttachmentDto attachment;

  const _AudioAttachmentTile({
    required this.attachment,
  });

  @override
  State<_AudioAttachmentTile> createState() => _AudioAttachmentTileState();
}

class _AudioAttachmentTileState extends State<_AudioAttachmentTile> {
  late final AudioPlayer _player;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _loading = false;
  bool _initialized = false;
  bool _hasError = false;

  late final List<double> _waveform;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _waveform = _makeStableWaveform(
      '${widget.attachment.url}|${widget.attachment.fileName}',
    );

    _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });

    _player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() => _duration = duration);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;

      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
        setState(() => _position = Duration.zero);
      } else {
        setState(() {});
      }
    });
  }

  Future<bool> _ensureLoaded() async {
    if (_initialized) return true;

    final url = _mediaUrl(widget.attachment.url);
    if (url.isEmpty) return false;

    setState(() {
      _loading = true;
      _hasError = false;
    });

    try {
      final duration = await _player.setUrl(url);
      if (!mounted) return false;

      setState(() {
        _initialized = true;
        if (duration != null) _duration = duration;
        _loading = false;
      });
      return true;
    } catch (error) {
      debugPrint('Audio load error: $error');
      if (!mounted) return false;

      setState(() {
        _loading = false;
        _hasError = true;
      });
      return false;
    }
  }

  Future<void> _togglePlayback() async {
    if (_loading) return;

    if (_player.playing) {
      await _player.pause();
      return;
    }

    final loaded = await _ensureLoaded();
    if (!loaded) return;

    if (_duration > Duration.zero && _position >= _duration) {
      await _player.seek(Duration.zero);
    }

    await _player.play();
  }

  Future<void> _seekFromFraction(double fraction) async {
    final loaded = await _ensureLoaded();
    if (!loaded || _duration <= Duration.zero) return;

    final safe = fraction.clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (_duration.inMilliseconds * safe).round(),
    );
    await _player.seek(target);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final playing = _player.playing;

    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds)
            .clamp(0.0, 1.0);

    // WhatsApp shows elapsed time once playback has moved; otherwise it shows
    // the full voice-note duration.
    final shownTime =
        _position > Duration.zero ? _position : _duration;

    final playedColor =
        dark ? const Color(0xFF00A884) : const Color(0xFF008069);
    final unplayedColor =
        dark ? const Color(0xFF8696A0) : const Color(0xFF667781);

    return SizedBox(
      width: 285,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 3, 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFF00A884),
                      ),
                    )
                  : IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: _togglePlayback,
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 39,
                        color: _hasError ? Colors.red : playedColor,
                      ),
                    ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 32,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        void seek(Offset localPosition) {
                          if (constraints.maxWidth <= 0) return;
                          _seekFromFraction(
                            localPosition.dx / constraints.maxWidth,
                          );
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) =>
                              seek(details.localPosition),
                          onHorizontalDragUpdate: (details) =>
                              seek(details.localPosition),
                          child: CustomPaint(
                            size: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                            painter: _VoiceWaveformPainter(
                              samples: _waveform,
                              progress: progress,
                              playedColor: playedColor,
                              unplayedColor: unplayedColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 1, top: 1),
                    child: Row(
                      children: [
                        if (_hasError)
                          const Text(
                            'Unable to play',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                            ),
                          )
                        else
                          Text(
                            _formatDuration(shownTime),
                            style: TextStyle(
                              color: unplayedColor,
                              fontSize: 11,
                            ),
                          ),
                        const Spacer(),
                        Icon(
                          Icons.mic_rounded,
                          size: 15,
                          color: playedColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<double> _makeStableWaveform(String seedText) {
    // The server currently stores the audio file but not waveform peaks.
    // Generate a stable visual shape from the attachment identity. Playback
    // progress is real; if you later store peaks on upload, replace this list
    // with those peaks for an exact audio waveform.
    var seed = 0;
    for (final unit in seedText.codeUnits) {
      seed = ((seed * 31) + unit) & 0x7fffffff;
    }

    final random = math.Random(seed);
    return List<double>.generate(48, (index) {
      final wave = 0.25 + (math.sin(index * 0.62).abs() * 0.28);
      final noise = random.nextDouble() * 0.47;
      return (wave + noise).clamp(0.14, 1.0);
    });
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  const _VoiceWaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final spacing = size.width / samples.length;
    final stroke = math.min(2.7, math.max(1.5, spacing * 0.52));
    final playedX = size.width * progress;

    for (var i = 0; i < samples.length; i++) {
      final x = spacing * i + spacing / 2;
      final h = (4.0 + samples[i] * (size.height - 7.0))
          .clamp(4.0, size.height);

      final paint = Paint()
        ..color = x <= playedX ? playedColor : unplayedColor
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }

    if (progress > 0 && progress < 1) {
      final dotPaint = Paint()..color = playedColor;
      canvas.drawCircle(
        Offset(playedX, size.height / 2),
        4.2,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.samples != samples ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.unplayedColor != unplayedColor;
  }
}

class _FileAttachmentTile extends StatelessWidget {
  final ChatAttachmentDto attachment;

  const _FileAttachmentTile({
    required this.attachment,
  });

  @override
  Widget build(BuildContext context) {
    final dark =
        Theme.of(context).brightness ==
            Brightness.dark;

    final fileName =
        attachment.fileName.trim().isEmpty
            ? 'Attachment'
            : attachment.fileName.trim();

    return Container(
      constraints:
          const BoxConstraints(minHeight: 64),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF182229)
            : Colors.black.withOpacity(0.055),
        borderRadius:
            BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF233138)
                  : Colors.white,
              borderRadius:
                  BorderRadius.circular(6),
            ),
            child: Icon(
              _fileIcon(attachment),
              size: 25,
              color: const Color(0xFF00A884),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dark
                        ? Colors.white
                        : const Color(
                            0xFF111B21,
                          ),
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w500,
                  ),
                ),

                if (_fileDescription(
                        attachment)
                    .isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _fileDescription(
                      attachment,
                    ),
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667781),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 6),

          const Icon(
            Icons.file_download_outlined,
            size: 22,
            color: Color(0xFF667781),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(
    ChatAttachmentDto attachment,
  ) {
    switch (attachment.type) {
      case ChatMessageType.video:
        return Icons.videocam_outlined;

      case ChatMessageType.audio:
        return Icons.headphones_rounded;

      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _fileDescription(
    ChatAttachmentDto attachment,
  ) {
    final parts = <String>[];

    if (attachment.mimeType.trim().isNotEmpty) {
      parts.add(
        attachment.mimeType
            .split('/')
            .last
            .toUpperCase(),
      );
    }

    if (attachment.fileSize != null &&
        attachment.fileSize! > 0) {
      parts.add(
        _formatBytes(
          attachment.fileSize!,
        ),
      );
    }

    return parts.join(' • ');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    final kb = bytes / 1024;

    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    }

    final mb = kb / 1024;

    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }
}

String _mediaUrl(String rawUrl) {
  var url = rawUrl.trim();

  if (url.isEmpty) {
    return '';
  }

  // Backend sometimes returns Hiddenly media
  // URLs using http. Force our own domain to HTTPS.
  if (url.startsWith(
    'http://hiddenly.org/',
  )) {
    url = url.replaceFirst(
      'http://hiddenly.org/',
      'https://hiddenly.org/',
    );
  }

  final uri =
      Uri.tryParse(url);

  if (uri != null &&
      (uri.scheme == 'http' ||
          uri.scheme == 'https')) {
    return url;
  }

  final normalized =
      url.startsWith('/')
          ? url
          : '/$url';

  return 'https://hiddenly.org$normalized';
}