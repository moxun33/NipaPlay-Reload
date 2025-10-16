import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';

class SharedRemoteLibraryProvider extends ChangeNotifier {
  static const String _hostsPrefsKey = 'shared_remote_hosts';
  static const String _activeHostIdKey = 'shared_remote_active_host';

  SharedRemoteLibraryProvider() {
    _loadPersistedHosts();
  }

  final List<SharedRemoteHost> _hosts = [];
  String? _activeHostId;
  List<SharedRemoteAnimeSummary> _animeSummaries = [];
  final Map<int, List<SharedRemoteEpisode>> _episodeCache = {};
  bool _isLoading = false;
  String? _errorMessage;
  bool _isInitializing = true;
  bool _autoRefreshPaused = false;
  DateTime? _lastRefreshFailureAt;

  List<SharedRemoteHost> get hosts => List.unmodifiable(_hosts);
  String? get activeHostId => _activeHostId;
  SharedRemoteHost? get activeHost {
    if (_activeHostId == null) return null;
    try {
      return _hosts.firstWhere((host) => host.id == _activeHostId);
    } catch (_) {
      return null;
    }
  }
  List<SharedRemoteAnimeSummary> get animeSummaries => List.unmodifiable(_animeSummaries);
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  bool get hasActiveHost => _activeHostId != null && _hosts.any((h) => h.id == _activeHostId);
  bool get hasReachableActiveHost => activeHost?.isOnline == true;

