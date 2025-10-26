import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'video_upload_ui.dart';
import 'vertical_indicator.dart';
import 'loading_overlay.dart';
import '../fluent_ui/fluent_loading_overlay.dart';
import '../fluent_ui/fluent_right_edge_menu.dart';
import '../danmaku_overlay.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'brightness_gesture_area.dart';
import 'volume_gesture_area.dart';
import 'blur_dialog.dart';
import 'right_edge_hover_menu.dart';
import 'minimal_progress_bar.dart';
import 'danmaku_density_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/manual_danmaku_matcher.dart';

class VideoPlayerUI extends StatefulWidget {
  const VideoPlayerUI({super.key});

  @override
  State<VideoPlayerUI> createState() => _VideoPlayerUIState();
}

class _VideoPlayerUIState extends State<VideoPlayerUI> {
  final FocusNode _focusNode = FocusNode();
  final bool _isIndicatorHovered = false;
  Timer? _doubleTapTimer;
  Timer? _mouseMoveTimer;
  int _tapCount = 0;
  static const _doubleTapTimeout = Duration(milliseconds: 200);
  static const _mouseHideDelay = Duration(seconds: 3);
  bool _isProcessingTap = false;
  bool _isMouseVisible = true;
  bool _isHorizontalDragging = false;

  // <<< ADDED: Hold a reference to VideoPlayerState for managing the callback
  VideoPlayerState? _videoPlayerStateInstance;
  String? _currentAnimeCoverUrl; // 当前番剧封面URL
  int? _lastAnimeId; // 上次获取封面的番剧ID，用于避免重复请求

  // 获取番剧封面URL
  Future<String?> _getAnimeCoverUrl(int? animeId) async {
    if (animeId == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      const prefsKeyPrefix = 'media_library_image_url_';
      return prefs.getString('$prefsKeyPrefix$animeId');
    } catch (e) {
      debugPrint('获取番剧封面失败: $e');
      return null;
    }
  }

  // 更新封面URL（如果番剧ID变化）
  void _updateAnimeCoverUrl(int? animeId) async {
    if (animeId != _lastAnimeId) {
      _lastAnimeId = animeId;
      final coverUrl = await _getAnimeCoverUrl(animeId);
      if (mounted && coverUrl != _currentAnimeCoverUrl) {
        setState(() {
          _currentAnimeCoverUrl = coverUrl;
        });
      }
    }
  }

  double getFontSize(VideoPlayerState videoState) {
    return videoState.actualDanmakuFontSize;
  }

  @override
  void initState() {
    super.initState();
    // 移除键盘事件处理
    // _focusNode.onKey = _handleKeyEvent;

    // 使用安全的方式初始化，避免在卸载后访问context
    _safeInitialize();

    // <<< ADDED: Setup callback for serious errors
    // We need to get the VideoPlayerState instance.
    // Since this is initState, and Consumer is used in build,
    // we use Provider.of with listen: false.
    // It's often safer to do this in didChangeDependencies if context is needed
    // more reliably, but for listen:false, initState is usually fine.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _videoPlayerStateInstance =
            Provider.of<VideoPlayerState>(context, listen: false);
        _videoPlayerStateInstance?.onSeriousPlaybackErrorAndShouldPop =
            () async {
          if (mounted && _videoPlayerStateInstance != null) {
            // 获取当前的错误信息用于显示
            final String errorMessage =
                _videoPlayerStateInstance!.error ?? "发生未知播放错误，已停止播放。";

            // 显示 BlurDialog
            BlurDialog.show<void>(
              context: context, // 使用 VideoPlayerUI 的 context
              title: '播放错误',
              content: errorMessage,
              actions: [
                TextButton(
                  child: const Text('确定'),
                  onPressed: () {
                    // 1. Pop the dialog
                    //    这里的 context 是 BlurDialog.show 内部创建的用于对话框的 context
                    Navigator.of(context).pop();

                    // 2. Reset the player state.
                    //    这将导致 VideoPlayerUI 重建并因 hasVideo 为 false 而显示 VideoUploadUI。
                    _videoPlayerStateInstance!.resetPlayer();
                  },
                ),
              ],
            );
          } else {
            print(
                "[VideoPlayerUI] onSeriousPlaybackErrorAndShouldPop: Not mounted or _videoPlayerStateInstance is null.");
          }
        };

        // 设置视频识别失败回调
        _videoPlayerStateInstance?.onVideoRecognitionFailed = () {
          if (mounted && _videoPlayerStateInstance != null) {
            debugPrint("视频识别失败，显示提示消息");
            BlurSnackBar.show(
              context,
              '无法自动识别视频的关联性，是否手动匹配弹幕？',
              duration: const Duration(seconds: 10),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                  child: const Text('取消'),
                  onPressed: () {
                    // 取消按钮不需要额外操作，点击后消息会自动关闭
                  },
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blue.withOpacity(0.3),
                    textStyle: const TextStyle(fontSize: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text('手动匹配'),
                  onPressed: () async {
                    // 显示手动匹配界面
                    await _showManualDanmakuDialog();
                  },
                ),
              ],
            );
          }
        };

