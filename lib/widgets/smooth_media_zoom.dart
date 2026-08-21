import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// ===============================================================
/// SMOOTH MEDIA ZOOM
/// ===============================================================
///
/// Messenger / WhatsApp style:
///
/// - Smooth pinch zoom
/// - Smooth pinch zoom-out
/// - Slight elastic shrink below 1x
/// - Automatically returns to 1x
/// - Smooth double-tap zoom
/// - Double-tap again to zoom out
/// - Zoom around double-tapped position
/// - Smooth panning
/// - Momentum after pan
/// - Supports IMAGE
/// - Supports VIDEO
///
/// ===============================================================

class SmoothMediaZoom extends StatefulWidget {
  final Widget child;

  /// Called whenever zoom state changes.
  ///
  /// true  = media is zoomed
  /// false = normal 1x scale
  final ValueChanged<bool>? onZoomChanged;

  /// Reports the number of fingers currently touching this media.
  /// This lets the parent gallery immediately disable PageView
  /// as soon as a second finger touches the screen.
  final ValueChanged<int>? onPointerCountChanged;

  /// Minimum temporary scale while pinching inward.
  ///
  /// We intentionally allow less than 1.0 so it feels elastic.
  final double minScale;

  /// Maximum allowed zoom.
  final double maxScale;

  /// Scale used when double tapping.
  final double doubleTapScale;

  const SmoothMediaZoom({
    super.key,
    required this.child,
    this.onZoomChanged,
    this.onPointerCountChanged,
    this.minScale = 0.94,
    this.maxScale = 5.0,
    this.doubleTapScale = 2.5,
  });

  @override
  State<SmoothMediaZoom> createState() => _SmoothMediaZoomState();
}

class _SmoothMediaZoomState extends State<SmoothMediaZoom>
    with SingleTickerProviderStateMixin {
  // ===============================================================
  // CONTROLLERS
  // ===============================================================

  final TransformationController _transformationController =
      TransformationController();

  late final AnimationController _animationController;

  Animation<Matrix4>? _matrixAnimation;

  // ===============================================================
  // STATE
  // ===============================================================

  bool _isZoomed = false;
  bool _isInteracting = false;

  final Set<int> _activePointers = <int>{};

  TapDownDetails? _doubleTapDetails;

  // ===============================================================
  // INIT
  // ===============================================================

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _animationController.addListener(_animationListener);

    _transformationController.addListener(
      _handleTransformationChanged,
    );
  }

  // ===============================================================
  // CURRENT SCALE
  // ===============================================================

  double get _currentScale {
    return _transformationController.value.getMaxScaleOnAxis();
  }

  // ===============================================================
  // ANIMATION LISTENER
  // ===============================================================

  void _animationListener() {
    final animation = _matrixAnimation;

    if (animation == null) return;

    _transformationController.value = animation.value;
  }

  // ===============================================================
  // TRANSFORMATION LISTENER
  // ===============================================================

  void _handleTransformationChanged() {
    final scale = _currentScale;

    final nextZoomed = scale > 1.01;

    if (nextZoomed == _isZoomed) return;

    _isZoomed = nextZoomed;

    widget.onZoomChanged?.call(nextZoomed);

    if (mounted) {
      setState(() {});
    }
  }

  // ===============================================================
  // ANIMATE MATRIX
  // ===============================================================

  void _animateToMatrix(
    Matrix4 target, {
    Duration duration = const Duration(milliseconds: 320),
    Curve curve = Curves.easeOutQuart,
  }) {
    _animationController.stop();

    _animationController.duration = duration;

    _matrixAnimation = Matrix4Tween(
      begin: _transformationController.value.clone(),
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: curve,
      ),
    );

    _animationController
      ..reset()
      ..forward();
  }

  // ===============================================================
  // RESET ZOOM
  // ===============================================================

  void _resetZoom({
    bool spring = false,
  }) {
    _animateToMatrix(
      Matrix4.identity(),
      duration: Duration(
        milliseconds: spring ? 300 : 320,
      ),
      curve: spring
          ? Curves.easeOutBack
          : Curves.easeOutCubic,
    );
  }

  // ===============================================================
  // DOUBLE TAP DOWN
  // ===============================================================

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  // ===============================================================
  // DOUBLE TAP
  // ===============================================================

  void _handleDoubleTap() {
    final details = _doubleTapDetails;

    if (details == null) return;

    _animationController.stop();

    final scale = _currentScale;

    // -------------------------------------------------------------
    // Already zoomed
    // -------------------------------------------------------------

    if (scale > 1.05) {
      _resetZoom();
      return;
    }

    // -------------------------------------------------------------
    // Zoom into double-tapped point
    // -------------------------------------------------------------

    final position = details.localPosition;

    final targetScale = widget.doubleTapScale;

    final matrix = Matrix4.identity()
      ..translate(
        -position.dx * (targetScale - 1),
        -position.dy * (targetScale - 1),
      )
      ..scale(targetScale);

    _animateToMatrix(
      matrix,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutQuart,
    );
  }

  // ===============================================================
  // INTERACTION START
  // ===============================================================

  void _handleInteractionStart(
    ScaleStartDetails details,
  ) {
    // Stop double-tap/reset animation immediately when
    // the user puts their fingers back on the screen.
    _animationController.stop();

    if (_isInteracting) return;

    _isInteracting = true;

    if (mounted) {
      setState(() {});
    }
  }

  // ===============================================================
  // INTERACTION END
  // ===============================================================

  void _handleInteractionEnd(
    ScaleEndDetails details,
  ) {
    _isInteracting = false;

    if (mounted) {
      setState(() {});
    }

    final scale = _currentScale;

    // -------------------------------------------------------------
    // Elastic zoom-out
    // -------------------------------------------------------------
    //
    // User can temporarily shrink below normal size.
    //
    // When fingers are released it springs back naturally.
    // -------------------------------------------------------------

    if (scale < 1.0) {
      _resetZoom(
        spring: true,
      );

      return;
    }

    // -------------------------------------------------------------
    // Tiny accidental zoom
    // -------------------------------------------------------------

    if (scale < 1.06) {
      _animateToMatrix(
        Matrix4.identity(),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  void _notifyPointerCount() {
    widget.onPointerCountChanged?.call(_activePointers.length);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _notifyPointerCount();
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    _notifyPointerCount();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _notifyPointerCount();
  }

  // ===============================================================
  // BUILD
  // ===============================================================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,

        // -----------------------------------------------------------
        // DOUBLE TAP
        // -----------------------------------------------------------

        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,

        child: InteractiveViewer(
        transformationController:
            _transformationController,

        // ---------------------------------------------------------
        // ZOOM
        // ---------------------------------------------------------

        minScale: widget.minScale,
        maxScale: widget.maxScale,

        scaleEnabled: true,

        // DO NOT dynamically disable panning while gesture is active.
        //
        // Changing panEnabled based on scale during the same gesture
        // can make zoom/pan feel jerky.
        panEnabled: true,

        // ---------------------------------------------------------
        // MOMENTUM
        // ---------------------------------------------------------

        interactionEndFrictionCoefficient: 0.000018,

        // ---------------------------------------------------------
        // BOUNDARIES
        // ---------------------------------------------------------

        boundaryMargin: EdgeInsets.symmetric(
          horizontal: size.width * 0.35,
          vertical: size.height * 0.35,
        ),

        clipBehavior: Clip.none,

        // ---------------------------------------------------------
        // INTERACTION
        // ---------------------------------------------------------

        onInteractionStart:
            _handleInteractionStart,

        onInteractionEnd:
            _handleInteractionEnd,

          child: widget.child,
        ),
      ),
    );
  }

  // ===============================================================
  // DISPOSE
  // ===============================================================

  @override
  void dispose() {
    _animationController
      ..removeListener(_animationListener)
      ..dispose();

    _transformationController
      ..removeListener(
        _handleTransformationChanged,
      )
      ..dispose();

    super.dispose();
  }
}

