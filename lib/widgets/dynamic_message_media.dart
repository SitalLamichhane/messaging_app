import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/config/app_config.dart';
import 'package:video_player/video_player.dart';

String get baseServerUrl => AppConfig.serverUrl;

String fixedMediaUrl(String? url) {
  if (url == null || url.trim().isEmpty) return '';

  final decoded = Uri.decodeFull(url.trim());

  if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
    return decoded;
  }

  if (decoded.startsWith('/media/')) {
    return '$baseServerUrl$decoded';
  }

  return decoded;
}

bool _isNetworkPath(String path) {
  return path.startsWith('http://') || path.startsWith('https://');
}

class DynamicMessageMedia extends StatelessWidget {
  final ChatMessage message;
  final bool isDark;

  const DynamicMessageMedia({
    super.key,
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
  case MessageType.image:
    return _ImageBubble(message: message);

  case MessageType.mediaAlbum:
    return _MediaAlbumBubble(
      message: message,
    );

  case MessageType.audio:
        return _AudioBubble(message: message);

      case MessageType.video:
        return _VideoBubble(message: message);

      case MessageType.file:
        return _FileBubble(message: message, isDark: isDark);

      default:
        return const SizedBox.shrink();
    }
  }
}

class _ImageBubble extends StatelessWidget {
  final ChatMessage message;

  const _ImageBubble({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final path = fixedMediaUrl(message.filePath);

    if (path.isEmpty) return const SizedBox.shrink();

    final imageWidget = _isNetworkPath(path)
        ? Image.network(
            path,
            width: 230,
            height: 280,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return const _BrokenMediaBox(
                icon: Icons.broken_image_rounded,
                text: 'Image not found',
              );
            },
          )
        : Image.file(
            File(path),
            width: 230,
            height: 280,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return const _BrokenMediaBox(
                icon: Icons.broken_image_rounded,
                text: 'Image not found',
              );
            },
          );

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (_, __, ___) => _FullScreenImageViewer(
              imagePath: path,
              isNetwork: _isNetworkPath(path),
              heroTag: 'image_${message.id}',
            ),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Hero(
        tag: 'image_${message.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: imageWidget,
        ),
      ),
    );
  }
}


class _FullScreenImageViewer extends StatelessWidget {
  final String imagePath;
  final bool isNetwork;
  final String heroTag;

