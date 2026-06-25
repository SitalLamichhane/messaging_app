

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hiddenly/chat_models.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:photo_view/photo_view.dart';
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

  if (decoded.startsWith('media/')) {
    return '$baseServerUrl/$decoded';
  }

  if (decoded.startsWith('/')) {
    return '$baseServerUrl$decoded';
  }

  return decoded;
}

bool _isNetworkPath(String path) {
  final cleanPath = path.trim().toLowerCase();
  return cleanPath.startsWith('http://') || cleanPath.startsWith('https://');
}

bool _looksLikeImagePath(String value) {
  final path = value.toLowerCase().split('?').first.split('#').first;
  return path.endsWith('.jpg') ||
      path.endsWith('.jpeg') ||
      path.endsWith('.png') ||
      path.endsWith('.webp') ||
      path.endsWith('.gif') ||
      path.endsWith('.heic') ||
      path.endsWith('.heif');
}

bool _looksLikeVideoPath(String value) {
  final path = value.toLowerCase().split('?').first.split('#').first;
  return path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm') ||
      path.endsWith('.avi') ||
      path.endsWith('.mkv') ||
      path.endsWith('.3gp');
}

bool _looksLikeAudioPath(String value) {
  final path = value.toLowerCase().split('?').first.split('#').first;
  return path.endsWith('.mp3') ||
      path.endsWith('.m4a') ||
      path.endsWith('.aac') ||
      path.endsWith('.wav') ||
      path.endsWith('.ogg') ||
      path.endsWith('.opus') ||
      path.endsWith('.amr');
}

String _fileExtension(String value) {
  final clean = value.split('?').first.split('#').first;
  final name = clean.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot == -1 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toUpperCase();
}

String _fileNameFromPath(String value, String fallback) {
  final clean = value.split('?').first.split('#').first;
  final name = clean.replaceAll('\\', '/').split('/').last.trim();
  return name.isEmpty ? fallback : name;
}

void _showMediaSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1400),
    ),
  );
}

enum _ViewerMediaType {
  image,
  video,
}

class _ViewerMedia {
  final String path;
  final _ViewerMediaType type;
  final String heroTag;

  const _ViewerMedia({
    required this.path,
    required this.type,
    required this.heroTag,
  });

  bool get isNetwork => _isNetworkPath(path);
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
        return _MediaAlbumBubble(message: message);

      case MessageType.video:
        return _VideoBubble(message: message);

      case MessageType.audio:
        return _AudioBubble(message: message);

      case MessageType.file:
        return _FileBubble(message: message, isDark: isDark);

      default:
        return const SizedBox.shrink();
    }
  }
}

void _openMediaViewer(
  BuildContext context, {
  required List<_ViewerMedia> items,
  int initialIndex = 0,
}) {
  final cleanItems = items.where((item) => item.path.trim().isNotEmpty).toList();
  if (cleanItems.isEmpty) return;

  final safeInitialIndex = initialIndex.clamp(0, cleanItems.length - 1);

  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _MessengerFullScreenMediaViewer(
        items: cleanItems,
        initialIndex: safeInitialIndex,
      ),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: child,
        );
      },
    ),
  );
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

    final heroTag = 'image_${message.id}_${path.hashCode}';

    final imageWidget = _isNetworkPath(path)
        ? Image.network(
            path,
            width: 230,
            height: 280,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
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
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) {
              return const _BrokenMediaBox(
                icon: Icons.broken_image_rounded,
                text: 'Image not found',
              );
            },
          );

    return GestureDetector(
      onTap: () {
        _openMediaViewer(
          context,
          items: [
            _ViewerMedia(
              path: path,
              type: _ViewerMediaType.image,
              heroTag: heroTag,
            ),
          ],
        );
      },
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: imageWidget,
        ),
      ),
    );
  }
}

class _MessengerFullScreenMediaViewer extends StatefulWidget {
  final List<_ViewerMedia> items;
  final int initialIndex;

  const _MessengerFullScreenMediaViewer({
    required this.items,
    required this.initialIndex,
  });

  @override
  State<_MessengerFullScreenMediaViewer> createState() =>
      _MessengerFullScreenMediaViewerState();
}