/// ===============================================================
/// SMOOTH IMAGE VIEWER
/// ===============================================================

class SmoothZoomImage extends StatelessWidget {
  final String path;

  final BoxFit fit;

  final ValueChanged<bool>? onZoomChanged;
  final ValueChanged<int>? onPointerCountChanged;

  const SmoothZoomImage({
    super.key,
    required this.path,
    this.fit = BoxFit.contain,
    this.onZoomChanged,
    this.onPointerCountChanged,
  });

  bool get _isNetwork {
    final value = path.trim().toLowerCase();

    return value.startsWith('http://') ||
        value.startsWith('https://');
  }

  String get _resolvedLocalPath {
    final value = path.trim();

    if (value.startsWith('file://')) {
      return Uri.parse(value).toFilePath();
    }

    return value;
  }

  // ===============================================================
  // BROKEN IMAGE
  // ===============================================================

  Widget _brokenImage() {
    return const Center(
      child: Icon(
        Icons.broken_image_rounded,
        color: Colors.white70,
        size: 48,
      ),
    );
  }

  // ===============================================================
  // IMAGE
  // ===============================================================

  Widget _buildImage() {
    if (_isNetwork) {
      return Image.network(
        path,
        fit: fit,

        gaplessPlayback: true,

        filterQuality: FilterQuality.medium,

        loadingBuilder: (
          context,
          child,
          loadingProgress,
        ) {
          if (loadingProgress == null) {
            return child;
          }

          return const Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          );
        },

        errorBuilder: (_, __, ___) {
          return _brokenImage();
        },
      );
    }