  const _FullScreenImageViewer({
    required this.imagePath,
    required this.isNetwork,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final image = isNetwork
        ? Image.network(
            imagePath,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.white, size: 48),
            ),
          )
        : Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.white, size: 48),
            ),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() > 450) {
                  Navigator.pop(context);
                }
              },
              child: Center(
                child: Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.5,
                    child: image,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioBubble extends StatefulWidget {
  final ChatMessage message;

  const _AudioBubble({
    required this.message,
  });

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final AudioPlayer _player = AudioPlayer();

  bool _isReady = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final path = fixedMediaUrl(
        widget.message.audioPath ?? widget.message.filePath,
      );

      if (path.isEmpty) return;

      if (_isNetworkPath(path)) {
        await _player.setUrl(path);
      } else {
        await _player.setFilePath(path);
      }

      _duration =
          _player.duration ?? widget.message.audioDuration ?? Duration.zero;

      _player.positionStream.listen((position) {
        if (!mounted) return;

        setState(() {
          _position = position;
        });
      });

      _player.playerStateStream.listen((state) async {
        if (!mounted) return;

        setState(() {
          _isPlaying = state.playing;
        });

        if (state.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
          await _player.pause();
        }
      });

      if (!mounted) return;

      setState(() {
        _isReady = true;
      });
    } catch (e) {
      debugPrint('AUDIO LOAD ERROR: $e');
    }
  }

  Future<void> _toggle() async {
    if (!_isReady) return;

    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.message.isMe;

    final bgColor = isMe ? const Color(0xFF1877F2) : const Color(0xFFEFEFF4);
    final textColor = isMe ? Colors.white : Colors.black87;
    final waveColor = isMe ? Colors.white : const Color(0xFF1877F2);

    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(isMe ? 22 : 6),
          bottomRight: Radius.circular(isMe ? 6 : 22),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(999),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: const Color(0xFF1877F2),
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MiniWaveform(
                  isPlaying: _isPlaying,
                  color: waveColor,
                ),
                const SizedBox(height: 4),
                Text(
                  _duration == Duration.zero
                      ? _format(_position)
                      : '${_format(_position)} / ${_format(_duration)}',
                  style: TextStyle(
                    color: textColor.withOpacity(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 14,
            backgroundColor:
                isMe ? Colors.white.withOpacity(0.25) : const Color(0xFFD8DADF),
            child: Icon(
              Icons.mic_rounded,
              color: textColor,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniWaveform extends StatelessWidget {
  final bool isPlaying;
  final Color color;

  const _MiniWaveform({
    required this.isPlaying,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final values = isPlaying
        ? [
            0.25,
            0.70,
            0.35,
            0.85,
            0.45,
            0.95,
            0.30,
            0.65,
            0.40,
            0.80,
            0.50,
            0.35,
          ]
        : [
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
            0.35,
          ];

    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: values.map((value) {
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 1.4),
              height: 6 + (20 * value),
              decoration: BoxDecoration(
                color: color.withOpacity(0.85),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _VideoBubble extends StatefulWidget {
  final ChatMessage message;

  const _VideoBubble({
    required this.message,
  });

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final path = fixedMediaUrl(widget.message.filePath);

      if (path.isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
        });
        return;
      }

      if (_isNetworkPath(path)) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(path));
      } else {
        _controller = VideoPlayerController.file(File(path));
      }

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _isReady = true;
      });
    } catch (e) {
      debugPrint('VIDEO LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        _hasError = true;
      });
    }
  }

  void _toggle() {
    if (!_isReady || _controller == null) return;

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const _BrokenMediaBox(
        icon: Icons.videocam_off_rounded,
        text: 'Video not found',
      );
    }

    if (!_isReady || _controller == null) {
      return Container(
        width: 230,
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const CircularProgressIndicator(),
      );
    }

    return GestureDetector(
      onTap: _toggle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 230,
              height: 160,
              child: VideoPlayer(_controller!),
            ),
            if (!_controller!.value.isPlaying)
              const CircleAvatar(
                radius: 30,
                backgroundColor: Colors.black54,
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isDark;

  const _FileBubble({
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = message.fileName ?? 'File';

    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: message.isMe
            ? const Color(0xFF1877F2)
            : isDark
                ? const Color(0xFF1E293B)
                : const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(
              Icons.insert_drive_file_rounded,
              color: message.isMe ? const Color(0xFF1877F2) : Colors.black87,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: message.isMe
                    ? Colors.white
                    : isDark
                        ? Colors.white
                        : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrokenMediaBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BrokenMediaBox({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: Colors.black45),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
class _MediaAlbumBubble extends StatelessWidget {
  final ChatMessage message;

  const _MediaAlbumBubble({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final images = message.mediaUrls ?? [];

    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    if (images.length == 1) {
      return _ImageBubble(
        message: message.copyWith(
          filePath: images.first,
        ),
      );
    }

    final visible = images.take(4).toList();
    final extra = images.length - 4;

    Widget imageTile(
      String path,
      int index, {
      bool showOverlay = false,
    }) {
      final fixedPath = fixedMediaUrl(path);

      return GestureDetector(
        onTap: () {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            _isNetworkPath(fixedPath)
                ? Image.network(
                    fixedPath,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    File(fixedPath),
                    fit: BoxFit.cover,
                  ),
            if (showOverlay)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 240,
        height: 190,
        child: images.length == 2
            ? Row(
                children: [
                  Expanded(child: imageTile(visible[0], 0)),
                  const SizedBox(width: 2),
                  Expanded(child: imageTile(visible[1], 1)),
                ],
              )
            : images.length == 3
                ? Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: imageTile(visible[0], 0),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: imageTile(visible[1], 1),
                            ),
                            const SizedBox(height: 2),
                            Expanded(
                              child: imageTile(visible[2], 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: imageTile(visible[0], 0),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: imageTile(visible[1], 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: imageTile(visible[2], 2),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: imageTile(
                                visible[3],
                                3,
                                showOverlay: extra > 0,
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
}