        // 设置弹幕数据缺失回调
        _videoPlayerStateInstance?.onDanmakuDataMissing = () {
          if (mounted && _videoPlayerStateInstance != null) {
            debugPrint("识别到视频关联性但未获取到弹幕数据，显示提示对话框");
            BlurDialog.show<void>(
              context: context,
              title: '弹幕数据缺失',
              content: '已识别视频关联性，但未获取到弹幕数据，是否手动匹配弹幕？',
              actions: [
                TextButton(
                  child: const Text('取消'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('手动匹配'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    // 显示手动匹配界面
                    await _showManualDanmakuDialog();
                  },
                ),
              ],
            );
          }
        };

        // 设置上下文，以便 VideoPlayerState 可以访问
        _videoPlayerStateInstance?.setContext(context);

        // 其他初始化逻辑...
        // ...
      }
    });
  }

  // 使用单独的方法进行安全初始化
  Future<void> _safeInitialize() async {
    // 使用微任务确保在当前帧渲染完成后执行
    Future.microtask(() {
      // 首先检查组件是否仍然挂载
      if (!mounted) return;

      try {
        // 移除键盘快捷键注册
        // _registerKeyboardShortcuts();

        // 安全获取视频状态
        final videoState =
            Provider.of<VideoPlayerState>(context, listen: false);
        videoState.setContext(context);

        // 如果不是手机，重置鼠标隐藏计时器
        if (!globals.isPhone) {
          _resetMouseHideTimer();
        }
      } catch (e) {
        // 捕获并记录任何异常
        print('VideoPlayerUI初始化出错: $e');
      }
    });
  }

  // 移除键盘快捷键注册方法
  // void _registerKeyboardShortcuts() { ... }

  void _resetMouseHideTimer() {
    _mouseMoveTimer?.cancel();
    if (!globals.isPhone) {
      _mouseMoveTimer = Timer(_mouseHideDelay, () {
        if (mounted && !_isProcessingTap) {
          setState(() {
            _isMouseVisible = false;
          });
        }
      });
    }
  }

  void _handleTap() {
    if (_isProcessingTap) return;
    if (_isHorizontalDragging) return;

    _tapCount++;
    if (_tapCount == 1) {
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(_doubleTapTimeout, () {
        if (_tapCount == 1) {
          _handleSingleTap();
        }
        _tapCount = 0;
      });
    } else if (_tapCount == 2) {
      _doubleTapTimer?.cancel();
      _tapCount = 0;
      _handleDoubleTap();
    }
  }

  void _handleSingleTap() {
    _isProcessingTap = true;
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      if (globals.isPhone) {
        videoState.toggleControls();
      } else {
        videoState.togglePlayPause();
      }
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      _isProcessingTap = false;
    });
  }

  void _handleDoubleTap() {
    if (_isProcessingTap) return;
    _tapCount = 0;
    _doubleTapTimer?.cancel();

    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      if (globals.isPhone) {
        videoState.togglePlayPause();
      } else {
        videoState.toggleFullscreen();
      }
    }
  }

  // 添加长按手势处理方法
  void _handleLongPressStart(VideoPlayerState videoState) {
    if (!globals.isPhone || !videoState.hasVideo) return;

    // 开始倍速播放
    videoState.startSpeedBoost();

    // 触觉反馈
    HapticFeedback.lightImpact();
  }

  void _handleLongPressEnd(VideoPlayerState videoState) {
    if (!globals.isPhone || !videoState.hasVideo) return;

    // 结束倍速播放
    videoState.stopSpeedBoost();

    // 触觉反馈
    HapticFeedback.lightImpact();
  }

  void _handleMouseMove(PointerEvent event) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (!videoState.hasVideo) return;

    if (!_isMouseVisible) {
      setState(() {
        _isMouseVisible = true;
      });
    }
    videoState.setShowControls(true);

    _mouseMoveTimer?.cancel();
    _mouseMoveTimer = Timer(_mouseHideDelay, () {
      if (mounted && !_isIndicatorHovered) {
        setState(() {
          _isMouseVisible = false;
        });
        videoState.setShowControls(false);
      }
    });
  }

  void _handleHorizontalDragStart(
      BuildContext context, DragStartDetails details) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.hasVideo) {
      _isHorizontalDragging = true;
      videoState.startSeekDrag(context);
      _doubleTapTimer?.cancel();
      _tapCount = 0;
    }
  }

  void _handleHorizontalDragUpdate(
      BuildContext context, DragUpdateDetails details) {
    if (_isHorizontalDragging) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      if (details.primaryDelta != null && details.primaryDelta!.abs() > 0) {
        if ((details.delta.dx.abs() > details.delta.dy.abs())) {
          videoState.updateSeekDrag(details.delta.dx, context);
        }
      }
    }
  }

  void _handleHorizontalDragEnd(BuildContext context, DragEndDetails details) {
    if (_isHorizontalDragging) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.endSeekDrag();
      _isHorizontalDragging = false;
    }
  }

  // 显示手动匹配弹幕的对话框
  Future<void> _showManualDanmakuDialog() async {
    try {
      debugPrint("显示手动匹配弹幕对话框");
      // 使用ManualDanmakuMatcher服务类显示手动匹配对话框
      final Map<String, dynamic>? result =
          await ManualDanmakuMatcher.instance.showManualMatchDialog(
        context,
        // 可以尝试从_videoPlayerStateInstance获取视频标题作为初始搜索文本
        initialVideoTitle:
            _videoPlayerStateInstance?.currentVideoPath?.split('/').last ?? '',
      );
      if (result != null) {
        debugPrint("手动匹配弹幕成功，获取到匹配结果");
        // 如果匹配成功，使用匹配结果加载弹幕
        final int animeId = result['anime']['animeId'];
        final int episodeId = result['episode']['episodeId'];

        if (_videoPlayerStateInstance != null) {
          debugPrint("加载匹配到的弹幕数据: animeId=$animeId, episodeId=$episodeId");
          await _videoPlayerStateInstance!.loadDanmaku(
            episodeId.toString(),
            animeId.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint("显示手动匹配弹幕对话框时出错: $e");
      // 如果手动匹配功能不可用，可以显示一个简单的提示
      if (mounted) {
        BlurDialog.show<void>(
          context: context,
          title: '功能不可用',
          content: '手动匹配弹幕功能暂时不可用，请稍后再试。',
          actions: [
            TextButton(
              child: const Text('确定'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      }
    }
  }

  @override
  void dispose() {
    // <<< ADDED: Clear the callbacks to prevent memory leaks
    if (_videoPlayerStateInstance != null) {
      _videoPlayerStateInstance!.onSeriousPlaybackErrorAndShouldPop = null;
      _videoPlayerStateInstance!.onVideoRecognitionFailed = null;
      _videoPlayerStateInstance!.onDanmakuDataMissing = null;
    }

    // 确保清理所有资源
    _focusNode.dispose();
    _doubleTapTimer?.cancel();
    _mouseMoveTimer?.cancel();

    super.dispose();
  }

  // 移除键盘事件处理方法
  // KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) { ... }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final uiThemeProvider = Provider.of<UIThemeProvider>(context);
        final textureId = videoState.player.textureId.value;

        // 更新番剧封面URL（如果有番剧ID）
        _updateAnimeCoverUrl(videoState.animeId);

        if (!videoState.hasVideo) {
          return Stack(
            children: [
              const VideoUploadUI(),
              if (videoState.status == PlayerStatus.recognizing ||
                  videoState.status == PlayerStatus.loading)
                uiThemeProvider.isFluentUITheme
                    ? FluentLoadingOverlay(
                        messages: videoState.statusMessages,
                        highPriorityAnimation:
                            !videoState.isInFinalLoadingPhase,
                        animeTitle: videoState.animeTitle,
                        episodeTitle: videoState.episodeTitle,
                        fileName: videoState.currentVideoPath?.split('/').last,
                        coverImageUrl: _currentAnimeCoverUrl,
                      )
                    : LoadingOverlay(
                        messages: videoState.statusMessages,
                        backgroundOpacity: 0.5,
                        highPriorityAnimation:
                            !videoState.isInFinalLoadingPhase,
                        animeTitle: videoState.animeTitle,
                        episodeTitle: videoState.episodeTitle,
                        fileName: videoState.currentVideoPath?.split('/').last,
                        coverImageUrl: _currentAnimeCoverUrl,
                      ),
            ],
          );
        }

        if (videoState.error != null) {
          return const SizedBox.shrink();
        }

        if (textureId != null && textureId >= 0) {
          return MouseRegion(
            onHover: _handleMouseMove,
            cursor: _isMouseVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onLongPressStart: globals.isPhone
                      ? (details) => _handleLongPressStart(videoState)
                      : null,
                  onLongPressEnd: globals.isPhone
                      ? (details) => _handleLongPressEnd(videoState)
                      : null,
                  onHorizontalDragStart: globals.isPhone
                      ? (details) =>
                          _handleHorizontalDragStart(context, details)
                      : null,
                  onHorizontalDragUpdate: globals.isPhone
                      ? (details) =>
                          _handleHorizontalDragUpdate(context, details)
                      : null,
                  onHorizontalDragEnd: globals.isPhone
                      ? (details) => _handleHorizontalDragEnd(context, details)
                      : null,
                  child: FocusScope(
                    node: FocusScopeNode(),
                    child: globals.isPhone
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: videoState.aspectRatio,
                                        child: Texture(
                                          textureId: textureId,
                                          filterQuality: FilterQuality.medium,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              if (videoState.hasVideo &&
                                  videoState.danmakuVisible)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: true,
                                    child: Consumer<VideoPlayerState>(
                                      builder: (context, videoState, _) {
                                        // 使用高频时间轴驱动弹幕帧率
                                        return ValueListenableBuilder<double>(
                                          valueListenable:
                                              videoState.playbackTimeMs,
                                          builder: (context, posMs, __) {
                                            return DanmakuOverlay(
                                              key: ValueKey(
                                                  'danmaku_${videoState.danmakuOverlayKey}'),
                                              currentPosition: posMs,
                                              videoDuration: videoState
                                                  .videoDuration.inMilliseconds
                                                  .toDouble(),
                                              isPlaying: videoState.status ==
                                                  PlayerStatus.playing,
                                              fontSize: getFontSize(videoState),
                                              isVisible:
                                                  videoState.danmakuVisible,
                                              opacity: videoState
                                                  .mappedDanmakuOpacity,
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),

                              if (videoState.status ==
                                      PlayerStatus.recognizing ||
                                  videoState.status == PlayerStatus.loading)
                                Positioned.fill(
                                  child: uiThemeProvider.isFluentUITheme
                                      ? FluentLoadingOverlay(
                                          messages: videoState.statusMessages,
                                          highPriorityAnimation:
                                              !videoState.isInFinalLoadingPhase,
                                          animeTitle: videoState.animeTitle,
                                          episodeTitle: videoState.episodeTitle,
                                          fileName: videoState.currentVideoPath
                                              ?.split('/')
                                              .last,
                                          coverImageUrl: _currentAnimeCoverUrl,
                                        )
                                      : LoadingOverlay(
                                          messages: videoState.statusMessages,
                                          backgroundOpacity: 0.5,
                                          highPriorityAnimation:
                                              !videoState.isInFinalLoadingPhase,
                                          animeTitle: videoState.animeTitle,
                                          episodeTitle: videoState.episodeTitle,
                                          fileName: videoState.currentVideoPath
                                              ?.split('/')
                                              .last,
                                          coverImageUrl: _currentAnimeCoverUrl,
                                        ),
                                ),

                              if (videoState.hasVideo)
                                VerticalIndicator(videoState: videoState),

                              if (globals.isPhone && videoState.hasVideo)
                                const BrightnessGestureArea(),

                              if (globals.isPhone && videoState.hasVideo)
                                const VolumeGestureArea(),

                              // 底部1像素白色进度条
                              const MinimalProgressBar(),

                              // 弹幕密度曲线
                              const DanmakuDensityBar(),
                            ],
                          )
                        : Focus(
                            focusNode: _focusNode,
                            autofocus: true,
                            canRequestFocus: true,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(
                                  child: RepaintBoundary(
                                    child: ColoredBox(
                                      color: Colors.black,
                                      child: Center(
                                        child: AspectRatio(
                                          aspectRatio: videoState.aspectRatio,
                                          child: Texture(
                                            textureId: textureId,
                                            filterQuality: FilterQuality.medium,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                if (videoState.hasVideo &&
                                    videoState.danmakuVisible)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: true,
                                      child: Consumer<VideoPlayerState>(
                                        builder: (context, videoState, _) {
                                          // 使用高频时间轴驱动弹幕帧率
                                          return ValueListenableBuilder<double>(
                                            valueListenable:
                                                videoState.playbackTimeMs,
                                            builder: (context, posMs, __) {
                                              return DanmakuOverlay(
                                                key: ValueKey(
                                                    'danmaku_${videoState.danmakuOverlayKey}'),
                                                currentPosition: posMs,
                                                videoDuration: videoState
                                                    .videoDuration
                                                    .inMilliseconds
                                                    .toDouble(),
                                                isPlaying: videoState.status ==
                                                    PlayerStatus.playing,
                                                fontSize:
                                                    getFontSize(videoState),
                                                isVisible:
                                                    videoState.danmakuVisible,
                                                opacity: videoState
                                                    .mappedDanmakuOpacity,
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),

                                if (videoState.status ==
                                        PlayerStatus.recognizing ||
                                    videoState.status == PlayerStatus.loading)
                                  Positioned.fill(
                                    child: uiThemeProvider.isFluentUITheme
                                        ? FluentLoadingOverlay(
                                            messages: videoState.statusMessages,
                                            highPriorityAnimation: !videoState
                                                .isInFinalLoadingPhase,
                                            animeTitle: videoState.animeTitle,
                                            episodeTitle:
                                                videoState.episodeTitle,
                                            fileName: videoState
                                                .currentVideoPath
                                                ?.split('/')
                                                .last,
                                            coverImageUrl:
                                                _currentAnimeCoverUrl,
                                          )
                                        : LoadingOverlay(
                                            messages: videoState.statusMessages,
                                            backgroundOpacity: 0.5,
                                            highPriorityAnimation: !videoState
                                                .isInFinalLoadingPhase,
                                            animeTitle: videoState.animeTitle,
                                            episodeTitle:
                                                videoState.episodeTitle,
                                            fileName: videoState
                                                .currentVideoPath
                                                ?.split('/')
                                                .last,
                                            coverImageUrl:
                                                _currentAnimeCoverUrl,
                                          ),
                                  ),

                                if (videoState.hasVideo)
                                  VerticalIndicator(videoState: videoState),

                                // 右边缘悬浮菜单（仅桌面版）
                                uiThemeProvider.isFluentUITheme
                                    ? const FluentRightEdgeMenu()
                                    : const RightEdgeHoverMenu(),

                                // 底部1像素白色进度条
                                const MinimalProgressBar(),

                                // 弹幕密度曲线
                                const DanmakuDensityBar(),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