  Future<void> _loadPersistedHosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHosts = prefs.getString(_hostsPrefsKey);
      final savedActiveHost = prefs.getString(_activeHostIdKey);
      if (rawHosts != null && rawHosts.isNotEmpty) {
        final storedHosts = SharedRemoteHost.decodeList(rawHosts);
        _hosts
          ..clear()
          ..addAll(storedHosts);
      }
      if (savedActiveHost != null &&
          _hosts.any((element) => element.id == savedActiveHost)) {
        _activeHostId = savedActiveHost;
      }
    } catch (e) {
      _errorMessage = '加载远程媒体库配置失败: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
      if (_activeHostId != null) {
        refreshLibrary();
      }
    }
  }

  Future<void> _persistHosts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostsPrefsKey, SharedRemoteHost.encodeList(_hosts));
    if (_activeHostId != null) {
      await prefs.setString(_activeHostIdKey, _activeHostId!);
    } else {
      await prefs.remove(_activeHostIdKey);
    }
  }

  Future<SharedRemoteHost> addHost({
    required String displayName,
    required String baseUrl,
  }) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final host = SharedRemoteHost(id: id, displayName: displayName, baseUrl: normalizedUrl);
    _hosts.add(host);
    _activeHostId = id;
    await _persistHosts();
    notifyListeners();
    await refreshLibrary(userInitiated: true);
    return host;
  }

  Future<void> removeHost(String hostId) async {
    _hosts.removeWhere((host) => host.id == hostId);
    if (_activeHostId == hostId) {
      _activeHostId = _hosts.isNotEmpty ? _hosts.first.id : null;
      _animeSummaries = [];
      _episodeCache.clear();
    }
    await _persistHosts();
    notifyListeners();
    if (_activeHostId != null) {
      await refreshLibrary(userInitiated: true);
    }
  }

  Future<void> setActiveHost(String hostId) async {
    if (_activeHostId == hostId) return;
    if (!_hosts.any((host) => host.id == hostId)) return;
    _activeHostId = hostId;
    _animeSummaries = [];
    _episodeCache.clear();
    await _persistHosts();
    notifyListeners();
    await refreshLibrary(userInitiated: true);
  }

  Future<void> refreshLibrary({bool userInitiated = false}) async {
    final host = activeHost;
    if (host == null) {
      return;
    }

    if (userInitiated) {
      _autoRefreshPaused = false;
      _lastRefreshFailureAt = null;
    } else if (_autoRefreshPaused) {
      final message = _lastRefreshFailureAt != null
          ? '⏳ [共享媒体] 自动刷新已暂停（上次失败 ${_lastRefreshFailureAt!.toLocal()}），等待手动刷新'
          : '⏳ [共享媒体] 自动刷新已暂停，等待手动刷新';
      debugPrint(message);
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/share/animes');
      debugPrint('📡 [共享媒体] 开始请求: $uri');
      debugPrint('📡 [共享媒体] 主机信息: ${host.displayName} (${host.baseUrl})');

      final response = await _sendGetRequest(uri, timeout: const Duration(seconds: 10));

      debugPrint('📡 [共享媒体] 响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('❌ [共享媒体] HTTP错误: ${response.statusCode}, body: ${response.body}');
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = (payload['items'] ?? payload['data'] ?? []) as List<dynamic>;

      debugPrint('✅ [共享媒体] 成功获取 ${items.length} 个番剧');

      _animeSummaries = items
          .map((item) => SharedRemoteAnimeSummary.fromJson(item as Map<String, dynamic>))
          .toList();
      _animeSummaries.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
      _episodeCache.clear();
      _updateHostStatus(host.id, isOnline: true, lastError: null);
      _autoRefreshPaused = false;
      _lastRefreshFailureAt = null;
    } catch (e, stackTrace) {
      debugPrint('❌ [共享媒体] 请求失败: $e');
      debugPrint('❌ [共享媒体] 错误类型: ${e.runtimeType}');
      if (e is TimeoutException) {
        debugPrint('ℹ️ [共享媒体] 请求超时，已暂停自动刷新等待手动重试');
      } else {
        debugPrint('❌ [共享媒体] 堆栈跟踪:\n$stackTrace');
      }

      String friendlyError;
      if (e.toString().contains('SocketException') || e.toString().contains('Connection')) {
        if (e.toString().contains('No route to host') || e.toString().contains('errno = 65')) {
          friendlyError = '无法连接到主机 ${host.baseUrl}\n错误详情: $e';
          debugPrint('🔍 [共享媒体诊断] 网络路由问题，可能原因：');
          debugPrint('  1. 设备不在同一局域网');
          debugPrint('  2. 主机IP变更了');
          debugPrint('  3. 防火墙阻止连接');
        } else if (e.toString().contains('Connection refused')) {
          friendlyError = '连接被拒绝，请确认主机已开启远程访问服务';
          debugPrint('🔍 [共享媒体诊断] 端口拒绝连接，可能原因：');
          debugPrint('  1. 远程访问服务未启动');
          debugPrint('  2. 端口号错误');
        } else if (e.toString().contains('timed out') || e.toString().contains('TimeoutException')) {
          friendlyError = '连接超时，请检查网络连接或主机是否在线';
          debugPrint('🔍 [共享媒体诊断] 连接超时，可能原因：');
          debugPrint('  1. 网络延迟过高');
          debugPrint('  2. 主机负载过高');
          debugPrint('  3. 主机未响应');
        } else {
          friendlyError = '网络连接失败: $e';
        }
      } else if (e.toString().contains('HTTP')) {
        friendlyError = '服务器响应错误: $e';
      } else {
        friendlyError = '同步失败: $e';
      }
      _animeSummaries = [];
      _episodeCache.clear();
      _errorMessage = friendlyError;
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
      if (!userInitiated) {
        _autoRefreshPaused = true;
        _lastRefreshFailureAt = DateTime.now();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      await _persistHosts();
    }
  }

  Future<List<SharedRemoteEpisode>> loadAnimeEpisodes(int animeId, {bool force = false}) async {
    if (!force && _episodeCache.containsKey(animeId)) {
      return _episodeCache[animeId]!;
    }

    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程媒体库');
    }

    try {
      final uri = Uri.parse('${host.baseUrl}/api/media/local/share/animes/$animeId');
      debugPrint('📡 [剧集加载] 请求: $uri');

      final response = await _sendGetRequest(uri, timeout: const Duration(seconds: 10));

      debugPrint('📡 [剧集加载] 响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('❌ [剧集加载] HTTP错误: ${response.statusCode}');
        throw Exception('HTTP ${response.statusCode}');
      }

      final payload = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final episodes = (payload['data']?['episodes'] ?? payload['episodes'] ?? []) as List<dynamic>;
      final episodeList = episodes
          .map((episode) => SharedRemoteEpisode.fromJson(episode as Map<String, dynamic>))
          .toList();

      debugPrint('✅ [剧集加载] 成功获取 ${episodeList.length} 集');

      _episodeCache[animeId] = episodeList;

      // 如果返回包含 anime 信息，但 summary 还没更新，则更新一下卡片显示
      final data = payload['data']?['anime'] ?? payload['anime'];
      if (data is Map<String, dynamic>) {
        final summaryIndex = _animeSummaries.indexWhere((element) => element.animeId == animeId);
        if (summaryIndex != -1 && data['lastWatchTime'] != null) {
          final updatedSummary = SharedRemoteAnimeSummary.fromJson({
            'animeId': animeId,
            'name': data['name'] ?? _animeSummaries[summaryIndex].name,
            'nameCn': data['nameCn'] ?? _animeSummaries[summaryIndex].nameCn,
            'summary': data['summary'] ?? _animeSummaries[summaryIndex].summary,
            'imageUrl': data['imageUrl'] ?? _animeSummaries[summaryIndex].imageUrl,
            'lastWatchTime': data['lastWatchTime'],
            'episodeCount': data['episodeCount'] ?? episodeList.length,
            'hasMissingFiles': data['hasMissingFiles'] ?? false,
          });
          _animeSummaries[summaryIndex] = updatedSummary;
          notifyListeners();
        }
      }

      return episodeList;
    } catch (e, stackTrace) {
      debugPrint('❌ [剧集加载] 失败: $e');
      debugPrint('❌ [剧集加载] 错误类型: ${e.runtimeType}');
      debugPrint('❌ [剧集加载] 堆栈:\n$stackTrace');

      if (e.toString().contains('SocketException') || e.toString().contains('Connection')) {
        if (e.toString().contains('No route to host') || e.toString().contains('errno = 65')) {
          throw Exception('无法连接到主机，请检查网络连接\n详情: $e');
        } else if (e.toString().contains('Connection refused')) {
          throw Exception('连接被拒绝，主机服务可能未启动\n详情: $e');
        } else if (e.toString().contains('timed out') || e.toString().contains('TimeoutException')) {
          throw Exception('连接超时，请检查网络或主机状态\n详情: $e');
        }
      }
      rethrow;
    }
  }

  Future<http.Response> _sendGetRequest(Uri uri, {Duration timeout = const Duration(seconds: 10)}) async {
    final sanitizedUri = _sanitizeUri(uri);
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'NipaPlay/1.0',
    };

    final authHeader = _buildBasicAuthHeader(uri);
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    final client = IOClient(_createHttpClient(uri));
    try {
      return await client
          .get(sanitizedUri, headers: headers)
          .timeout(timeout, onTimeout: () {
        throw TimeoutException('请求超时');
      });
    } finally {
      client.close();
    }
  }

  Uri _sanitizeUri(Uri source) {
    return Uri(
      scheme: source.scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: source.path,
      query: source.hasQuery ? source.query : null,
      fragment: source.fragment.isEmpty ? null : source.fragment,
    );
  }

  String? _buildBasicAuthHeader(Uri uri) {
    if (uri.userInfo.isEmpty) {
      return null;
    }

    final separatorIndex = uri.userInfo.indexOf(':');
    String username;
    String password;
    if (separatorIndex >= 0) {
      username = uri.userInfo.substring(0, separatorIndex);
      password = uri.userInfo.substring(separatorIndex + 1);
    } else {
      username = uri.userInfo;
      password = '';
    }

    username = Uri.decodeComponent(username);
    password = Uri.decodeComponent(password);

    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  HttpClient _createHttpClient(Uri uri) {
    final httpClient = HttpClient();
    httpClient.userAgent = 'NipaPlay/1.0';
    httpClient.autoUncompress = false;
    if (_shouldBypassProxy(uri.host)) {
      httpClient.findProxy = (_) => 'DIRECT';
    }
    return httpClient;
  }

  bool _shouldBypassProxy(String host) {
    if (host.isEmpty) {
      return false;
    }

    if (host == 'localhost' || host == '127.0.0.1') {
      return true;
    }

    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (ip.type == InternetAddressType.IPv4) {
        final bytes = ip.rawAddress;
        if (bytes.length == 4) {
          final first = bytes[0];
          final second = bytes[1];
          if (first == 10) return true;
          if (first == 127) return true;
          if (first == 192 && second == 168) return true;
          if (first == 172 && second >= 16 && second <= 31) return true;
        }
      } else if (ip.type == InternetAddressType.IPv6) {
        if (ip.isLoopback) {
          return true;
        }
        final firstByte = ip.rawAddress.isNotEmpty ? ip.rawAddress[0] : 0;
        if (firstByte & 0xfe == 0xfc) {
          return true;
        }
      }
    } else {
      if (host.endsWith('.local')) {
        return true;
      }
    }

    return false;
  }

  Uri buildStreamUri(SharedRemoteEpisode episode) {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择远程媒体库');
    }
    return Uri.parse(host.baseUrl).resolve(episode.streamPath.startsWith('/')
        ? episode.streamPath.substring(1)
        : episode.streamPath);
  }

  WatchHistoryItem buildWatchHistoryItem({
    required SharedRemoteAnimeSummary anime,
    required SharedRemoteEpisode episode,
  }) {
    final streamUri = buildStreamUri(episode).toString();
    return WatchHistoryItem(
      filePath: streamUri,
      animeName: anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
      episodeTitle: episode.title,
      episodeId: episode.episodeId,
      animeId: episode.animeId ?? anime.animeId,
      watchProgress: episode.progress ?? 0,
      lastPosition: 0,
      duration: episode.duration ?? 0,
      lastWatchTime: episode.lastWatchTime ?? DateTime.now(),
      thumbnailPath: anime.imageUrl,
      isFromScan: false,
      videoHash: episode.videoHash,
    );
  }

  PlayableItem buildPlayableItem({
    required SharedRemoteAnimeSummary anime,
    required SharedRemoteEpisode episode,
  }) {
    final watchItem = buildWatchHistoryItem(anime: anime, episode: episode);
    return PlayableItem(
      videoPath: watchItem.filePath,
      title: watchItem.animeName,
      subtitle: episode.title,
      animeId: anime.animeId,
      episodeId: episode.episodeId ?? episode.shareId.hashCode,
      historyItem: watchItem,
      actualPlayUrl: watchItem.filePath,
    );
  }

  Future<void> renameHost(String hostId, String newName) async {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) return;
    _hosts[index] = _hosts[index].copyWith(displayName: newName);
    await _persistHosts();
    notifyListeners();
  }

  Future<void> updateHostUrl(String hostId, String newUrl) async {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) return;
    final normalized = _normalizeBaseUrl(newUrl);
    _hosts[index] = _hosts[index].copyWith(baseUrl: normalized);
    if (_activeHostId == hostId) {
      await refreshLibrary(userInitiated: true);
    }
    await _persistHosts();
    notifyListeners();
  }

  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  void _updateHostStatus(String hostId, {bool? isOnline, String? lastError}) {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) return;
    final current = _hosts[index];
    _hosts[index] = current.copyWith(
      isOnline: isOnline ?? current.isOnline,
      lastConnectedAt: DateTime.now(),
      lastError: lastError,
    );
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
