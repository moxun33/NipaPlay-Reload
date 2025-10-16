import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alist_model.dart';

class AlistService {
  static final AlistService instance = AlistService._internal();

  AlistService._internal();

  // 用于存储和管理AList服务器配置
  final List<AlistHost> _hosts = [];
  final List<String> _activeHostIds = []; // 修改为支持多个激活
  bool _isInitializing = true;

  List<AlistHost> get hosts => List.unmodifiable(_hosts);
  List<String> get activeHostIds => List.unmodifiable(_activeHostIds);
  List<AlistHost> get activeHosts => _hosts.where((host) => host.enabled && _activeHostIds.contains(host.id)).toList();
  AlistHost? get activeHost {
    if (_activeHostIds.isEmpty) return null;
    try {
      return _hosts.firstWhere((host) => _activeHostIds.contains(host.id));
    } catch (_) {
      return null;
    }
  }

  bool get isInitializing => _isInitializing;

  // 初始化服务，加载保存的配置
  Future<void> initialize() async {
    await _loadPersistedHosts();
  }

  // 从SharedPreferences加载保存的主机配置
  Future<void> _loadPersistedHosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHosts = prefs.getString('alist_hosts');
      final savedActiveHosts = prefs.getString('alist_active_hosts');
      if (rawHosts != null && rawHosts.isNotEmpty) {
        final storedHosts = AlistHost.decodeList(rawHosts);
        _hosts
          ..clear()
          ..addAll(storedHosts);
      }
      // 加载多个激活主机
      if (savedActiveHosts != null && savedActiveHosts.isNotEmpty) {
        try {
          final List<String> activeIds = List<String>.from(json.decode(savedActiveHosts));
          _activeHostIds.clear();
          for (final id in activeIds) {
            if (_hosts.any((element) => element.id == id)) {
              _activeHostIds.add(id);
            }
          }
        } catch (e) {
          debugPrint('解析激活主机列表失败: $e');
        }
      }
      // 兼容旧版本的单激活主机配置
      final savedActiveHost = prefs.getString('alist_active_host');
      if (savedActiveHost != null && _activeHostIds.isEmpty &&
          _hosts.any((element) => element.id == savedActiveHost)) {
        _activeHostIds.add(savedActiveHost);
        // 删除旧配置
        await prefs.remove('alist_active_host');
      }
    } catch (e) {
      debugPrint('加载AList配置失败: $e');
    } finally {
      _isInitializing = false;
    }
  }

  // 将主机配置保存到SharedPreferences
  Future<void> _persistHosts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alist_hosts', AlistHost.encodeList(_hosts));
    if (_activeHostIds.isNotEmpty) {
      await prefs.setString('alist_active_hosts', json.encode(_activeHostIds));
    } else {
      await prefs.remove('alist_active_hosts');
    }
  }

  // 添加新的AList服务器配置
  Future<AlistHost> addHost({required String displayName, required String baseUrl, String username = '', String password = '', bool enabled = true}) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final host = AlistHost(
      id: id,
      displayName: displayName,
      baseUrl: normalizedUrl,
      username: username,
      password: password,
      enabled: enabled,
    );

    _hosts.add(host);
    _activeHostIds.add(id); // 默认添加到激活列表
    await _persistHosts();

    // 如果用户名和密码都为空，则跳过认证，标记为在线
    if (username.isEmpty && password.isEmpty) {
      final updatedHost = host.copyWith(
        isOnline: true,
        lastConnectedAt: DateTime.now(),
      );

      final index = _hosts.indexOf(host);
      if (index != -1) {
        _hosts[index] = updatedHost;
        await _persistHosts();
      }

      return updatedHost;
    }

    // 尝试认证并更新主机状态
    try {
      final token = await _authenticate(host);
      final updatedHost = host.copyWith(
        token: token,
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 48)),
        isOnline: true,
        lastConnectedAt: DateTime.now(),
      );

      final index = _hosts.indexOf(host);
      if (index != -1) {
        _hosts[index] = updatedHost;
        await _persistHosts();
      }

      return updatedHost;
    } catch (e) {
      debugPrint('AList认证失败: $e');
      return host;
    }
  }

  // 移除AList服务器配置
  Future<void> removeHost(String hostId) async {
    _hosts.removeWhere((host) => host.id == hostId);
    _activeHostIds.remove(hostId); // 同时从激活列表中移除
    await _persistHosts();
  }

  // 添加主机到激活列表
  Future<void> addActiveHost(String hostId) async {
    if (!_hosts.any((host) => host.id == hostId)) {
      throw Exception('找不到指定的AList服务器');
    }
    if (!_activeHostIds.contains(hostId)) {
      _activeHostIds.add(hostId);
      await _persistHosts();
    }
  }

  // 从激活列表中移除主机
  Future<void> removeActiveHost(String hostId) async {
    if (_activeHostIds.contains(hostId)) {
      _activeHostIds.remove(hostId);
      await _persistHosts();
    }
  }

  // 更新AList服务器配置
  Future<AlistHost> updateHost({
    required String hostId,
    String? displayName,
    String? baseUrl,
    String? username,
    String? password,
    bool? enabled,
  }) async {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) {
      throw Exception('找不到指定的AList服务器');
    }

    final oldHost = _hosts[index];
    final normalizedUrl =
        baseUrl != null ? _normalizeBaseUrl(baseUrl) : oldHost.baseUrl;

    // 创建更新后的主机配置
    final updatedHost = oldHost.copyWith(
      displayName: displayName ?? oldHost.displayName,
      baseUrl: normalizedUrl,
      username: username ?? oldHost.username,
      password: password ?? oldHost.password,
      enabled: enabled ?? oldHost.enabled,
      // 更新URL或凭证时，重置token信息
      token: (baseUrl != null || username != null || password != null)
          ? null
          : oldHost.token,
      tokenExpiresAt: (baseUrl != null || username != null || password != null)
          ? null
          : oldHost.tokenExpiresAt,
      isOnline: false, // 重新连接前标记为离线
    );

    _hosts[index] = updatedHost;
    await _persistHosts();

    // 如果是活动主机且URL或凭证有变化，尝试重新连接
    if (_activeHostIds.contains(hostId) &&
        (baseUrl != null || username != null || password != null)) {
      try {
        final token = await _authenticate(updatedHost);
        final reconnectedHost = updatedHost.copyWith(
          token: token,
          tokenExpiresAt: DateTime.now().add(const Duration(hours: 48)),
          isOnline: true,
          lastConnectedAt: DateTime.now(),
          lastError: null,
        );
        _hosts[index] = reconnectedHost;
        await _persistHosts();
        return reconnectedHost;
      } catch (e) {
        debugPrint('更新AList服务器后重连失败: $e');
        _updateHostStatus(updatedHost.id,
            isOnline: false, lastError: e.toString());
      }
    }

    return _hosts[index];
  }

  // 设置活动的AList服务器（兼容旧版API）
  Future<void> setActiveHost(String hostId) async {
    if (!_hosts.any((host) => host.id == hostId)) return;

    _activeHostIds.clear();
    _activeHostIds.add(hostId);
    await _persistHosts();
  }

  // 认证并获取Token
  Future<String> _authenticate(AlistHost host) async {
    final uri = Uri.parse('${host.baseUrl}/api/auth/login');
    debugPrint('AList认证请求: $uri');

    final client = IOClient(_createHttpClient(uri));
    try {
      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'NipaPlay/1.0',
            },
            body: json.encode({
              'username': host.username,
              'password': host.password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('认证失败: HTTP ${response.statusCode}, ${response.body}');
      }

      final authResponse =
          AlistAuthResponse.fromJson(json.decode(response.body));
      if (authResponse.code != 200) {
        throw Exception('认证失败: ${authResponse.message}');
      }

      return authResponse.data.token;
    } finally {
      client.close();
    }
  }

  // 确保Token有效，如果无效则重新获取
  Future<String> _ensureValidToken(AlistHost host) async {
    // 对于匿名访问（用户名和密码都为空），返回空字符串作为token
    if (host.username.isEmpty && host.password.isEmpty) {
      return '';
    }

    // 检查Token是否存在或已过期
    if (host.token == null ||
        host.tokenExpiresAt == null ||
        host.tokenExpiresAt!.isBefore(DateTime.now())) {
      // 重新认证获取Token
      final token = await _authenticate(host);

      // 更新主机信息
      final updatedHost = host.copyWith(
        token: token,
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 48)),
        isOnline: true,
        lastConnectedAt: DateTime.now(),
      );

      final index = _hosts.indexOf(host);
      if (index != -1) {
        _hosts[index] = updatedHost;
        await _persistHosts();
      }

      return token;
    }

    return host.token!;
  }

  // 获取文件列表
  Future<List<AlistFile>> getFileList({
    String path = '/',
    String password = '',
    int page = 1,
    int perPage = 0,
    bool refresh = false,
  }) async {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择AList服务器');
    }

    try {
      final token = await _ensureValidToken(host);
      final uri = Uri.parse('${host.baseUrl}/api/fs/list');

      final client = IOClient(_createHttpClient(uri));
      try {
        // 构建请求头，对于匿名访问不添加Authorization头
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'User-Agent': 'NipaPlay/1.0',
        };

        // 只有当token不为空时才添加Authorization头
        if (token.isNotEmpty) {
          headers['Authorization'] = token;
        }

        final response = await client
            .post(
              uri,
              headers: headers,
              body: json.encode({
                'path': path,
                'password': password,
                'page': page,
                'per_page': perPage,
                'refresh': refresh,
              }),
            )
            .timeout(const Duration(seconds: 30)); // 增加超时时间到30秒

        if (response.statusCode != 200) {
          throw Exception(
              '获取文件列表失败: HTTP ${response.statusCode}, ${response.body}');
        }

        final fileListResponse =
            AlistFileListResponse.fromJson(json.decode(response.body));
        if (fileListResponse.code != 200) {
          throw Exception('获取文件列表失败: ${fileListResponse.message}');
        }

        // 更新主机状态为在线
        _updateHostStatus(host.id, isOnline: true, lastError: null);

        return fileListResponse.data.content;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('获取AList文件列表失败: $e');
      // 更新主机状态为离线
      _updateHostStatus(host.id, isOnline: false, lastError: e.toString());
      rethrow;
    }
  }

  // 构建文件的下载/播放URL
  String buildFileUrl(String path) {
    final host = activeHost;
    if (host == null) {
      throw Exception('未选择AList服务器');
    }

    // AList的文件访问URL格式通常是 /d/路径
    // 注意需要正确编码路径
    final encodedPath = path.startsWith('/') ? path.substring(1) : path;
    return '${host.baseUrl}/d/$encodedPath';
  }

  // 更新主机状态
  void _updateHostStatus(String hostId, {bool? isOnline, String? lastError}) {
    final index = _hosts.indexWhere((host) => host.id == hostId);
    if (index == -1) return;

    final current = _hosts[index];
    final updated = current.copyWith(
      isOnline: isOnline ?? current.isOnline,
      lastConnectedAt: DateTime.now(),
      lastError: lastError,
    );

    _hosts[index] = updated;
    _persistHosts();
  }

  // 规范化BaseURL
  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  // 创建HttpClient实例
  HttpClient _createHttpClient(Uri uri) {
    final httpClient = HttpClient();
    httpClient.userAgent = 'NipaPlay/1.0';
    httpClient.autoUncompress = true; // 启用自动解压响应
    if (_shouldBypassProxy(uri.host)) {
      httpClient.findProxy = (_) => 'DIRECT';
    }
    return httpClient;
  }

  // 判断是否需要绕过代理
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
}
