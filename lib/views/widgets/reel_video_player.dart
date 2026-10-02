import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';


class ReelVideoPlayer extends StatefulWidget {
  final String? videoUrl;
  final File? videoFile;
  final double maxHeight;
  final bool autoPlay;
  final bool isLooping;
  final VoidCallback? onRemove;

  const ReelVideoPlayer({
    super.key,
    this.videoUrl,
    this.videoFile,
    this.maxHeight = 440,
    this.autoPlay = true,
    this.isLooping = true,
    this.onRemove,
  }) : assert(videoUrl != null || videoFile != null,
            'Either videoUrl or videoFile must be provided');

  @override
  State<ReelVideoPlayer> createState() => _ReelVideoPlayerState();
}

class _ReelVideoPlayerState extends State<ReelVideoPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isMuted = false;
  bool _showPlayPauseOverlay = false;
  late AnimationController _animController;
  late Animation<double> _animScale;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _animScale = Tween<double>(begin: 0.6, end: 1.2).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _initVideoPlayer();
  }

  @override
  void didUpdateWidget(covariant ReelVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.videoFile?.path != widget.videoFile?.path) {
      _disposeController();
      _initVideoPlayer();
    }
  }

  Future<void> _initVideoPlayer() async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      if (widget.videoFile != null) {
        _controller = VideoPlayerController.file(widget.videoFile!);
      } else if (widget.videoUrl != null) {
        final url = widget.videoUrl!;
        if (url.startsWith('http://') || url.startsWith('https://')) {
          _controller = VideoPlayerController.networkUrl(Uri.parse(url));
        } else {
          _controller = VideoPlayerController.file(File(url));
        }
      }

      if (_controller == null) return;

      await _controller!.initialize();
      if (!mounted) return;

      if (widget.isLooping) {
        await _controller!.setLooping(true);
      }
      await _controller!.setVolume(_isMuted ? 0.0 : 1.0);

      if (widget.autoPlay) {
        await _controller!.play();
      }

      setState(() {
        _isInitialized = true;
      });

      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Could not load video: $e';
      });
    }
  }

  void _disposeController() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _animController.dispose();
    _disposeController();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    _triggerOverlayAnimation();
  }

  void _triggerOverlayAnimation() {
    _animController.forward(from: 0.0);
    setState(() => _showPlayPauseOverlay = true);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) {
        setState(() => _showPlayPauseOverlay = false);
      }
    });
  }

  void _toggleMute() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  Future<void> _openFullScreen() async {
    if (_controller == null || !_isInitialized) return;
    final wasPlaying = _controller!.value.isPlaying;
    final currentPos = _controller!.value.position;
    _controller!.pause();

    final returnPos = await Navigator.of(context).push<Duration>(
      MaterialPageRoute(
        builder: (_) => FullScreenVideoPage(
          videoUrl: widget.videoUrl,
          videoFile: widget.videoFile,
          initialPosition: currentPos,
          initialIsMuted: _isMuted,
          isLooping: widget.isLooping,
        ),
      ),
    );

    if (!mounted || _controller == null) return;
    if (returnPos != null) {
      await _controller!.seekTo(returnPos);
    }
    if (wasPlaying) {
      await _controller!.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      final isChannelError = _errorMessage.contains('channel-error') ||
          _errorMessage.contains('VideoPlayerApi') ||
          _errorMessage.contains('pigeon');

      final displayMsg = isChannelError
          ? 'Native video engine requires a full app restart (flutter run rebuild) after plugin installation.'
          : _errorMessage;

      return Container(
        constraints: const BoxConstraints(minHeight: 140),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off_rounded,
                    color: Colors.redAccent, size: 24),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Video Reel Unavailable',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (widget.onRemove != null) ...[
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.white70),
                    onPressed: widget.onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              displayMsg,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 11,
                color: Colors.white70,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: _initVideoPlayer,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded,
                      size: 14, color: Colors.white),
                  label: Text(
                    'Retry',
                    style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
                if (widget.videoUrl != null &&
                    widget.videoUrl!.startsWith('http'))
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        final uri = Uri.parse(widget.videoUrl!);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      } catch (_) {}
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      backgroundColor:
                          const Color(0xFF673AB7).withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded,
                        size: 14, color: Colors.white),
                    label: Text(
                      'Open in Player',
                      style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        height: 260,
        decoration: BoxDecoration(
          color: const Color(0xFF121217),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF673AB7),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading Reel Clip 🎬...',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final val = _controller!.value;
    final isPlaying = val.isPlaying;
    final duration = val.duration;
    final position = val.position;
    final progressRatio = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [

          GestureDetector(
            onTap: _togglePlayPause,
            child: AspectRatio(
              aspectRatio: val.aspectRatio > 0 ? val.aspectRatio : 9 / 16,
              child: VideoPlayer(_controller!),
            ),
          ),


          if (_showPlayPauseOverlay)
            IgnorePointer(
              child: ScaleTransition(
                scale: _animScale,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),


          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                const Spacer(),

                GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      _isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                GestureDetector(
                  onTap: _openFullScreen,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: const Icon(
                      Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                if (widget.onRemove != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),


          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 4,
              color: Colors.white.withValues(alpha: 0.25),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progressRatio,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF9C27B0), Color(0xFF673AB7)],
                      ),
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


class FullScreenVideoPage extends StatefulWidget {
  final String? videoUrl;
  final File? videoFile;
  final Duration initialPosition;
  final bool initialIsMuted;
  final bool isLooping;

  const FullScreenVideoPage({
    super.key,
    this.videoUrl,
    this.videoFile,
    this.initialPosition = Duration.zero,
    this.initialIsMuted = false,
    this.isLooping = true,
  }) : assert(videoUrl != null || videoFile != null,
            'Either videoUrl or videoFile must be provided');

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  late bool _isMuted;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isDraggingSlider = false;
  double _dragSliderValue = 0.0;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.initialIsMuted;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      if (widget.videoFile != null) {
        _controller = VideoPlayerController.file(widget.videoFile!);
      } else if (widget.videoUrl != null) {
        final url = widget.videoUrl!;
        if (url.startsWith('http://') || url.startsWith('https://')) {
          _controller = VideoPlayerController.networkUrl(Uri.parse(url));
        } else {
          _controller = VideoPlayerController.file(File(url));
        }
      }

      if (_controller == null) return;

      await _controller!.initialize();
      if (!mounted) return;

      if (widget.isLooping) {
        await _controller!.setLooping(true);
      }
      await _controller!.setVolume(_isMuted ? 0.0 : 1.0);
      if (widget.initialPosition > Duration.zero) {
        await _controller!.seekTo(widget.initialPosition);
      }
      await _controller!.play();

      setState(() {
        _isInitialized = true;
      });

      _startHideTimer();

      _controller!.addListener(() {
        if (mounted && !_isDraggingSlider) {
          setState(() {});
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Could not play video in full screen: $e';
      });
    }
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _controller != null &&
          _controller!.value.isPlaying &&
          !_isDraggingSlider) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _showControls = true);
    } else {
      _controller!.play();
      _startHideTimer();
    }
    setState(() {});
  }

  void _toggleMute() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _exitFullScreen() {
    final pos = _controller?.value.position ?? widget.initialPosition;
    Navigator.of(context).pop(pos);
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitFullScreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [

              if (_isInitialized && _controller != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio > 0
                        ? _controller!.value.aspectRatio
                        : 9 / 16,
                    child: VideoPlayer(_controller!),
                  ),
                )
              else if (_hasError)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage,
                          style: GoogleFonts.nunito(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _exitFullScreen,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Back'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFAB47BC),
                  ),
                ),


              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: _togglePlayPause,
                  child: const SizedBox.expand(),
                ),
              ),


              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Stack(
                    children: [

                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white, size: 24),
                                onPressed: _exitFullScreen,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Rescue Reel Clip',
                                  style: GoogleFonts.nunito(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _isMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: _toggleMute,
                              ),
                            ],
                          ),
                        ),
                      ),


                      if (_isInitialized && _controller != null)
                        Center(
                          child: GestureDetector(
                            onTap: _togglePlayPause,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _controller!.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                        ),


                      if (_isInitialized && _controller != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.85),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _formatDuration(_isDraggingSlider
                                          ? Duration(
                                              seconds:
                                                  _dragSliderValue.toInt())
                                          : _controller!.value.position),
                                      style: GoogleFonts.nunito(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3.5,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                  enabledThumbRadius: 6),
                                          activeTrackColor:
                                              const Color(0xFFAB47BC),
                                          inactiveTrackColor: Colors.white
                                              .withValues(alpha: 0.3),
                                          thumbColor: Colors.white,
                                          overlayColor: const Color(0xFFAB47BC)
                                              .withValues(alpha: 0.2),
                                        ),
                                        child: Slider(
                                          min: 0.0,
                                          max: _controller!
                                              .value.duration.inSeconds
                                              .toDouble()
                                              .clamp(1.0, double.infinity),
                                          value: (_isDraggingSlider
                                                  ? _dragSliderValue
                                                  : _controller!
                                                      .value.position.inSeconds
                                                      .toDouble())
                                              .clamp(
                                                  0.0,
                                                  _controller!
                                                      .value.duration.inSeconds
                                                      .toDouble()
                                                      .clamp(
                                                          1.0,
                                                          double
                                                              .infinity)),
                                          onChangeStart: (val) {
                                            setState(() {
                                              _isDraggingSlider = true;
                                              _dragSliderValue = val;
                                            });
                                          },
                                          onChanged: (val) {
                                            setState(() {
                                              _dragSliderValue = val;
                                            });
                                          },
                                          onChangeEnd: (val) {
                                            _controller!.seekTo(Duration(
                                                seconds: val.toInt()));
                                            setState(() {
                                              _isDraggingSlider = false;
                                            });
                                            _startHideTimer();
                                          },
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(
                                          _controller!.value.duration),
                                      style: GoogleFonts.nunito(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.fullscreen_exit_rounded,
                                          color: Colors.white,
                                          size: 24),
                                      onPressed: _exitFullScreen,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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

