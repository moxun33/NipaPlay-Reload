import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../models/alist_model.dart';
import '../models/playable_item.dart';
import '../models/watch_history_model.dart';
import '../services/alist_service.dart';

class AlistProvider extends ChangeNotifier {
  final AlistService _alistService = AlistService.instance;
  List<AlistFile> _currentFiles = [];
  String _currentPath = '/';
  bool _isLoading = false;
  String? _errorMessage;
  bool _isConnected = false;

  List<AlistHost> get hosts => _alistService.hosts;
  List<String> get activeHostIds => _alistService.activeHostIds;
  List<AlistHost> get activeHosts => _alistService.activeHosts;
  AlistHost? get activeHost => _alistService.activeHost;
  String? get activeHostId => activeHostIds.isNotEmpty ? activeHostIds.first : null;
  List<AlistFile> get currentFiles => List.unmodifiable(_currentFiles);
  String get currentPath => _currentPath;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  bool get hasActiveHost => _alistService.activeHost != null;

  // 初始化Provider
  Future<void> initialize() async {
    await _alistService.initialize();
    notifyListeners();
  }

  // 添加新的AList服务器
  Future<AlistHost> addHost(String displayName, {
    required String baseUrl,
    String username = '',
    String password = '',
    bool enabled = true,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final host = await _alistService.addHost(
        displayName: displayName,
        baseUrl: baseUrl,
        username: username,
        password: password,
        enabled: enabled,
      );
      
      _isConnected = host.isOnline;
      _errorMessage = host.isOnline ? null : '认证成功，但连接状态未知';
      
      // 如果是第一个主机，立即加载根目录
      if (_alistService.hosts.length == 1 && host.isOnline) {
        await navigateTo('/');
      }
      
      notifyListeners();
      return host;
    } catch (e) {
      _errorMessage = '添加AList服务器失败: $e';
      debugPrint('添加AList服务器失败: $e');
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 移除AList服务器
  Future<void> removeHost(String hostId) async {
    try {
      await _alistService.removeHost(hostId);
      
      // 如果移除的是当前活动主机，清空当前文件列表
      if (hostId == activeHostId) {
        _currentFiles = [];
        _currentPath = '/';
        _isConnected = false;
      }
      
      notifyListeners();
    } catch (e) {
      _errorMessage = '移除AList服务器失败: $e';
      debugPrint('移除AList服务器失败: $e');
      notifyListeners();
    }
  }

  // 更新AList服务器配置
  Future<AlistHost> updateHost(String hostId, {
    String? displayName,
    String? baseUrl,
    String? username,
    String? password,
    bool? enabled,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final host = await _alistService.updateHost(
        hostId: hostId,
        displayName: displayName,
        baseUrl: baseUrl,
        username: username,
        password: password,
        enabled: enabled,
      );
      
      // 如果更新的是当前活动主机，更新连接状态
      if (hostId == activeHostId) {
        _isConnected = host.isOnline;
        // 如果主机重新连接成功，重新加载当前目录
        if (host.isOnline && _currentPath != '/') {
          await navigateTo(_currentPath);
        }
      }
      
      notifyListeners();
      return host;
    } catch (e) {
      _errorMessage = '更新AList服务器失败: $e';
      debugPrint('更新AList服务器失败: $e');
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 设置活动的AList服务器（兼容旧版API）
  Future<void> setActiveHost(String hostId) async {
    try {
      await _alistService.setActiveHost(hostId);
      
      // 清空当前文件列表并导航到根目录
      _currentFiles = [];
      _currentPath = '/';
      _isConnected = activeHost?.isOnline ?? false;
      
      // 尝试加载根目录
      if (_isConnected) {
        await navigateTo('/');
      }
      
      notifyListeners();
    } catch (e) {
      _errorMessage = '设置活动AList服务器失败: $e';
      debugPrint('设置活动AList服务器失败: $e');
      notifyListeners();
    }
  }
  
  // 添加主机到激活列表
  Future<void> addActiveHost(String hostId) async {
    try {
      await _alistService.addActiveHost(hostId);
      notifyListeners();
    } catch (e) {
      _errorMessage = '添加激活AList服务器失败: $e';
      debugPrint('添加激活AList服务器失败: $e');
      notifyListeners();
    }
  }
  
  // 从激活列表中移除主机
  Future<void> removeActiveHost(String hostId) async {
    try {
      await _alistService.removeActiveHost(hostId);
      
      // 如果移除的是当前活动主机，清空当前文件列表
      if (activeHostId == hostId) {
        _currentFiles = [];
        _currentPath = '/';
        _isConnected = activeHost?.isOnline ?? false;
      }
      
      notifyListeners();
    } catch (e) {
      _errorMessage = '移除激活AList服务器失败: $e';
      debugPrint('移除激活AList服务器失败: $e');
      notifyListeners();
    }
  }

  // 导航到指定路径
  Future<void> navigateTo(String path, {String password = '',   bool? refresh}) async {
    if (activeHost == null) {
      _errorMessage = '未选择AList服务器';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _currentPath = path;
    notifyListeners();

    try {
      final files = await _alistService.getFileList(
        path: path,
        password: password,
      );
      
      // 按文件夹优先，然后按名称排序
    /*   files.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }); */
      
      _currentFiles = files;
      _isConnected = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = '导航到 $path 失败: $e';
      debugPrint('导航到 $path 失败: $e');
      _isConnected = false;
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 返回上一级目录
  Future<void> navigateUp() async {
    if (_currentPath == '/') return;
    
    final parts = _currentPath.split('/');
    final parentPath = parts.length > 1 
        ? parts.sublist(0, parts.length - 1).join('/') 
        : '/';
    
    await navigateTo(parentPath);
  }

  // 构建可播放项
  PlayableItem buildPlayableItem(AlistFile file) {
    if (activeHost == null) {
      throw Exception('未选择AList服务器');
    }
    
    final streamUrl = _alistService.buildFileUrl('$_currentPath/${file.name}');
    final historyItem = WatchHistoryItem(
      filePath: streamUrl,
      animeName: file.name,
      episodeTitle: file.name,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
      isFromScan: false,
      watchProgress: 0,
    );
    
    return PlayableItem(
      videoPath: streamUrl,
      title: file.name,
      historyItem: historyItem,
      actualPlayUrl: streamUrl,
    );
  }

  // 刷新当前目录
  Future<void> refreshCurrentDirectory() async {
    if (_currentPath.isNotEmpty) {
      await navigateTo(_currentPath, refresh: true);
    }
  }

  // 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // 静态方法：创建Provider
  static ChangeNotifierProvider<AlistProvider> createProvider() {
    return ChangeNotifierProvider(
      create: (_) {
        final provider = AlistProvider();
        provider.initialize();
        return provider;
      },
    );
  }
}