    return Image.file(
      File(_resolvedLocalPath),
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) {
        return _brokenImage();
      },
    );
  }

  // ===============================================================
  // BUILD
  // ===============================================================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return SmoothMediaZoom(
      onZoomChanged: onZoomChanged,
      onPointerCountChanged: onPointerCountChanged,

      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Center(
          child: _buildImage(),
        ),
      ),
    );
  }
}

/// ===============================================================
/// SMOOTH VIDEO VIEWER
/// ===============================================================

class SmoothZoomVideo extends StatefulWidget {
  final String videoPath;

  final bool autoPlay;

  final bool looping;

  final ValueChanged<bool>? onZoomChanged;

  const SmoothZoomVideo({
    super.key,
    required this.videoPath,
    this.autoPlay = true,
    this.looping = false,
    this.onZoomChanged,
  });

  @override
  State<SmoothZoomVideo> createState() =>
      _SmoothZoomVideoState();
}

class _SmoothZoomVideoState
    extends State<SmoothZoomVideo> {
  VideoPlayerController? _videoController;

  bool _initializing = true;

  String? _error;

  bool _showControls = true;

  // ===============================================================
  // NETWORK CHECK
  // ===============================================================

  bool get _isNetwork {
    final value =
        widget.videoPath.trim().toLowerCase();

    return value.startsWith('http://') ||
        value.startsWith('https://');
  }

  // ===============================================================
  // LOCAL PATH
  // ===============================================================

  String get _localPath {
    final value = widget.videoPath.trim();

    if (value.startsWith('file://')) {
      return Uri.parse(value).toFilePath();
    }

    return value;
  }

  // ===============================================================
  // INIT
  // ===============================================================

  @override
  void initState() {
    super.initState();

    _initializeVideo();
  }

  // ===============================================================
  // VIDEO INITIALIZATION
  // ===============================================================

  Future<void> _initializeVideo() async {
    try {
      final VideoPlayerController controller;

      if (_isNetwork) {
        controller =
            VideoPlayerController.networkUrl(
          Uri.parse(widget.videoPath),
        );
      } else {
        controller =
            VideoPlayerController.file(
          File(_localPath),
        );
      }

      _videoController = controller;

      await controller.initialize();

      await controller.setLooping(
        widget.looping,
      );

      if (widget.autoPlay) {
        await controller.play();
      }

      if (!mounted) return;

      setState(() {
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _initializing = false;
        _error = e.toString();
      });
    }
  }

  // ===============================================================
  // PLAY PAUSE
  // ===============================================================

  Future<void> _togglePlay() async {
    final controller = _videoController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ===============================================================
  // ZOOM CHANGE
  // ===============================================================

  void _handleZoomChanged(bool zoomed) {
    widget.onZoomChanged?.call(zoomed);

    // Hide controls when heavily interacting with zoom.
    if (zoomed && _showControls) {
      setState(() {
        _showControls = false;
      });
    }
  }

  // ===============================================================
  // VIDEO
  // ===============================================================

  Widget _buildVideo() {
    final controller = _videoController;

    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    if (_error != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Colors.white70,
              size: 48,
            ),
            SizedBox(height: 12),
            Text(
              'Could not play video',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    final aspectRatio =
        controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9;

    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  // ===============================================================
  // CONTROLS
  // ===============================================================

  Widget _buildControls() {
    final controller = _videoController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_showControls,
        child: AnimatedOpacity(
          duration:
              const Duration(milliseconds: 180),
          opacity: _showControls ? 1 : 0,

          child: Center(
            child: GestureDetector(
              onTap: _togglePlay,

              child: Container(
                width: 64,
                height: 64,

                decoration: BoxDecoration(
                  color:
                      Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),

                child: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===============================================================
  // BUILD
  // ===============================================================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      // -----------------------------------------------------------
      // Single tap toggles controls
      // -----------------------------------------------------------

      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },

      child: Stack(
        fit: StackFit.expand,
        children: [
          // -------------------------------------------------------
          // VIDEO + ZOOM
          // -------------------------------------------------------

          SmoothMediaZoom(
            onZoomChanged:
                _handleZoomChanged,

            child: SizedBox(
              width: size.width,
              height: size.height,
              child: _buildVideo(),
            ),
          ),

          // -------------------------------------------------------
          // PLAY / PAUSE
          // -------------------------------------------------------

          _buildControls(),

          // -------------------------------------------------------
          // VIDEO PROGRESS
          // -------------------------------------------------------

          if (_videoController != null &&
              _videoController!
                  .value.isInitialized)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: AnimatedOpacity(
                duration:
                    const Duration(
                  milliseconds: 180,
                ),
                opacity:
                    _showControls ? 1 : 0,
                child: VideoProgressIndicator(
                  _videoController!,
                  allowScrubbing: true,
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  colors:
                      const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor:
                        Colors.white38,
                    backgroundColor:
                        Colors.white24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===============================================================
  // DISPOSE
  // ===============================================================

  @override
  void dispose() {
    _videoController?.dispose();

    super.dispose();
  }
}