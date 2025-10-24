import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 网络设置管理类
class NetworkSettings {
  static const String _dandanplayServerKey = 'dandanplay_server_url';
  static const String _customServersKey = 'dandanplay_custom_servers';
  
  // 服务器常量
  static const String primaryServer = 'https://api.dandanplay.net';
  static const String backupServer = 'http://139.217.235.62:16001';
  
  // 默认服务器（主服务器）
  static const String defaultServer = primaryServer;

  /// 获取当前弹弹play服务器地址
  static Future<String> getDandanplayServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dandanplayServerKey) ?? defaultServer;
  }

  /// 设置弹弹play服务器地址
  static Future<void> setDandanplayServer(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dandanplayServerKey, serverUrl);
    print('[网络设置] 弹弹play服务器已切换到: $serverUrl');
  }

  /// 重置为默认服务器
  static Future<void> resetToDefaultServer() async {
    await setDandanplayServer(defaultServer);
  }

  /// 检查是否使用备用服务器
  static Future<bool> isUsingBackupServer() async {
    final currentServer = await getDandanplayServer();
    return currentServer == backupServer;
  }

  /// 获取所有可用服务器列表（包括系统默认和自定义服务器）
  static Future<List<Map<String, String>>> getAllAvailableServers() async {
    // 先获取系统默认服务器
    final defaultServers = [
      {
        'name': '主服务器',
        'url': primaryServer,
        'description': 'api.dandanplay.net（官方服务器）',
        'isCustom': 'false',
      },
      {
        'name': '备用服务器', 
        'url': backupServer,
        'description': '139.217.235.62:16001（镜像服务器）',
        'isCustom': 'false',
      },
    ];

    // 获取自定义服务器
    final customServers = await getCustomServers();
    
    // 合并列表
    defaultServers.addAll(customServers);
    return defaultServers;
  }

  /// 获取自定义服务器列表
  static Future<List<Map<String, String>>> getCustomServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = prefs.getString(_customServersKey);
    
    if (serversJson != null) {
      try {
        final List<dynamic> serversList = jsonDecode(serversJson);
        return serversList
            .map((server) => {
                  'name': server['name'] as String,
                  'url': server['url'] as String,
                  'description': server['description'] as String,
                  'isCustom': 'true',
                })
            .toList();
      } catch (e) {
        print('[网络设置] 解析自定义服务器列表失败: $e');
        return [];
      }
    }
    
    return [];
  }

  /// 添加自定义服务器
  static Future<void> addCustomServer(String name, String url, String description) async {
    final customServers = await getCustomServers();
    
    // 检查是否已存在相同URL的服务器
    final exists = customServers.any((server) => server['url'] == url);
    if (!exists) {
      customServers.add({
        'name': name,
        'url': url,
        'description': description,
      });
      await _saveCustomServers(customServers);
      print('[网络设置] 添加自定义服务器: $name - $url');
    }
  }

  /// 更新自定义服务器
  static Future<void> updateCustomServer(String oldUrl, String newName, String newUrl, String newDescription) async {
    final customServers = await getCustomServers();
    final index = customServers.indexWhere((server) => server['url'] == oldUrl);
    
    if (index != -1) {
      customServers[index] = {
        'name': newName,
        'url': newUrl,
        'description': newDescription,
      };
      await _saveCustomServers(customServers);
      print('[网络设置] 更新自定义服务器: $oldUrl -> $newUrl');
    }
  }

  /// 删除自定义服务器
  static Future<void> deleteCustomServer(String url) async {
    final customServers = await getCustomServers();
    final filteredServers = customServers.where((server) => server['url'] != url).toList();
    
    if (filteredServers.length != customServers.length) {
      await _saveCustomServers(filteredServers);
      print('[网络设置] 删除自定义服务器: $url');
    }
  }

  /// 保存自定义服务器列表
  static Future<void> _saveCustomServers(List<Map<String, String>> servers) async {
    final prefs = await SharedPreferences.getInstance();
    // 移除isCustom字段后保存
    final serversToSave = servers.map((server) {
      final serverCopy = Map<String, String>.from(server);
      serverCopy.remove('isCustom');
      return serverCopy;
    }).toList();
    
    await prefs.setString(_customServersKey, jsonEncode(serversToSave));
  }

  /// 检查URL是否有效
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }
}