class _MessengerFullScreenMediaViewerState
    extends State<_MessengerFullScreenMediaViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _showBars = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  Widget _buildPage(_ViewerMedia item) {
    if (item.type == _ViewerMediaType.video) {
      return _FullScreenVideoPage(
        path: item.path,
        isNetwork: item.isNetwork,
        onToggleBars: () {
          setState(() => _showBars = !_showBars);
        },
      );
    }

    return _FullScreenImagePage(
      path: item.path,
      isNetwork: item.isNetwork,
      heroTag: item.heroTag,
      onToggleBars: () {
        setState(() => _showBars = !_showBars);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return _buildPage(widget.items[index]);
              },
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            top: _showBars ? topPadding + 6 : -76,
            left: 6,
            right: 6,
            child: Row(
              children: [
                IconButton(
                  onPressed: _close,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const Spacer(),
                if (widget.items.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.items.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: _showBars ? bottomPadding + 16 : -70,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.items[_currentIndex].type == _ViewerMediaType.video
                        ? 'Pinch to zoom • Drag to move • Tap controls'
                        : 'Pinch to zoom • Double tap to zoom • Drag to move',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenImagePage extends StatelessWidget {
  final String path;
  final bool isNetwork;
  final String heroTag;
  final VoidCallback onToggleBars;

  const _FullScreenImagePage({
    required this.path,
    required this.isNetwork,
    required this.heroTag,
    required this.onToggleBars,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider imageProvider =
        isNetwork ? NetworkImage(path) : FileImage(File(path));

    return GestureDetector(
      onTap: onToggleBars,
      child: PhotoView(
        imageProvider: imageProvider,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        initialScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4.0,
        enablePanAlways: true,
        strictScale: false,
        heroAttributes: PhotoViewHeroAttributes(tag: heroTag),
        loadingBuilder: (context, event) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(
              Icons.broken_image_rounded,
              color: Colors.white,
              size: 54,
            ),
          );
        },
      ),
    );
  }
}

class _FullScreenVideoPage extends StatefulWidget {
  final String path;
  final bool isNetwork;
  final VoidCallback onToggleBars;

  const _FullScreenVideoPage({
    required this.path,
    required this.isNetwork,
    required this.onToggleBars,
  });

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  VideoPlayerController? _controller;

  bool _isReady = false;
  bool _hasError = false;
  bool _userPaused = true;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      if (widget.path.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _hasError = true);
        return;
      }

      if (widget.isNetwork) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.path));
      } else {
        _controller = VideoPlayerController.file(File(widget.path));
      }

      await _controller!.initialize();
      await _controller!.setLooping(false);
      _controller!.addListener(_videoListener);

      if (!mounted) return;

      setState(() {
        _isReady = true;
        _userPaused = true;
      });
    } catch (e) {
      debugPrint('FULLSCREEN VIDEO LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        _hasError = true;
      });
    }
  }

  void _videoListener() {
    if (!mounted) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final value = controller.value;
    final isCompleted = value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;

    if (isCompleted) {
      _userPaused = true;
    }

    setState(() {});
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !_isReady) return;

    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      await controller.seekTo(Duration.zero);
    }

    if (controller.value.isPlaying) {
      _userPaused = true;
      await controller.pause();
    } else {
      _userPaused = false;
      await controller.play();
    }

    if (mounted) setState(() {});
  }

  Future<void> _seekRelative(Duration delta) async {
    final controller = _controller;
    if (controller == null || !_isReady) return;

    final current = controller.value.position;
    final duration = controller.value.duration;

    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    await controller.seekTo(target);
  }

  String _formatVideoTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) return '$hours:$minutes:$seconds';

    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(
          Icons.videocam_off_rounded,
          color: Colors.white,
          size: 60,
        ),
      );
    }

    if (!_isReady || _controller == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.white),
      );
    }

    final controller = _controller!;
    final value = controller.value;
    final duration = value.duration;
    final position = value.position;
    final isBuffering = value.isBuffering;
    final showPlayButton = !value.isPlaying && !isBuffering;

    final videoChild = Center(
      child: AspectRatio(
        aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onToggleBars,
            child: PhotoView.customChild(
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              initialScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3.5,
              enablePanAlways: true,
              strictScale: false,
              childSize: MediaQuery.of(context).size,
              child: videoChild,
            ),
          ),
        ),

        if (isBuffering)
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.48),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ),

        if (showPlayButton)
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.52),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),

        Positioned(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 50,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.48),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _seekRelative(const Duration(seconds: -10)),
                      child: const Icon(
                        Icons.replay_10_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _seekRelative(const Duration(seconds: 10)),
                      child: const Icon(
                        Icons.forward_10_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${_formatVideoTime(position)} / ${_formatVideoTime(duration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (isBuffering) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
  bool _showControls = true;
  bool _userPaused = true;

  String _path = '';

  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _initPreview();
  }

  Future<void> _initPreview() async {
    try {
      final path = fixedMediaUrl(widget.message.filePath);

      if (path.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
        });
        return;
      }

      _path = path;

      if (_isNetworkPath(path)) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(path));
      } else {
        _controller = VideoPlayerController.file(File(path));
      }

      await _controller!.initialize();
      await _controller!.setLooping(false);

      if (!mounted) return;

      _controller!.addListener(_previewListener);

      setState(() {
        _isReady = true;
        _userPaused = true;
        _showControls = true;
      });
    } catch (e) {
      debugPrint('VIDEO PREVIEW LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        _hasError = true;
      });
    }
  }

  void _previewListener() {
    if (!mounted) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final value = controller.value;

    final isCompleted = value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;

    if (isCompleted) {
      _showControls = true;
      _userPaused = true;
      _controlsTimer?.cancel();
    }

    setState(() {});
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();

    final controller = _controller;
    if (controller == null || !controller.value.isPlaying) return;

    _controlsTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final c = _controller;
      if (c == null || !c.value.isPlaying) return;

      setState(() {
        _showControls = false;
      });
    });
  }

  Future<void> _playOrPauseInline() async {
    final controller = _controller;
    if (controller == null || !_isReady) return;

    HapticFeedback.lightImpact();

    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      await controller.seekTo(Duration.zero);
    }

    if (controller.value.isPlaying) {
      _userPaused = true;
      await controller.pause();
      _controlsTimer?.cancel();

      if (mounted) {
        setState(() {
          _showControls = true;
        });
      }
      return;
    }

    _userPaused = false;
    await controller.play();

    if (mounted) {
      setState(() {
        _showControls = true;
      });
    }

    _startControlsTimer();
  }

  void _openFullScreenVideo() {
    if (_path.trim().isEmpty) return;

    HapticFeedback.lightImpact();

    _controller?.pause();
    _userPaused = true;
    _controlsTimer?.cancel();

    if (mounted) {
      setState(() {
        _showControls = true;
      });
    }

    _openMediaViewer(
      context,
      items: [
        _ViewerMedia(
          path: _path,
          type: _ViewerMediaType.video,
          heroTag: 'video_${widget.message.id}_${_path.hashCode}',
        ),
      ],
    );
  }

  void _handleVideoSurfaceTap() {
    final controller = _controller;

    if (controller == null || !_isReady) return;

    if (controller.value.isPlaying && !controller.value.isBuffering) {
      _openFullScreenVideo();
    } else {
      _playOrPauseInline();
    }
  }

  Future<void> _seekInline(Duration delta) async {
    final controller = _controller;
    if (controller == null || !_isReady) return;

    final duration = controller.value.duration;
    var target = controller.value.position + delta;

    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    await controller.seekTo(target);

    _startControlsTimer();
  }

  String _formatVideoTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) return '$hours:$minutes:$seconds';

    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller?.removeListener(_previewListener);
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
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 230,
          height: 160,
          color: Colors.black,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.6,
          ),
        ),
      );
    }

    final controller = _controller!;
    final value = controller.value;
    final duration = value.duration;
    final position = value.position;
    final durationText = duration == Duration.zero ? '' : _formatVideoTime(duration);
    final positionText = _formatVideoTime(position);
    final isPlaying = value.isPlaying;
    final isBuffering = value.isBuffering;

    final showBigButton = (!isPlaying && !isBuffering) || _showControls;

    return Hero(
      tag: 'video_${widget.message.id}_${_path.hashCode}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 230,
          height: 160,
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleVideoSurfaceTap,
                  onDoubleTap: _openFullScreenVideo,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: value.size.width <= 0 ? 230 : value.size.width,
                      height: value.size.height <= 0 ? 160 : value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showControls || !isPlaying || isBuffering ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.05),
                            Colors.black.withOpacity(0.38),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (isBuffering)
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.48),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),

              if (showBigButton && !isBuffering)
                AnimatedScale(
                  scale: isPlaying ? 0.92 : 1,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  child: GestureDetector(
                    onTap: _playOrPauseInline,
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.52),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.24),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                ),

              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: AnimatedOpacity(
                  opacity: _showControls || !isPlaying || isBuffering ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _playOrPauseInline,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.58),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              if (durationText.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Text(
                                  isPlaying || isBuffering
                                      ? '$positionText / $durationText'
                                      : durationText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                              if (isBuffering) ...[
                                const SizedBox(width: 5),
                                const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 1.8,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isPlaying || isBuffering) ...[
                        GestureDetector(
                          onTap: () => _seekInline(const Duration(seconds: -10)),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.50),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.replay_10_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      GestureDetector(
                        onTap: _openFullScreenVideo,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.58),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(
                            Icons.fullscreen_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ],
          ),
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

  IconData _iconForFile(String pathOrName) {
    if (_looksLikeImagePath(pathOrName)) return Icons.image_rounded;
    if (_looksLikeVideoPath(pathOrName)) return Icons.play_circle_fill_rounded;
    if (_looksLikeAudioPath(pathOrName)) return Icons.audiotrack_rounded;

    final ext = _fileExtension(pathOrName).toLowerCase();

    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (ext == 'doc' || ext == 'docx') return Icons.description_rounded;
    if (ext == 'xls' || ext == 'xlsx' || ext == 'csv') {
      return Icons.table_chart_rounded;
    }
    if (ext == 'ppt' || ext == 'pptx') return Icons.slideshow_rounded;
    if (ext == 'zip' || ext == 'rar' || ext == '7z') {
      return Icons.folder_zip_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  String _subtitleForFile(String pathOrName) {
    if (_looksLikeImagePath(pathOrName)) return 'Tap to view photo';
    if (_looksLikeVideoPath(pathOrName)) return 'Tap to play video';
    if (_looksLikeAudioPath(pathOrName)) return 'Tap to copy audio link';

    final ext = _fileExtension(pathOrName);
    if (ext.isEmpty) return 'Tap to copy file link';

    return '$ext file • Tap to copy link';
  }

  Future<void> _handleTap(
    BuildContext context,
    String path,
    String fileName,
  ) async {
    if (path.trim().isEmpty) {
      _showMediaSnack(context, 'File not found');
      return;
    }

    if (_looksLikeImagePath(path) || _looksLikeImagePath(fileName)) {
      _openMediaViewer(
        context,
        items: [
          _ViewerMedia(
            path: path,
            type: _ViewerMediaType.image,
            heroTag: 'file_image_${path.hashCode}',
          ),
        ],
      );
      return;
    }

    if (_looksLikeVideoPath(path) || _looksLikeVideoPath(fileName)) {
      _openMediaViewer(
        context,
        items: [
          _ViewerMedia(
            path: path,
            type: _ViewerMediaType.video,
            heroTag: 'file_video_${path.hashCode}',
          ),
        ],
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: path));

    _showMediaSnack(context, 'File link copied');
  }

  @override
  Widget build(BuildContext context) {
    final rawPath = (message.filePath ?? message.audioPath ?? '').trim();
    final path = fixedMediaUrl(rawPath);
    final fileName = (message.fileName?.trim().isNotEmpty ?? false)
        ? message.fileName!.trim()
        : _fileNameFromPath(path, 'File');

    final isMe = message.isMe;
    final bgColor = isMe
        ? const Color(0xFF1877F2)
        : isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFEFEFF4);
    final textColor = isMe
        ? Colors.white
        : isDark
            ? Colors.white
            : Colors.black87;
    final subColor = isMe
        ? Colors.white.withOpacity(0.78)
        : isDark
            ? const Color(0xFFCBD5E1)
            : const Color(0xFF6B7280);

    final displayForType = path.isNotEmpty ? path : fileName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context, path, fileName),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 6),
              bottomRight: Radius.circular(isMe ? 6 : 18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color:
                      isMe ? Colors.white.withOpacity(0.22) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _iconForFile(displayForType),
                  color: isMe ? Colors.white : const Color(0xFF1877F2),
                  size: 25,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitleForFile(displayForType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: subColor,
                size: 22,
              ),
            ],
          ),
        ),
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

  void _openAlbumViewer(
    BuildContext context,
    List<String> images,
    int initialIndex,
  ) {
    final items = <_ViewerMedia>[];

    for (var i = 0; i < images.length; i++) {
      final path = fixedMediaUrl(images[i]);
      if (path.trim().isEmpty) continue;

      items.add(
        _ViewerMedia(
          path: path,
          type: _ViewerMediaType.image,
          heroTag: 'album_${message.id}_${i}_${path.hashCode}',
        ),
      );
    }

    _openMediaViewer(
      context,
      items: items,
      initialIndex: initialIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = (message.mediaUrls ?? [])
        .map(fixedMediaUrl)
        .where((path) => path.trim().isNotEmpty)
        .toList();

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
      return GestureDetector(
        onTap: () {
          _openAlbumViewer(context, images, index);
        },
        child: Hero(
          tag: 'album_${message.id}_${index}_${path.hashCode}',
          child: Stack(
            fit: StackFit.expand,
            children: [
              _isNetworkPath(path)
                  ? Image.network(
                      path,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) {
                        return const _BrokenMediaBox(
                          icon: Icons.broken_image_rounded,
                          text: 'Image not found',
                        );
                      },
                    )
                  : Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) {
                        return const _BrokenMediaBox(
                          icon: Icons.broken_image_rounded,
                          text: 'Image not found',
                        );
                      },
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
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 244,
        height: 196,
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
