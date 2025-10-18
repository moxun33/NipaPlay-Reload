import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'base_settings_menu.dart';
import 'dart:io';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/services/emby_episode_mapping_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/alist_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/message_helper.dart';

class PlaylistMenu extends StatefulWidget {
  final VoidCallback onClose;

  const PlaylistMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<PlaylistMenu> createState() => _PlaylistMenuState();
}

class _PlaylistMenuState extends State<PlaylistMenu> {
  // 文件系统数据
  List<String> _fileSystemEpisodes = [];

  // Jellyfin剧集信息缓存 (episodeId -> episode info)
  final Map<String, dynamic> _jellyfinEpisodeCache = {};

  // Emby剧集信息缓存 (episodeId -> episode info)
  final Map<String, dynamic> _embyEpisodeCache = {};

  bool _isLoading = true;
  String? _error;
  String? _currentFilePath;
  String? _currentAnimeTitle;

  // 可用的数据源
  bool _hasFileSystemData = false;

  @override
  void initState() {
    super.initState();
    _loadFileSystemData();
  }

  // 缓存AList文件信息
  final Map<String, dynamic> _alistFileCache = {};

  Future<void> _loadFileSystemData() async {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _currentFilePath = videoState.currentVideoPath;
      _currentAnimeTitle = videoState.animeTitle;

      debugPrint('[播放列表] 开始加载文件系统数据');
      debugPrint('[播放列表] _currentFilePath: $_currentFilePath');
      debugPrint('[播放列表] _currentAnimeTitle: $_currentAnimeTitle');

      if (_currentFilePath != null) {
        // 检查是否为Jellyfin流媒体URL
        if (_currentFilePath!.startsWith('jellyfin://')) {
          await _loadJellyfinEpisodes();
          return; // 直接返回，不执行本地文件逻辑
        }

        // 检查是否为Emby流媒体URL
        if (_currentFilePath!.startsWith('emby://')) {
          await _loadEmbyEpisodes();
          return; // 直接返回，不执行本地文件逻辑
        }

        // 检查是否为AList格式URL (主机/d/paths)
        if (_isAlistUrl(_currentFilePath!)) {
          await _loadAlistEpisodes();
          return; // 直接返回，不执行本地文件逻辑
        }

        final currentFile = File(_currentFilePath!);
        final directory = currentFile.parent;

        if (directory.existsSync()) {
          // 获取目录中的所有视频文件
          final videoExtensions = [
            '.mp4',
            '.mkv',
            '.avi',
            '.mov',
            '.wmv',
            '.flv',
            '.webm',
            '.m4v',
            '.3gp',
            '.ts',
            '.m2ts'
          ];
          final videoFiles = directory
              .listSync()
              .whereType<File>()
              .where((file) => videoExtensions
                  .any((ext) => file.path.toLowerCase().endsWith(ext)))
              .toList();

          // 按文件名排序
          videoFiles.sort(
              (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

          _fileSystemEpisodes = videoFiles.map((file) => file.path).toList();
          _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;

          debugPrint('[播放列表] 找到 ${_fileSystemEpisodes.length} 个视频文件');
        }
      }

      if (!_hasFileSystemData) {
        throw Exception('目录中没有找到视频文件');
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[播放列表] 加载文件系统数据失败: $e');
      setState(() {
        _error = '加载播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  // 检查URL是否为AList格式 (主机/d/paths)
  bool _isAlistUrl(String url) {
    // 检查是否符合 AList URL 格式: 主机/d/ /dav/ 路径
    final alistPattern =
        RegExp(r'^https?://(?:[^/]+:)?[^/]+@[^/]+/(?:d|dav)/.*$');
    return alistPattern.hasMatch(url);
  }

  // 从AList URL中提取路径
  String _extractAlistPath(String url) {
    // 从 URL 中提取 /d/ /dav/ 后面的路径部分
    final match = RegExp(r'(?:/d|/dav)/(.*)$').firstMatch(url);
    if (match != null && match.groupCount > 0) {
      return '/${match.group(1)!}';
    }
    return '/';
  }

  // 从AList URL中提取基础URL
  String _extractAlistBaseUrl(String url) {
    // 提取协议和主机部分
    // 匹配包含账号:密码的基础URL格式
    final match = RegExp(r'^(https?://(?:[^/]+:)?[^/]+@[^/]+)').firstMatch(url);
    if (match != null && match.groupCount > 0) {
      return match.group(1)!;
    }
    return '';
  }

// 用Uri解析alist baseurl，返回map，包含账号、密码、主机
  Map<String, dynamic> _parseAlistBaseUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);

    final scheme = uri.scheme; // 协议
    final host = uri.host; // 主机
    final port =
        uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80); // 端口 (可选)
    final userInfo = uri.userInfo; // "user:pwd"

    final username = userInfo.contains(':') ? userInfo.split(':')[0] : userInfo;
    final password = userInfo.contains(':') ? userInfo.split(':')[1] : '';

    // 如果你想要 Map 返回：
    final Map<String, dynamic> result = {
      'scheme': scheme,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    };
    debugPrint('[播放列表] 解析AList基础URL: $result');
    return result;
  }

  // 加载AList目录中的视频文件
  Future<void> _loadAlistEpisodes() async {
    try {
      if (_currentFilePath == null) {
        throw Exception('当前文件路径为空');
      }

      // 提取基础URL和路径
      final baseUrl = _extractAlistBaseUrl(_currentFilePath!);
      final hostInfo = _parseAlistBaseUrl(baseUrl);

      final path = _extractAlistPath(_currentFilePath!);

      debugPrint('[播放列表] AList模式: baseUrl=$baseUrl, path=$path');

      // 初始化AList服务
      await AlistService.instance.initialize();

      // 查找匹配的主机
      final matchingHost = AlistService.instance.hosts.firstWhere(
        (host) =>
            host.baseUrl ==
            '${hostInfo['scheme']}://${hostInfo['host']}:${hostInfo['port']}',
        orElse: () => throw Exception('未找到匹配的AList服务器: $baseUrl'),
      );

      // 设置为活动主机
      await AlistService.instance.setActiveHost(matchingHost.id);

      // 获取目录的父目录（如果有）
      String parentPath = path;
      if (path != '/') {
        final pathParts = path.split('/')..removeLast();
        parentPath = pathParts.join('/') + (pathParts.length > 1 ? '/' : '');
      }

      // 获取父目录中的所有文件
      final files = await AlistService.instance.getFileList(path: parentPath);

      // 过滤出视频文件
      final videoFiles = files.where((file) => file.isVideo).toList();

      if (videoFiles.isEmpty) {
        throw Exception('AList目录中没有找到视频文件');
      }

      // 按文件名排序
      videoFiles
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // 缓存文件信息并转换为播放列表格式
      _alistFileCache.clear();
      _fileSystemEpisodes = videoFiles.map((file) {
        final filePath =
            '${baseUrl}/d/${parentPath == '/' ? '' : parentPath.substring(1)}/${file.name}';
        _alistFileCache[filePath] = file;
        return filePath;
      }).toList();

      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;

      debugPrint('[播放列表] AList模式: 找到 ${_fileSystemEpisodes.length} 个视频文件');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[播放列表] 加载AList文件失败: $e');
      setState(() {
        _error = '加载AList播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadJellyfinEpisodes() async {
    try {
      // 解析当前的Jellyfin URL获取episodeId
      final episodeId = _currentFilePath!.replaceFirst('jellyfin://', '');

      // 通过episodeId获取剧集详情，然后获取同一季的所有剧集
      final episodeInfo =
          await JellyfinService.instance.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        throw Exception('无法获取Jellyfin剧集信息');
      }

      // 获取该季的所有剧集
      final episodes = await JellyfinService.instance
          .getSeasonEpisodes(episodeInfo.seriesId!, episodeInfo.seasonId!);

      if (episodes.isEmpty) {
        throw Exception('该季没有找到剧集');
      }

      // 按集数排序
      episodes
          .sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));

      // 缓存剧集信息并转换为播放列表格式
      _jellyfinEpisodeCache.clear();
      _fileSystemEpisodes = episodes.map((ep) {
        final episodeUrl = 'jellyfin://${ep.id}';
        _jellyfinEpisodeCache[ep.id] = {
          'name': ep.name,
          'indexNumber': ep.indexNumber,
          'seriesName': ep.seriesName,
        };
        return episodeUrl;
      }).toList();
      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;

      debugPrint('[播放列表] Jellyfin模式: 找到 ${_fileSystemEpisodes.length} 个剧集');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[播放列表] 加载Jellyfin剧集失败: $e');
      setState(() {
        _error = '加载Jellyfin播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadEmbyEpisodes() async {
    try {
      // 解析当前的Emby URL获取episodeId
      final embyPath = _currentFilePath!.replaceFirst('emby://', '');
      final pathParts = embyPath.split('/');
      final episodeId = pathParts.last; // 只使用最后一部分作为episodeId

      // 通过episodeId获取剧集详情，然后获取同一季的所有剧集
      final episodeInfo =
          await EmbyService.instance.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        throw Exception('无法获取Emby剧集信息');
      }

      // 获取该季的所有剧集
      final episodes = await EmbyService.instance
          .getSeasonEpisodes(episodeInfo.seriesId!, episodeInfo.seasonId!);

      if (episodes.isEmpty) {
        throw Exception('该季没有找到剧集');
      }

      // 按集数排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0)
            ? 999999
            : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0)
            ? 999999
            : b.indexNumber!;
        return aIndex.compareTo(bIndex);
      });

      // 缓存剧集信息并转换为播放列表格式
      _embyEpisodeCache.clear();
      _fileSystemEpisodes = episodes.map((ep) {
        final episodeUrl = 'emby://${ep.id}';
        _embyEpisodeCache[ep.id] = {
          'name': ep.name,
          'indexNumber': ep.indexNumber,
          'seriesName': ep.seriesName,
        };
        return episodeUrl;
      }).toList();
      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;

      debugPrint('[播放列表] Emby模式: 找到 ${_fileSystemEpisodes.length} 个剧集');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[播放列表] 加载Emby剧集失败: $e');
      setState(() {
        _error = '加载Emby播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playEpisode(String filePath) async {
    try {
      debugPrint('[播放列表] 开始播放剧集: $filePath');

      final videoState = Provider.of<VideoPlayerState>(context, listen: false);

      if (mounted) {
        // 检查是否为Jellyfin URL
        if (filePath.startsWith('jellyfin://')) {
          // Jellyfin流媒体模式：使用完整的弹幕映射和API获取逻辑
          final episodeId = filePath.replaceFirst('jellyfin://', '');
          final episodeInfo =
              await JellyfinService.instance.getEpisodeDetails(episodeId);

          if (episodeInfo == null) {
            throw Exception('无法获取Jellyfin剧集信息');
          }

          // 获取实际的流媒体URL
          final actualUrl = JellyfinService.instance.getStreamUrl(episodeId);
          debugPrint('[播放列表] 获取Jellyfin流媒体URL: $actualUrl');

          // 尝试获取弹幕映射
          int? animeId;
          int? episodeIdForDanmaku;

          try {
            final mapping = await JellyfinEpisodeMappingService.instance
                .getEpisodeMapping(episodeId);
            if (mapping != null) {
              animeId = mapping['dandanplay_anime_id'] as int?;
              episodeIdForDanmaku = mapping['dandanplay_episode_id'] as int?;
              debugPrint(
                  '[播放列表] 找到剧集弹幕映射: animeId=$animeId, episodeId=$episodeIdForDanmaku');
            } else {
              debugPrint('[播放列表] 未找到剧集弹幕映射，将进行自动匹配');
            }
          } catch (e) {
            debugPrint('[播放列表] 获取剧集弹幕映射失败: $e');
          }

          // 创建带有弹幕信息的历史项
          final historyItem = await _createJellyfinHistoryItem(
              episodeInfo, animeId, episodeIdForDanmaku);

          // 按照剧集导航的方式，使用Jellyfin协议URL作为标识符，HTTP URL作为实际播放源
          await videoState.initializePlayer(filePath, // 使用Jellyfin协议URL作为标识符
              historyItem: historyItem,
              actualPlayUrl: actualUrl // HTTP URL作为实际播放源
              );
          debugPrint('[播放列表] Jellyfin剧集播放完成');
        } else if (filePath.startsWith('emby://')) {
          // Emby流媒体模式：使用完整的弹幕映射和API获取逻辑
          final embyPath = filePath.replaceFirst('emby://', '');
          final pathParts = embyPath.split('/');
          final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
          final episodeInfo =
              await EmbyService.instance.getEpisodeDetails(episodeId);

          if (episodeInfo == null) {
            throw Exception('无法获取Emby剧集信息');
          }

          // 获取实际的流媒体URL
          final actualUrl = await EmbyService.instance.getStreamUrl(episodeId);
          debugPrint('[播放列表] 获取Emby流媒体URL: $actualUrl');

          // 尝试获取弹幕映射
          int? animeId;
          int? episodeIdForDanmaku;

          try {
            final mapping = await EmbyEpisodeMappingService.instance
                .getEpisodeMapping(episodeId);
            if (mapping != null) {
              animeId = mapping['dandanplay_anime_id'] as int?;
              episodeIdForDanmaku = mapping['dandanplay_episode_id'] as int?;
              debugPrint(
                  '[播放列表] 找到Emby剧集弹幕映射: animeId=$animeId, episodeId=$episodeIdForDanmaku');
            } else {
              debugPrint('[播放列表] 未找到Emby剧集弹幕映射，将进行自动匹配');
            }
          } catch (e) {
            debugPrint('[播放列表] 获取Emby剧集弹幕映射失败: $e');
          }

          // 创建带有弹幕信息的历史项
          final historyItem = await _createEmbyHistoryItem(
              episodeInfo, animeId, episodeIdForDanmaku);

          // 按照剧集导航的方式，使用Emby协议URL作为标识符，HTTP URL作为实际播放源
          await videoState.initializePlayer(filePath, // 使用Emby协议URL作为标识符
              historyItem: historyItem,
              actualPlayUrl: actualUrl // HTTP URL作为实际播放源
              );
          debugPrint('[播放列表] Emby剧集播放完成');
        } else if (_isAlistUrl(filePath)) {
          // AList模式：直接使用URL播放
          debugPrint('[播放列表] AList模式播放: $filePath');

          // 为AList文件创建历史项
          final fileName = filePath.split('/').last;
          final historyItem = WatchHistoryItem(
            filePath: filePath,
            animeName: _currentAnimeTitle ?? 'Unknown',
            episodeTitle: fileName,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );

          // 直接使用AList URL播放
          await videoState.initializePlayer(filePath, historyItem: historyItem);
          debugPrint('[播放列表] AList文件播放完成');
        } else {
          // 本地文件模式：保持原有逻辑
          final file = File(filePath);
          if (!file.existsSync()) {
            throw Exception('文件不存在: $filePath');
          }

          await videoState.initializePlayer(filePath);
          debugPrint('[播放列表] 文件路径播放完成');
        }

        // 播放成功后关闭菜单
        if (mounted) {
          widget.onClose();
        }
      } else {
        debugPrint('[播放列表] 组件已卸载，取消播放');
      }
    } catch (e) {
      debugPrint('[播放列表] 播放剧集失败: $e');

      // 发生错误时也要关闭菜单
      if (mounted) {
        widget.onClose();

        MessageHelper.showMessage(
          context,
          '播放失败：$e',
          isError: true,
        );
      }
    }
  }

  String _getEpisodeDisplayName(String filePath) {
    // 检查是否为Jellyfin URL
    if (filePath.startsWith('jellyfin://')) {
      final episodeId = filePath.replaceFirst('jellyfin://', '');
      final cachedInfo = _jellyfinEpisodeCache[episodeId];
      if (cachedInfo != null) {
        final indexNumber = cachedInfo['indexNumber'] as int?;
        final name = cachedInfo['name'] as String?;
        if (indexNumber != null && name != null) {
          return '第$indexNumber话 - $name';
        } else if (name != null) {
          return name;
        }
      }
      return 'Episode $episodeId'; // 默认显示
    }

    // 检查是否为Emby URL
    if (filePath.startsWith('emby://')) {
      final embyPath = filePath.replaceFirst('emby://', '');
      final pathParts = embyPath.split('/');
      final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
      final cachedInfo = _embyEpisodeCache[episodeId];
      if (cachedInfo != null) {
        final indexNumber = cachedInfo['indexNumber'] as int?;
        final name = cachedInfo['name'] as String?;
        if (indexNumber != null && name != null) {
          return '第$indexNumber话 - $name';
        } else if (name != null) {
          return name;
        }
      }
      return 'Episode $episodeId'; // 默认显示
    }

    // 检查是否为AList URL
    if (_isAlistUrl(filePath)) {
      final cachedFile = _alistFileCache[filePath];
      if (cachedFile != null) {
        return cachedFile.name;
      }
      // 如果没有缓存，直接返回文件名
      final fileName = filePath.split('/').last;
      return fileName;
    }

    // 本地文件模式：保持原有逻辑
    final fileName = filePath.split('/').last;
    // 移除文件扩展名
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return nameWithoutExt;
  }

  bool _isCurrentEpisode(String filePath) {
    return filePath == _currentFilePath;
  }

  /// 创建Jellyfin历史项，包含完整的弹幕映射预测和API获取的准确信息
  Future<WatchHistoryItem> _createJellyfinHistoryItem(
      JellyfinEpisodeInfo episode, int? animeId, int? episodeId) async {
    try {
      int? finalAnimeId = animeId;
      int? finalEpisodeId = episodeId;

      // 如果没有提供映射的弹幕ID，尝试智能预测
      if (finalAnimeId == null || finalEpisodeId == null) {
        debugPrint('[播放列表] 未提供弹幕映射，开始智能预测');

        // 1. 首先尝试获取现有的剧集映射
        final existingMapping = await JellyfinEpisodeMappingService.instance
            .getEpisodeMapping(episode.id);
        if (existingMapping != null) {
          finalEpisodeId = existingMapping['dandanplay_episode_id'] as int?;

          // 通过系列ID获取动画映射
          final animeMapping =
              await JellyfinEpisodeMappingService.instance.getAnimeMapping(
            jellyfinSeriesId: episode.seriesId!,
            jellyfinSeasonId: episode.seasonId,
          );

          if (animeMapping != null) {
            finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
            debugPrint(
                '[播放列表] 从现有映射获取弹幕ID: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
          }
        } else {
          // 2. 如果没有现有映射，尝试智能预测
          debugPrint('[播放列表] 没有现有映射，开始智能预测映射');
          final predictedEpisodeId = await JellyfinEpisodeMappingService
              .instance
              .predictEpisodeMapping(
            jellyfinEpisode: episode,
          );

          if (predictedEpisodeId != null) {
            finalEpisodeId = predictedEpisodeId;

            // 获取对应的动画ID
            final animeMapping =
                await JellyfinEpisodeMappingService.instance.getAnimeMapping(
              jellyfinSeriesId: episode.seriesId!,
              jellyfinSeasonId: episode.seasonId,
            );

            if (animeMapping != null) {
              finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
              debugPrint(
                  '[播放列表] 预测映射成功: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
            }
          } else {
            debugPrint('[播放列表] 智能预测失败，将使用基础信息创建历史项');
          }
        }
      }

      // 如果有映射的弹幕ID，使用DanDanPlay API获取正确的剧集信息
      if (finalAnimeId != null && finalEpisodeId != null) {
        try {
          // 使用DanDanPlay API获取准确的剧集标题，保持标题一致性
          debugPrint(
              '[播放列表] 使用弹幕ID查询剧集信息: animeId=$finalAnimeId, episodeId=$finalEpisodeId');

          // 获取动画详情以获取准确的标题
          final bangumiDetails =
              await DandanplayService.getBangumiDetails(finalAnimeId);

          String? animeTitle;
          String? episodeTitle;

          if (bangumiDetails['success'] == true &&
              bangumiDetails['bangumi'] != null) {
            final bangumi = bangumiDetails['bangumi'];
            animeTitle = bangumi['animeTitle'] as String?;

            // 查找对应的剧集标题
            if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
              final episodes = bangumi['episodes'] as List;
              final targetEpisode = episodes.firstWhere(
                (ep) => ep['episodeId'] == finalEpisodeId,
                orElse: () => null,
              );

              if (targetEpisode != null) {
                episodeTitle = targetEpisode['episodeTitle'] as String?;
                debugPrint('[播放列表] 从DanDanPlay API获取到剧集标题: $episodeTitle');
              }
            }
          }

          // 创建包含正确弹幕信息和标题的历史项
          return WatchHistoryItem(
            filePath: 'jellyfin://${episode.id}',
            animeName: animeTitle ?? episode.seriesName ?? 'Unknown',
            episodeTitle: episodeTitle ?? episode.name,
            animeId: finalAnimeId,
            episodeId: finalEpisodeId,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );
        } catch (e) {
          debugPrint('[播放列表] 获取DanDanPlay剧集信息失败: $e，使用基础信息');
        }
      }

      // 如果没有映射的弹幕ID或获取失败，使用基础信息创建历史项
      debugPrint('[播放列表] 没有映射的弹幕ID，使用基础信息创建历史项');
      return episode.toWatchHistoryItem();
    } catch (e) {
      debugPrint('[播放列表] 创建历史项时出错：$e，使用基础历史项');
      return episode.toWatchHistoryItem();
    }
  }

  /// 创建Emby历史项，包含完整的弹幕映射预测和API获取的准确信息
  Future<WatchHistoryItem> _createEmbyHistoryItem(
      EmbyEpisodeInfo episode, int? animeId, int? episodeId) async {
    try {
      int? finalAnimeId = animeId;
      int? finalEpisodeId = episodeId;

      // 如果没有提供映射的弹幕ID，尝试智能预测
      if (finalAnimeId == null || finalEpisodeId == null) {
        debugPrint('[播放列表] 未提供Emby弹幕映射，开始智能预测');

        // 1. 首先尝试获取现有的剧集映射
        final existingMapping = await EmbyEpisodeMappingService.instance
            .getEpisodeMapping(episode.id);
        if (existingMapping != null) {
          finalEpisodeId = existingMapping['dandanplay_episode_id'] as int?;

          // 通过系列ID获取动画映射
          final animeMapping =
              await EmbyEpisodeMappingService.instance.getAnimeMapping(
            embySeriesId: episode.seriesId!,
            embySeasonId: episode.seasonId,
          );

          if (animeMapping != null) {
            finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
            debugPrint(
                '[播放列表] 从现有Emby映射获取弹幕ID: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
          }
        } else {
          // 2. 如果没有现有映射，尝试智能预测
          debugPrint('[播放列表] 没有现有Emby映射，开始智能预测映射');
          final predictedEpisodeId =
              await EmbyEpisodeMappingService.instance.predictEpisodeId(
            embyEpisodeId: episode.id,
            embyIndexNumber: episode.indexNumber ?? 0,
            embySeriesId: episode.seriesId!,
            embySeasonId: episode.seasonId,
          );

          if (predictedEpisodeId != null) {
            finalEpisodeId = predictedEpisodeId;

            // 获取对应的动画ID
            final animeMapping =
                await EmbyEpisodeMappingService.instance.getAnimeMapping(
              embySeriesId: episode.seriesId!,
              embySeasonId: episode.seasonId,
            );

            if (animeMapping != null) {
              finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
              debugPrint(
                  '[播放列表] Emby预测映射成功: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
            }
          } else {
            debugPrint('[播放列表] Emby智能预测失败，将使用基础信息创建历史项');
          }
        }
      }

      // 如果有映射的弹幕ID，使用DanDanPlay API获取正确的剧集信息
      if (finalAnimeId != null && finalEpisodeId != null) {
        try {
          // 使用DanDanPlay API获取准确的剧集标题，保持标题一致性
          debugPrint(
              '[播放列表] 使用弹幕ID查询Emby剧集信息: animeId=$finalAnimeId, episodeId=$finalEpisodeId');

          // 获取动画详情以获取准确的标题
          final bangumiDetails =
              await DandanplayService.getBangumiDetails(finalAnimeId);

          String? animeTitle;
          String? episodeTitle;

          if (bangumiDetails['success'] == true &&
              bangumiDetails['bangumi'] != null) {
            final bangumi = bangumiDetails['bangumi'];
            animeTitle = bangumi['animeTitle'] as String?;

            // 查找对应的剧集标题
            if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
              final episodes = bangumi['episodes'] as List;
              final targetEpisode = episodes.firstWhere(
                (ep) => ep['episodeId'] == finalEpisodeId,
                orElse: () => null,
              );

              if (targetEpisode != null) {
                episodeTitle = targetEpisode['episodeTitle'] as String?;
                debugPrint('[播放列表] 从DanDanPlay API获取到Emby剧集标题: $episodeTitle');
              }
            }
          }

          // 创建包含正确弹幕信息和标题的历史项
          return WatchHistoryItem(
            filePath: 'emby://${episode.id}',
            animeName: animeTitle ?? episode.seriesName ?? 'Unknown',
            episodeTitle: episodeTitle ?? episode.name,
            animeId: finalAnimeId,
            episodeId: finalEpisodeId,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );
        } catch (e) {
          debugPrint('[播放列表] 获取DanDanPlay Emby剧集信息失败: $e，使用基础信息');
        }
      }

      // 如果没有映射的弹幕ID或获取失败，使用基础信息创建历史项
      debugPrint('[播放列表] 没有映射的Emby弹幕ID，使用基础信息创建历史项');
      return episode.toWatchHistoryItem();
    } catch (e) {
      debugPrint('[播放列表] 创建Emby历史项时出错：$e，使用基础历史项');
      return episode.toWatchHistoryItem();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseSettingsMenu(
      title: '播放列表',
      onClose: widget.onClose,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 动画标题
          if (_currentAnimeTitle != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _currentAnimeTitle!,
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),

          // 内容区域 - 移除固定高度限制
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '加载播放列表中...',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _loadFileSystemData();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (!_hasFileSystemData || _fileSystemEpisodes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              color: Colors.white54,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              '目录中没有找到视频文件',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 添加顶部边距
        const SizedBox(height: 8),
        // 使用Column和多个Container替代ListView.builder
        for (int index = 0; index < _fileSystemEpisodes.length; index++)
          Builder(
            builder: (context) {
              final filePath = _fileSystemEpisodes[index];
              final isCurrentEpisode = _isCurrentEpisode(filePath);
              final displayName = _getEpisodeDisplayName(filePath);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isCurrentEpisode
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: isCurrentEpisode
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.5), width: 1)
                      : null,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    displayName,
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: isCurrentEpisode
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.87),
                      fontSize: 14,
                      fontWeight: isCurrentEpisode
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCurrentEpisode
                      ? const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                  onTap: isCurrentEpisode
                      ? null // 当前剧集不可点击
                      : () => _playEpisode(filePath),
                  enabled: !isCurrentEpisode,
                ),
              );
            },
          ),
        // 添加底部边距，确保最后一项不被遮挡
        const SizedBox(height: 16),
      ],
    );
  }
}
