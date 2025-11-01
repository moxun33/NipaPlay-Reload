import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/utils/message_helper.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/pages/fluent_anime_detail_page.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FluentDashboardHomePage extends StatefulWidget {
  const FluentDashboardHomePage({super.key});

  @override
  State<FluentDashboardHomePage> createState() => _FluentDashboardHomePageState();
}

class _FluentDashboardHomePageState extends State<FluentDashboardHomePage>
    with AutomaticKeepAliveClientMixin {
  // 持有Provider实例引用，确保在dispose中能正确移除监听器
  JellyfinProvider? _jellyfinProviderRef;
  EmbyProvider? _embyProviderRef;
  WatchHistoryProvider? _watchHistoryProviderRef;
  ScanService? _scanServiceRef;
  VideoPlayerState? _videoPlayerStateRef;
  
  @override
  bool get wantKeepAlive => true;

  // 推荐内容数据
  List<RecommendedItem> _recommendedItems = [];
  bool _isLoadingRecommended = false;
  
  // 待处理的刷新请求
  bool _pendingRefreshAfterLoad = false;
  String _pendingRefreshReason = '';

  // 播放器状态追踪，用于检测退出播放器时触发刷新
  bool _wasPlayerActive = false;
  Timer? _playerStateCheckTimer;
  
  // 播放器状态缓存，减少频繁的Provider查询
  bool _cachedPlayerActiveState = false;
  DateTime _lastPlayerStateCheck = DateTime.now();

  // 最近添加数据 - 按媒体库分类
  Map<String, List<JellyfinMediaItem>> _recentJellyfinItemsByLibrary = {};
  Map<String, List<EmbyMediaItem>> _recentEmbyItemsByLibrary = {};
  
  // 本地媒体库数据 - 使用番组信息而不是观看历史
  List<LocalAnimeItem> _localAnimeItems = [];
  // 本地媒体库图片持久化缓存（与 MediaLibraryPage 复用同一前缀）
  final Map<int, String> _localImageCache = {};
  static const String _localPrefsKeyPrefix = 'media_library_image_url_';
  bool _isLoadingLocalImages = false;

  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _continueWatchingScrollController = ScrollController();
  final ScrollController _recentJellyfinScrollController = ScrollController();
  final ScrollController _recentEmbyScrollController = ScrollController();
  
  // 动态媒体库的ScrollController映射
  final Map<String, ScrollController> _jellyfinLibraryScrollControllers = {};
  final Map<String, ScrollController> _embyLibraryScrollControllers = {};
  ScrollController? _localLibraryScrollController;
  
  // 自动切换相关
  Timer? _autoSwitchTimer;
  bool _isAutoSwitching = true;
  int _currentHeroBannerIndex = 0;
  late final ValueNotifier<int> _heroBannerIndexNotifier;
  int? _hoveredIndicatorIndex;

  // 缓存映射，用于存储已绘制的缩略图和最后绘制时间
  final Map<String, Map<String, dynamic>> _thumbnailCache = {};

  // 静态变量，用于缓存推荐内容
  static List<RecommendedItem> _cachedRecommendedItems = [];
  static DateTime? _lastRecommendedLoadTime;

  @override
  void initState() {
    super.initState();
    _heroBannerIndexNotifier = ValueNotifier(0);
    
    // 🔥 修复Flutter状态错误：将数据加载移到addPostFrameCallback中
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupProviderListeners();
      _startAutoSwitch();
      
      // 🔥 在build完成后安全地加载数据，避免setState during build错误
      if (mounted) {
        _loadData();
      }
    });
  }
  
  // 获取或创建Jellyfin媒体库的ScrollController
  ScrollController _getJellyfinLibraryScrollController(String libraryName) {
    if (!_jellyfinLibraryScrollControllers.containsKey(libraryName)) {
      _jellyfinLibraryScrollControllers[libraryName] = ScrollController();
    }
    return _jellyfinLibraryScrollControllers[libraryName]!;
  }
  
  // 获取或创建Emby媒体库的ScrollController
  ScrollController _getEmbyLibraryScrollController(String libraryName) {
    if (!_embyLibraryScrollControllers.containsKey(libraryName)) {
      _embyLibraryScrollControllers[libraryName] = ScrollController();
    }
    return _embyLibraryScrollControllers[libraryName]!;
  }
  
  // 获取或创建本地媒体库的ScrollController
  ScrollController _getLocalLibraryScrollController() {
    _localLibraryScrollController ??= ScrollController();
    return _localLibraryScrollController!;
  }
  
  void _startAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _autoSwitchTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAutoSwitching && _recommendedItems.length >= 3 && mounted) {
        _currentHeroBannerIndex = (_currentHeroBannerIndex + 1) % math.min(3, _recommendedItems.length);
        _heroBannerIndexNotifier.value = _currentHeroBannerIndex;
      }
    });
  }
  
  void _stopAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _isAutoSwitching = false;
  }
  
  void _resumeAutoSwitch() {
    _isAutoSwitching = true;
    _startAutoSwitch();
  }

  void _setupProviderListeners() {
    // 监听各种Provider状态变化 - 简化版本，与原版逻辑相同
    try {
      _jellyfinProviderRef = Provider.of<JellyfinProvider>(context, listen: false);
      _jellyfinProviderRef!.addListener(_onJellyfinStateChanged);
    } catch (e) {
      debugPrint('FluentDashboard: 添加JellyfinProvider监听器失败: $e');
    }
    
    try {
      _embyProviderRef = Provider.of<EmbyProvider>(context, listen: false);
      _embyProviderRef!.addListener(_onEmbyStateChanged);
    } catch (e) {
      debugPrint('FluentDashboard: 添加EmbyProvider监听器失败: $e');
    }
    
    try {
      _watchHistoryProviderRef = Provider.of<WatchHistoryProvider>(context, listen: false);
      _watchHistoryProviderRef!.addListener(_onWatchHistoryStateChanged);
    } catch (e) {
      debugPrint('FluentDashboard: 添加WatchHistoryProvider监听器失败: $e');
    }
    
    try {
      _scanServiceRef = Provider.of<ScanService>(context, listen: false);
      _scanServiceRef!.addListener(_onScanServiceStateChanged);
    } catch (e) {
      debugPrint('FluentDashboard: 添加ScanService监听器失败: $e');
    }
    
    try {
      _videoPlayerStateRef = Provider.of<VideoPlayerState>(context, listen: false);
      _videoPlayerStateRef!.addListener(_onVideoPlayerStateChanged);
    } catch (e) {
      debugPrint('FluentDashboard: 添加VideoPlayerState监听器失败: $e');
    }
  }

  // 检查播放器是否处于活跃状态
  bool _isVideoPlayerActive() {
    try {
      final now = DateTime.now();
      const cacheValidDuration = Duration(milliseconds: 100);
      
      if (now.difference(_lastPlayerStateCheck) < cacheValidDuration) {
        return _cachedPlayerActiveState;
      }
      
      final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
      final isActive = videoPlayerState.status == PlayerStatus.playing || 
             videoPlayerState.status == PlayerStatus.paused ||
             videoPlayerState.hasVideo ||
             videoPlayerState.currentVideoPath != null;
      
      _cachedPlayerActiveState = isActive;
      _lastPlayerStateCheck = now;
      
      return isActive;
    } catch (e) {
      debugPrint('FluentDashboard: _isVideoPlayerActive() 出错: $e');
      return false;
    }
  }

  void _onVideoPlayerStateChanged() {
    if (!mounted) return;
    
    final isCurrentlyActive = _isVideoPlayerActive();
    
    if (_wasPlayerActive && !isCurrentlyActive) {
      _playerStateCheckTimer?.cancel();
      _playerStateCheckTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && !_isVideoPlayerActive()) {
          _loadData();
        }
      });
    }
    
    if (!_wasPlayerActive && isCurrentlyActive) {
      _playerStateCheckTimer?.cancel();
    }
    
    _wasPlayerActive = isCurrentlyActive;
  }
  
  void _onJellyfinStateChanged() {
    if (!mounted || _isVideoPlayerActive()) return;
    
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    if (jellyfinProvider.isConnected && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    }
  }
  
  void _onEmbyStateChanged() {
    if (!mounted || _isVideoPlayerActive()) return;
    
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    if (embyProvider.isConnected && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    }
  }
  
  void _onWatchHistoryStateChanged() {
    if (!mounted || _isVideoPlayerActive()) return;
    
    final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
    if (watchHistoryProvider.isLoaded && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    }
  }
  
  void _onScanServiceStateChanged() {
    if (!mounted || _isVideoPlayerActive()) return;
    
    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.scanJustCompleted && mounted) {
      try {
        final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
        watchHistoryProvider.refresh();
      } catch (e) {
        debugPrint('FluentDashboard: 刷新WatchHistoryProvider失败: $e');
      }
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
      
      scanService.acknowledgeScanCompleted();
    }
  }

  @override
  void dispose() {
    _autoSwitchTimer?.cancel();
    _playerStateCheckTimer?.cancel();
    _heroBannerIndexNotifier.dispose();
    
    // 移除监听器
    try {
      _jellyfinProviderRef?.removeListener(_onJellyfinStateChanged);
      _embyProviderRef?.removeListener(_onEmbyStateChanged);
      _watchHistoryProviderRef?.removeListener(_onWatchHistoryStateChanged);
      _scanServiceRef?.removeListener(_onScanServiceStateChanged);
      _videoPlayerStateRef?.removeListener(_onVideoPlayerStateChanged);
    } catch (e) {
      debugPrint('FluentDashboard: 移除监听器失败: $e');
    }
    
    // 销毁ScrollController
    try {
      _mainScrollController.dispose();
      _continueWatchingScrollController.dispose();
      _recentJellyfinScrollController.dispose();
      _recentEmbyScrollController.dispose();
      
      for (final controller in _jellyfinLibraryScrollControllers.values) {
        controller.dispose();
      }
      _jellyfinLibraryScrollControllers.clear();
      
      for (final controller in _embyLibraryScrollControllers.values) {
        controller.dispose();
      }
      _embyLibraryScrollControllers.clear();
      
      _localLibraryScrollController?.dispose();
    } catch (e) {
      debugPrint('FluentDashboard: 销毁ScrollController失败: $e');
    }
    
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted || _isVideoPlayerActive() || _isLoadingRecommended) return;
    
    // 确保WatchHistoryProvider已加载
    try {
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (!watchHistoryProvider.isLoaded && !watchHistoryProvider.isLoading) {
        await watchHistoryProvider.loadHistory();
      }
    } catch (e) {
      debugPrint('FluentDashboard: 加载WatchHistoryProvider失败: $e');
    }
    
    try {
      await Future.wait([
        _loadRecommendedContent(forceRefresh: true),
        _loadRecentContent(),
      ]);
    } catch (e) {
      debugPrint('FluentDashboard: 并行加载数据时发生错误: $e');
    }
  }

  Future<void> _loadRecommendedContent({bool forceRefresh = false}) async {
    if (!mounted) return;
    
    // 检查缓存
    if (!forceRefresh && _cachedRecommendedItems.isNotEmpty && 
        _lastRecommendedLoadTime != null && 
        DateTime.now().difference(_lastRecommendedLoadTime!).inHours < 24) {
      setState(() {
        _recommendedItems = _cachedRecommendedItems;
        _isLoadingRecommended = false;
      });
      if (_recommendedItems.length >= 3) _startAutoSwitch();
      return;
    }

    setState(() {
      _isLoadingRecommended = true;
    });

    try {
      // 简化版本：只收集少量推荐内容，适合FluentUI的简洁风格
      List<dynamic> allCandidates = [];

      // 从各媒体源收集候选项目（逻辑与原版相同，但数量更少）
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            try {
              final items = await jellyfinService.getRandomMediaItemsByLibrary(library.id, limit: 20);
              allCandidates.addAll(items);
            } catch (e) {
              debugPrint('FluentDashboard: 获取Jellyfin媒体库内容失败: $e');
            }
          }
        }
      }

      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            try {
              final items = await embyService.getRandomMediaItemsByLibrary(library.id, limit: 20);
              allCandidates.addAll(items);
            } catch (e) {
              debugPrint('FluentDashboard: 获取Emby媒体库内容失败: $e');
            }
          }
        }
      }

      // 从本地媒体库收集候选项目
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://')
          ).toList();
          
          final Map<int, WatchHistoryItem> latestLocalItems = {};
          for (var item in localHistory) {
            if (item.animeId != null) {
              if (!latestLocalItems.containsKey(item.animeId!) ||
                  item.lastWatchTime.isAfter(latestLocalItems[item.animeId!]!.lastWatchTime)) {
                latestLocalItems[item.animeId!] = item;
              }
            }
          }
          
          final localItems = latestLocalItems.values.toList();
          localItems.shuffle(math.Random());
          allCandidates.addAll(localItems.take(10));
        } catch (e) {
          debugPrint('FluentDashboard: 获取本地媒体库内容失败: $e');
        }
      }

      // 随机选择3个推荐项目（FluentUI风格更简洁）
      List<dynamic> selectedCandidates = [];
      if (allCandidates.isNotEmpty) {
        allCandidates.shuffle(math.Random());
        selectedCandidates = allCandidates.take(3).toList();
      }

      // 构建推荐项目
      List<RecommendedItem> basicItems = [];
      for (final item in selectedCandidates) {
        try {
          if (item is JellyfinMediaItem) {
            final jellyfinService = JellyfinService.instance;
            String? backdropUrl;
            try {
              backdropUrl = jellyfinService.getImageUrl(item.id, type: 'Backdrop');
            } catch (e) {
              backdropUrl = null;
            }

            basicItems.add(RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: item.overview?.isNotEmpty == true ? item.overview!
                  .replaceAll('<br>', ' ')
                  .replaceAll('<br/>', ' ')
                  .replaceAll('<br />', ' ') : '暂无简介信息',
              backgroundImageUrl: backdropUrl,
              source: RecommendedItemSource.jellyfin,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            ));
            
          } else if (item is EmbyMediaItem) {
            final embyService = EmbyService.instance;
            String? backdropUrl;
            try {
              backdropUrl = embyService.getImageUrl(item.id, type: 'Backdrop');
            } catch (e) {
              backdropUrl = null;
            }

            basicItems.add(RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: item.overview?.isNotEmpty == true ? item.overview!
                  .replaceAll('<br>', ' ')
                  .replaceAll('<br/>', ' ')
                  .replaceAll('<br />', ' ') : '暂无简介信息',
              backgroundImageUrl: backdropUrl,
              source: RecommendedItemSource.emby,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            ));
            
          } else if (item is WatchHistoryItem) {
            String? cachedImageUrl;
            String subtitle = '暂无简介信息';
            
            if (item.animeId != null) {
              cachedImageUrl = _localImageCache[item.animeId!];
              
              if (cachedImageUrl == null) {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final persisted = prefs.getString('$_localPrefsKeyPrefix${item.animeId!}');
                  if (persisted != null && persisted.isNotEmpty) {
                    cachedImageUrl = persisted;
                    _localImageCache[item.animeId!] = persisted;
                  }
                } catch (_) {}
              }

              try {
                final prefs = await SharedPreferences.getInstance();
                final cacheKey = 'bangumi_detail_${item.animeId!}';
                final String? cachedString = prefs.getString(cacheKey);
                if (cachedString != null) {
                  final data = json.decode(cachedString);
                  final animeData = data['animeDetail'] as Map<String, dynamic>?;
                  if (animeData != null) {
                    final summary = animeData['summary'] as String?;
                    if (summary?.isNotEmpty == true) {
                      subtitle = summary!;
                    }
                  }
                }
              } catch (_) {}
            }
            
            basicItems.add(RecommendedItem(
              id: item.animeId?.toString() ?? item.filePath,
              title: item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画'),
              subtitle: subtitle,
              backgroundImageUrl: cachedImageUrl,
              source: RecommendedItemSource.local,
              rating: null,
            ));
          }
        } catch (e) {
          debugPrint('FluentDashboard: 构建推荐项目失败: $e');
        }
      }

      // 如果不够3个，添加占位符
      while (basicItems.length < 3) {
        basicItems.add(RecommendedItem(
          id: 'placeholder_${basicItems.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }

      if (mounted) {
        setState(() {
          _recommendedItems = basicItems;
          _isLoadingRecommended = false;
        });
        
        _cachedRecommendedItems = basicItems;
        _lastRecommendedLoadTime = DateTime.now();
        
        if (basicItems.length >= 3) {
          _startAutoSwitch();
        }
      }
      
    } catch (e) {
      debugPrint('FluentDashboard: 加载推荐内容失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingRecommended = false;
        });
      }
    }
  }

  Future<void> _loadRecentContent() async {
    try {
      // 加载最近内容的逻辑与原版相同，但适配FluentUI
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        _recentJellyfinItemsByLibrary.clear();
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            try {
              final libraryItems = await jellyfinService.getLatestMediaItemsByLibrary(library.id, limit: 15);
              if (libraryItems.isNotEmpty) {
                _recentJellyfinItemsByLibrary[library.name] = libraryItems;
              }
            } catch (e) {
              debugPrint('FluentDashboard: 获取Jellyfin最近内容失败: $e');
            }
          }
        }
      }

      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        _recentEmbyItemsByLibrary.clear();
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            try {
              final libraryItems = await embyService.getLatestMediaItemsByLibrary(library.id, limit: 15);
              if (libraryItems.isNotEmpty) {
                _recentEmbyItemsByLibrary[library.name] = libraryItems;
              }
            } catch (e) {
              debugPrint('FluentDashboard: 获取Emby最近内容失败: $e');
            }
          }
        }
      }

      // 本地媒体库逻辑与原版相同
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://')
          ).toList();

          final Map<int, WatchHistoryItem> representativeItems = {};
          final Map<int, DateTime> addedTimeMap = {};

          for (final item in localHistory) {
            final animeId = item.animeId;
            if (animeId == null) continue;

            final candidateTime = item.isFromScan ? item.lastWatchTime : item.lastWatchTime;
            if (!representativeItems.containsKey(animeId)) {
              representativeItems[animeId] = item;
              addedTimeMap[animeId] = candidateTime;
            } else {
              if (candidateTime.isAfter(addedTimeMap[animeId]!)) {
                representativeItems[animeId] = item;
                addedTimeMap[animeId] = candidateTime;
              }
            }
          }

          await _loadPersistedLocalImageUrls(addedTimeMap.keys.toSet());

          List<LocalAnimeItem> localAnimeItems = representativeItems.entries.map((entry) {
            final animeId = entry.key;
            final latestEpisode = entry.value;
            final addedTime = addedTimeMap[animeId]!;
            final cachedImg = _localImageCache[animeId];
            return LocalAnimeItem(
              animeId: animeId,
              animeName: latestEpisode.animeName.isNotEmpty ? latestEpisode.animeName : '未知动画',
              imageUrl: cachedImg,
              backdropImageUrl: cachedImg,
              addedTime: addedTime,
              latestEpisode: latestEpisode,
            );
          }).toList();

          localAnimeItems.sort((a, b) => b.addedTime.compareTo(a.addedTime));
          if (localAnimeItems.length > 15) {
            localAnimeItems = localAnimeItems.take(15).toList();
          }

          _localAnimeItems = localAnimeItems;
        } catch (e) {
          debugPrint('FluentDashboard: 获取本地媒体库最近内容失败: $e');
        }
      }

      if (mounted) {
        setState(() {
          // 触发UI更新
        });
        _fetchLocalAnimeImagesInBackground();
      }
    } catch (e) {
      debugPrint('FluentDashboard: 加载最近内容失败: $e');
    }
  }

  // 加载持久化的本地番组图片URL
  Future<void> _loadPersistedLocalImageUrls(Set<int> animeIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in animeIds) {
        if (_localImageCache.containsKey(id)) continue;
        final url = prefs.getString('$_localPrefsKeyPrefix$id');
        if (url != null && url.isNotEmpty) {
          _localImageCache[id] = url;
        }
      }
    } catch (e) {
      debugPrint('FluentDashboard: 加载本地图片持久化缓存失败: $e');
    }
  }

  // 后台获取本地番剧图片
  Future<void> _fetchLocalAnimeImagesInBackground() async {
    if (_isLoadingLocalImages) return;
    _isLoadingLocalImages = true;
    
    const int maxConcurrent = 2; // FluentUI版本降低并发数
    final inflight = <Future<void>>[];
    int processedCount = 0;
    int updatedCount = 0;

    for (final item in _localAnimeItems) {
      final id = item.animeId;
      if (_localImageCache.containsKey(id) && 
          _localImageCache[id]?.isNotEmpty == true) {
        continue;
      }

      Future<void> task() async {
        try {
          String? imageUrl;
          
          try {
            final prefs = await SharedPreferences.getInstance();
            final cacheKey = 'bangumi_detail_$id';
            final String? cachedString = prefs.getString(cacheKey);
            if (cachedString != null) {
              final data = json.decode(cachedString);
              final animeData = data['animeDetail'] as Map<String, dynamic>?;
              if (animeData != null) {
                imageUrl = animeData['imageUrl'] as String?;
              }
            }
          } catch (_) {}
          
          if (imageUrl?.isEmpty != false) {
            final detail = await BangumiService.instance.getAnimeDetails(id);
            imageUrl = detail.imageUrl;
          }
          
          if (imageUrl?.isNotEmpty == true) {
            _localImageCache[id] = imageUrl!;
            
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('$_localPrefsKeyPrefix$id', imageUrl);
            } catch (_) {}
            
            if (mounted) {
              final idx = _localAnimeItems.indexWhere((e) => e.animeId == id);
              if (idx != -1) {
                _localAnimeItems[idx] = LocalAnimeItem(
                  animeId: _localAnimeItems[idx].animeId,
                  animeName: _localAnimeItems[idx].animeName,
                  imageUrl: imageUrl,
                  backdropImageUrl: imageUrl,
                  addedTime: _localAnimeItems[idx].addedTime,
                  latestEpisode: _localAnimeItems[idx].latestEpisode,
                );
                updatedCount++;
              }
            }
          }
          processedCount++;
        } catch (e) {
          processedCount++;
        }
      }

      final fut = task();
      inflight.add(fut);
      fut.whenComplete(() {
        inflight.remove(fut);
      });
      
      if (inflight.length >= maxConcurrent) {
        try { 
          await Future.any(inflight); 
          if (updatedCount > 0 && processedCount % 3 == 0 && mounted) {
            setState(() {});
          }
        } catch (_) {}
      }
    }

    try { 
      await Future.wait(inflight); 
    } catch (_) {}
    
    if (mounted && updatedCount > 0) {
      setState(() {});
    }
    
    _isLoadingLocalImages = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final bool tickerEnabled = !_isVideoPlayerActive();
    
    return TickerMode(
      enabled: tickerEnabled,
      child: ScaffoldPage.scrollable(
        scrollController: _mainScrollController,
        children: [
          Consumer2<JellyfinProvider, EmbyProvider>(
            builder: (context, jellyfinProvider, embyProvider, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 推荐内容区域 - FluentUI风格
                  _buildRecommendedSection(),
                  
                  const SizedBox(height: 24),
                  
                  // 继续播放区域
                  _buildContinueWatchingSection(),
                  
                  const SizedBox(height: 24),
                  
                  // Jellyfin按媒体库显示最近添加
                  ..._recentJellyfinItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Jellyfin - 新增${entry.key}',
                      items: entry.value,
                      scrollController: _getJellyfinLibraryScrollController(entry.key),
                      onItemTap: (item) => _onJellyfinItemTap(item as JellyfinMediaItem),
                    ),
                    const SizedBox(height: 24),
                  ]).expand((x) => x),
                  
                  // Emby按媒体库显示最近添加
                  ..._recentEmbyItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Emby - 新增${entry.key}',
                      items: entry.value,
                      scrollController: _getEmbyLibraryScrollController(entry.key),
                      onItemTap: (item) => _onEmbyItemTap(item as EmbyMediaItem),
                    ),
                    const SizedBox(height: 24),
                  ]).expand((x) => x),
                  
                  // 本地媒体库显示最近添加
                  if (_localAnimeItems.isNotEmpty) ...[
                    _buildRecentSection(
                      title: '本地媒体库 - 最近添加',
                      items: _localAnimeItems,
                      scrollController: _getLocalLibraryScrollController(),
                      onItemTap: (item) => _onLocalAnimeItemTap(item as LocalAnimeItem),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // 空状态提示
                  if (_recentJellyfinItemsByLibrary.isEmpty && 
                      _recentEmbyItemsByLibrary.isEmpty && 
                      _localAnimeItems.isEmpty && 
                      !_isLoadingRecommended) ...[
                    Container(
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: FluentTheme.of(context).cardColor,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              FluentIcons.video,
                              color: FluentTheme.of(context).inactiveColor,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              jellyfinProvider.isConnected || embyProvider.isConnected
                                  ? '正在加载内容...'
                                  : '连接媒体服务器或观看本地视频以查看内容',
                              style: FluentTheme.of(context).typography.body?.copyWith(
                                color: FluentTheme.of(context).inactiveColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // 底部间距
                  const SizedBox(height: 50),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '推荐内容',
            style: FluentTheme.of(context).typography.subtitle,
          ),
        ),
        const SizedBox(height: 16),
        _buildRecommendedCards(),
      ],
    );
  }

  Widget _buildRecommendedCards() {
    if (_isLoadingRecommended) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: FluentTheme.of(context).cardColor,
        ),
        child: const Center(
          child: ProgressRing(),
        ),
      );
    }

    if (_recommendedItems.isEmpty) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: FluentTheme.of(context).cardColor,
        ),
        child: Center(
          child: Text(
            '暂无推荐内容',
            style: FluentTheme.of(context).typography.body?.copyWith(
              color: FluentTheme.of(context).inactiveColor,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _recommendedItems.take(3).length,
        itemBuilder: (context, index) {
          final item = _recommendedItems[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildRecommendedCard(item),
          );
        },
      ),
    );
  }

  Widget _buildRecommendedCard(RecommendedItem item) {
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: FluentTheme.of(context).cardColor,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图片
            if (item.backgroundImageUrl != null && item.backgroundImageUrl!.isNotEmpty)
              CachedNetworkImageWidget(
                imageUrl: item.backgroundImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error) => Container(
                  color: FluentTheme.of(context).cardColor,
                  child: Center(
                    child: Icon(
                      FluentIcons.error,
                      color: FluentTheme.of(context).inactiveColor,
                    ),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      FluentTheme.of(context).accentColor.withOpacity(0.3),
                      FluentTheme.of(context).accentColor.withOpacity(0.1),
                    ],
                  ),
                ),
              ),
            
            // 遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            // 服务商标识
            Positioned(
              top: 8,
              left: 8,
              child: _buildServiceIcon(item.source),
            ),
            
            // 评分
            if (item.rating != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FluentTheme.of(context).accentColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        FluentIcons.favorite_star_fill,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // 标题和简介
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: FluentTheme.of(context).typography.bodyStrong?.copyWith(
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: FluentTheme.of(context).typography.caption?.copyWith(
                        color: Colors.white.withOpacity(0.8),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIcon(RecommendedItemSource source) {
    Widget iconWidget;
    
    switch (source) {
      case RecommendedItemSource.jellyfin:
        iconWidget = SvgPicture.asset(
          'assets/jellyfin.svg',
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.emby:
        iconWidget = SvgPicture.asset(
          'assets/emby.svg',
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.local:
        iconWidget = const Icon(
          FluentIcons.folder,
          color: Colors.white,
          size: 16,
        );
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: iconWidget,
    );
  }

  Widget _buildContinueWatchingSection() {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;
        final validHistory = history.where((item) => item.duration > 0).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '继续播放',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                  ),
                ),
                if (validHistory.isNotEmpty)
                  _buildScrollButtons(_continueWatchingScrollController, 250),
              ],
            ),
            const SizedBox(height: 16),
            if (validHistory.isEmpty)
              Container(
                height: 150,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: FluentTheme.of(context).cardColor,
                ),
                child: Center(
                  child: Text(
                    '暂无播放记录',
                    style: FluentTheme.of(context).typography.body?.copyWith(
                      color: FluentTheme.of(context).inactiveColor,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: ListView.builder(
                  controller: _continueWatchingScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: math.min(validHistory.length, 10),
                  itemBuilder: (context, index) {
                    final item = validHistory[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildContinueWatchingCard(item),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildContinueWatchingCard(WatchHistoryItem item) {
    return GestureDetector(
      onTap: () => _onWatchHistoryItemTap(item),
      child: SizedBox(
        width: 250,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: FluentTheme.of(context).cardColor,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _getVideoThumbnail(item),
                  
                  // 播放进度条
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ProgressBar(
                      value: item.watchProgress * 100,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
              style: FluentTheme.of(context).typography.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            
            if (item.episodeTitle != null) ...[
              const SizedBox(height: 4),
              Text(
                item.episodeTitle!,
                style: FluentTheme.of(context).typography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSection({
    required String title,
    required List<dynamic> items,
    required ScrollController scrollController,
    required Function(dynamic) onItemTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  style: FluentTheme.of(context).typography.subtitle,
                ),
              ),
            ),
            if (items.isNotEmpty)
              _buildScrollButtons(scrollController, 160),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 240,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildMediaCard(item, onItemTap),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCard(dynamic item, Function(dynamic) onItemTap) {
    String name = '';
    String imageUrl = '';
    String uniqueId = '';
    
    if (item is JellyfinMediaItem) {
      name = item.name;
      uniqueId = 'jellyfin_${item.id}';
      try {
        imageUrl = JellyfinService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is EmbyMediaItem) {
      name = item.name;
      uniqueId = 'emby_${item.id}';
      try {
        imageUrl = EmbyService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is LocalAnimeItem) {
      name = item.animeName;
      uniqueId = 'local_${item.animeId}_${item.animeName}';
      imageUrl = item.imageUrl ?? '';
    }

    return SizedBox(
      width: 160,
      child: FluentAnimeCard(
        key: ValueKey(uniqueId),
        name: name,
        imageUrl: imageUrl,
        onTap: () => onItemTap(item),
        isOnAir: false,
      ),
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item) {
    final now = DateTime.now();
    
    if (_thumbnailCache.containsKey(item.filePath)) {
      final cachedData = _thumbnailCache[item.filePath]!;
      final lastRenderTime = cachedData['time'] as DateTime;
      
      if (now.difference(lastRenderTime).inSeconds < 60) {
        return cachedData['widget'] as Widget;
      }
    }
    
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        final thumbnailWidget = FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(color: FluentTheme.of(context).cardColor);
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildDefaultThumbnail();
            }
            try {
              // 验证图像数据是否有效
              final imageData = snapshot.data!;
              if (imageData.isEmpty) {
                return _buildDefaultThumbnail();
              }
              
              // 使用Image.memory的errorBuilder来处理无效图像数据
              return Image.memory(
                imageData,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('图像加载错误: $error');
                  // 删除损坏的缩略图文件
                  if (item.thumbnailPath != null) {
                    try {
                      final thumbnailFile = File(item.thumbnailPath!);
                      if (thumbnailFile.existsSync()) {
                        thumbnailFile.deleteSync();
                        debugPrint('已删除损坏的缩略图文件: ${item.thumbnailPath}');
                      }
                    } catch (e) {
                      debugPrint('删除缩略图文件失败: $e');
                    }
                  }
                  return _buildDefaultThumbnail();
                },
              );
            } catch (e) {
              debugPrint('图像处理异常: $e');
              return _buildDefaultThumbnail();
            }
          },
        );
        
        _thumbnailCache[item.filePath] = {
          'widget': thumbnailWidget,
          'time': now
        };
        
        return thumbnailWidget;
      }
    }

    final defaultThumbnail = _buildDefaultThumbnail();
    _thumbnailCache[item.filePath] = {
      'widget': defaultThumbnail,
      'time': now
    };
    
    return defaultThumbnail;
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      color: FluentTheme.of(context).cardColor,
      child: Center(
        child: Icon(
          FluentIcons.video,
          color: FluentTheme.of(context).inactiveColor,
          size: 32,
        ),
      ),
    );
  }

  void _onRecommendedItemTap(RecommendedItem item) {
    if (item.source == RecommendedItemSource.placeholder) return;
    
    if (item.source == RecommendedItemSource.jellyfin) {
      _navigateToJellyfinDetail(item.id);
    } else if (item.source == RecommendedItemSource.emby) {
      _navigateToEmbyDetail(item.id);
    } else if (item.source == RecommendedItemSource.local) {
      if (item.id.contains(RegExp(r'^\d+$'))) {
        final animeId = int.tryParse(item.id);
        if (animeId != null) {
          FluentAnimeDetailPage.show(context, animeId).then((result) {
            if (result != null) {
              Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadData();
              });
            }
          });
        }
      }
    }
  }

  void _onJellyfinItemTap(JellyfinMediaItem item) {
    _navigateToJellyfinDetail(item.id);
  }

  void _onEmbyItemTap(EmbyMediaItem item) {
    _navigateToEmbyDetail(item.id);
  }

  void _onLocalAnimeItemTap(LocalAnimeItem item) {
    FluentAnimeDetailPage.show(context, item.animeId).then((result) {
      if (result != null) {
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadData();
        });
      }
    });
  }

  void _navigateToJellyfinDetail(String jellyfinId) {
    MediaServerDetailPage.showJellyfin(context, jellyfinId).then((result) {
      if (result != null) {
        String? actualPlayUrl;
        final isJellyfinProtocol = result.filePath.startsWith('jellyfin://');
        
        if (isJellyfinProtocol) {
          try {
            final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
            final jellyfinService = JellyfinService.instance;
            if (jellyfinService.isConnected) {
              actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
            } else {
              MessageHelper.showMessage(context, '未连接到Jellyfin服务器');
              return;
            }
          } catch (e) {
            MessageHelper.showMessage(context, '获取Jellyfin流媒体URL失败: $e');
            return;
          }
        }
        
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _navigateToEmbyDetail(String embyId) {
    MediaServerDetailPage.showEmby(context, embyId).then((result) async {
      if (result != null) {
        String? actualPlayUrl;
        final isEmbyProtocol = result.filePath.startsWith('emby://');
        
        if (isEmbyProtocol) {
          try {
            final embyId = result.filePath.replaceFirst('emby://', '');
            final embyService = EmbyService.instance;
            if (embyService.isConnected) {
              actualPlayUrl = await embyService.getStreamUrl(embyId);
            } else {
              MessageHelper.showMessage(context, '未连接到Emby服务器');
              return;
            }
          } catch (e) {
            MessageHelper.showMessage(context, '获取Emby流媒体URL失败: $e');
            return;
          }
        }
        
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    final isNetworkUrl = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = item.filePath;
    String? actualPlayUrl;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
          } else {
            MessageHelper.showMessage(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          MessageHelper.showMessage(context, '获取Jellyfin流媒体URL失败: $e');
          return;
        }
      }
      
      if (isEmbyProtocol) {
        try {
          final embyId = item.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = await embyService.getStreamUrl(embyId);
          } else {
            MessageHelper.showMessage(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          MessageHelper.showMessage(context, '获取Emby流媒体URL失败: $e');
          return;
        }
      }
    } else {
      final videoFile = File(item.filePath);
      fileExists = videoFile.existsSync();
      
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath.startsWith('/private') 
            ? filePath.replaceFirst('/private', '') 
            : '/private$filePath';
        
        final File altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          fileExists = true;
        }
      }
    }
    
    if (!fileExists) {
      MessageHelper.showMessage(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return;
    }

    final playableItem = PlayableItem(
      videoPath: item.filePath,
      title: item.animeName,
      subtitle: item.episodeTitle,
      animeId: item.animeId,
      episodeId: item.episodeId,
      historyItem: item,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playableItem);
  }

  // 构建滚动按钮
  Widget _buildScrollButtons(ScrollController controller, double itemWidth) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final canScrollLeft = controller.hasClients && controller.offset > 0;
              return _buildScrollButton(
                icon: FluentIcons.chevron_left,
                onTap: canScrollLeft ? () => _scrollToPrevious(controller, itemWidth) : null,
                enabled: canScrollLeft,
              );
            },
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final canScrollRight = controller.hasClients && 
                  controller.offset < controller.position.maxScrollExtent;
              return _buildScrollButton(
                icon: FluentIcons.chevron_right,
                onTap: canScrollRight ? () => _scrollToNext(controller, itemWidth) : null,
                enabled: canScrollRight,
              );
            },
          ),
        ],
      ),
    );
  }
  
  // 构建单个滚动按钮
  Widget _buildScrollButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: enabled 
            ? FluentTheme.of(context).accentColor.withOpacity(0.1)
            : FluentTheme.of(context).inactiveColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: enabled
              ? FluentTheme.of(context).accentColor.withOpacity(0.3)
              : FluentTheme.of(context).inactiveColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(
          icon,
          color: enabled 
              ? FluentTheme.of(context).accentColor
              : FluentTheme.of(context).inactiveColor,
          size: 16,
        ),
      ),
    );
  }
  
  // 滚动到上一页
  void _scrollToPrevious(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = math.max(0.0, controller.offset - scrollDistance);
    
    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  // 滚动到下一页
  void _scrollToNext(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = controller.offset + scrollDistance;
    final maxScrollExtent = controller.position.maxScrollExtent;
    
    // 如果目标位置超过了最大滚动范围，就滚动到最大位置
    final finalTargetOffset = targetOffset > maxScrollExtent ? maxScrollExtent : targetOffset;
    
    controller.animateTo(
      finalTargetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}

// 推荐内容数据模型
class RecommendedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? backgroundImageUrl;
  final RecommendedItemSource source;
  final double? rating;

  RecommendedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.backgroundImageUrl,
    required this.source,
    this.rating,
  });
}

enum RecommendedItemSource {
  jellyfin,
  emby,
  local,
  placeholder,
}

// 本地动画项目数据模型
class LocalAnimeItem {
  final int animeId;
  final String animeName;
  final String? imageUrl;
  final String? backdropImageUrl;
  final DateTime addedTime;
  final WatchHistoryItem latestEpisode;

  LocalAnimeItem({
    required this.animeId,
    required this.animeName,
    this.imageUrl,
    this.backdropImageUrl,
    required this.addedTime,
    required this.latestEpisode,
  });
}