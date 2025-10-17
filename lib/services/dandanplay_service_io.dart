import 'dart:convert';
import 'dart:async';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'danmaku_cache_manager.dart';
import 'debug_log_service.dart';
import 'package:nipaplay/utils/remote_media_fetcher.dart';

class DandanplayService {
  static const String appId = "nipaplayv1";
  static const String userAgent = "NipaPlay/1.0";
  static String? _token;
  static String? _appSecret;
  static const String _videoCacheKey = 'video_recognition_cache';
  static const String _lastTokenRenewKey = 'last_token_renew_time';
  static const int _tokenRenewInterval = 21 * 24 * 60 * 60 * 1000; // 21天（毫秒）
  static bool _isLoggedIn = false;
  static String? _userName;
  static String? _screenName;
  static const List<String> _servers = [
    'https://nipaplay.aimes-soft.com',
    'https://kurisu.aimes-soft.com'
  ];
  static bool get isLoggedIn => _isLoggedIn;
  static String? get userName => _userName;
  static String? get screenName => _screenName;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;
    _userName = prefs.getString('dandanplay_username');
    _screenName = prefs.getString('dandanplay_screenname');
    await loadToken();
    
    // 输出当前使用的弹弹play服务器
    final currentServer = await NetworkSettings.getDandanplayServer();
    print('[弹弹play服务] 当前使用的服务器: $currentServer');
  }

  /// 获取当前弹弹play API基础URL
  static Future<String> _getApiBaseUrl() async {
    return await NetworkSettings.getDandanplayServer();
  }

  // 预加载最近更新的动画数据
  static Future<void> preloadRecentAnimes() async {
    try {
      debugPrint('[弹弹play服务] 开始预加载最近更新的番剧数据');
      
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/bangumi/recent';
      final baseUrl = await _getApiBaseUrl();
      final apiUrl = '$baseUrl/api/v2/bangumi/recent?limit=20';
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      );
      
      if (response.statusCode == 200) {
        // 数据已成功预加载，不需要进一步处理
        debugPrint('[弹弹play服务] 最近更新的番剧数据预加载成功');
      } else {
        debugPrint('[弹弹play服务] 预加载最近更新番剧失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 预加载最近更新番剧时出错: $e');
    }
  }

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('dandanplay_token');
    
    // 检查是否需要刷新Token
    await _checkAndRenewToken();
  }

  static Future<void> saveLoginInfo(String token, String username, String screenName) async {
    _token = token;
    _userName = username;
    _screenName = screenName;
    _isLoggedIn = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dandanplay_token', token);
    await prefs.setString('dandanplay_username', username);
    await prefs.setString('dandanplay_screenname', screenName);
    await prefs.setBool('dandanplay_logged_in', true);
    await prefs.setInt(_lastTokenRenewKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clearLoginInfo() async {
    _token = null;
    _userName = null;
    _screenName = null;
    _isLoggedIn = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dandanplay_token');
    await prefs.remove('dandanplay_username');
    await prefs.remove('dandanplay_screenname');
    await prefs.remove('dandanplay_logged_in');
    await prefs.remove(_lastTokenRenewKey);
  }

  // 检查并刷新Token
  static Future<void> _checkAndRenewToken() async {
    if (_token == null) return;

    final prefs = await SharedPreferences.getInstance();
    final lastRenewTime = prefs.getInt(_lastTokenRenewKey) ?? 0;
    final currentTime = DateTime.now().millisecondsSinceEpoch;

    // 如果距离上次刷新超过21天，则刷新Token
    if (currentTime - lastRenewTime >= _tokenRenewInterval) {
      try {
        final appSecret = await getAppSecret();
        final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();

        final response = await http.post(
          Uri.parse('${await _getApiBaseUrl()}/api/v2/login/renew'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': userAgent,
            'X-AppId': appId,
            'X-Signature': generateSignature(appId, timestamp, '/api/v2/login/renew', appSecret),
            'X-Timestamp': '$timestamp',
            'Authorization': 'Bearer $_token',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['token'] != null) {
            // 更新Token和刷新时间
            _token = data['token'];
            await saveToken(_token!);
            await prefs.setInt(_lastTokenRenewKey, currentTime);
            //////debugPrint('Token已成功刷新');
          } else {
            //////debugPrint('Token刷新失败: ${data['errorMessage']}');
          }
        } else {
          //////debugPrint('Token刷新请求失败: ${response.statusCode}');
        }
      } catch (e) {
        //////debugPrint('Token刷新时发生错误: $e');
      }
    }
  }

  static Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dandanplay_token', token);
    // 保存Token刷新时间
    await prefs.setInt(_lastTokenRenewKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dandanplay_token');
    await prefs.remove(_lastTokenRenewKey);
  }

  // 获取缓存的视频信息
  static Future<Map<String, dynamic>?> getCachedVideoInfo(String fileHash) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(_videoCacheKey);
    if (cache != null) {
      final Map<String, dynamic> cacheMap = json.decode(cache);
      //////debugPrint('缓存数据: ${json.encode(cacheMap)}');
      //////debugPrint('查找哈希: $fileHash');
      //////debugPrint('缓存中是否有该哈希: ${cacheMap.containsKey(fileHash)}');
      if (cacheMap.containsKey(fileHash)) {
        final videoInfo = cacheMap[fileHash];
        //////debugPrint('视频信息: ${json.encode(videoInfo)}');
        return videoInfo;
      }
    }
    return null;
  }

  // 保存视频信息到缓存
  static Future<void> saveVideoInfoToCache(String fileHash, Map<String, dynamic> videoInfo) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(_videoCacheKey);
    Map<String, dynamic> cacheMap = {};
    
    if (cache != null) {
      cacheMap = Map<String, dynamic>.from(json.decode(cache));
    }
    
    cacheMap[fileHash] = videoInfo;
    await prefs.setString(_videoCacheKey, json.encode(cacheMap));
  }

  // 获取appSecret
  static Future<String> getAppSecret() async {
    // debugPrint('[DandanplayService] getAppSecret: Called.');
     if (_appSecret != null) {
       //debugPrint('[DandanplayService] getAppSecret: Returning cached _appSecret.');
       return _appSecret!;
     }

    // // 尝试从 SharedPreferences 获取 appSecret
     final prefs = await SharedPreferences.getInstance();
     final savedAppSecret = prefs.getString('dandanplay_app_secret');
     if (savedAppSecret != null) {
       _appSecret = savedAppSecret;
       //debugPrint('[DandanplayService] getAppSecret: Returning appSecret from SharedPreferences.');
       return _appSecret!;
     }
    //debugPrint('[DandanplayService] getAppSecret: No cached appSecret. Fetching from servers...');

    // 从服务器列表获取 appSecret
    //final prefs = await SharedPreferences.getInstance();
    Exception? lastException;
    for (final server in _servers) {
      //debugPrint('[DandanplayService] getAppSecret: Trying server: $server');
      try {
        ////debugPrint('尝试从服务器 $server 获取appSecret');
        final response = await http.get(
          Uri.parse('$server/nipaplay.php'),
          headers: {
            'User-Agent': userAgent,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));

        // 强制打印服务器返回的原始内容以供调试
        print('[NipaPlay AppSecret Response from $server] StatusCode: ${response.statusCode}, Body: ${response.body}');

        ////debugPrint('服务器响应: 状态码=${response.statusCode}, 内容长度=${response.body.length}');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          ////debugPrint('解析的响应数据: $data');
          if (data['encryptedAppSecret'] != null) {
            _appSecret = _b(data['encryptedAppSecret']);
            await prefs.setString('dandanplay_app_secret', _appSecret!);
            ////debugPrint('成功从 $server 获取appSecret');
            return _appSecret!;
          }
          throw Exception('从 $server 获取appSecret失败：响应中没有encryptedAppSecret');
        }
        throw Exception('从 $server 获取appSecret失败：HTTP ${response.statusCode}');
      } on TimeoutException {
        // 打印超时错误
        print('[NipaPlay AppSecret Error from $server] TimeoutException: 请求超时');
        lastException = TimeoutException('从 $server 获取appSecret超时');
      } catch (e) {
        // 打印其他所有网络错误
        print('[NipaPlay AppSecret Error from $server] Exception: ${e.toString()}');
        lastException = e as Exception;
      }
    }
    
    //debugPrint('[DandanplayService] getAppSecret: Finished attempting all servers.');
    ////debugPrint('所有服务器均不可用，最后的错误: ${lastException?.toString()}');
    throw lastException ?? Exception('获取应用密钥失败，请检查网络连接');
  }

  static String _b(String a) {
    String b = a.split('').map((c) {
      if (c.toLowerCase() != c.toUpperCase()) {
        final d = c == c.toUpperCase();
        final e = d ? 'A'.codeUnitAt(0) : 'a'.codeUnitAt(0);
        return String.fromCharCode(e + 25 - (c.codeUnitAt(0) - e));
      }
      return c;
    }).join('');
    
    String f;
    if (b.length >= 5) {
      final g = b[0];
      f = b.substring(1, b.length - 4) + g + b.substring(b.length - 4);
    } else {
      f = b;
    }
    
    String h = f.split('').map((i) {
      if (i.codeUnitAt(0) >= '0'.codeUnitAt(0) && i.codeUnitAt(0) <= '9'.codeUnitAt(0)) {
        return String.fromCharCode('0'.codeUnitAt(0) + (10 - int.parse(i)));
      }
      return i;
    }).join('');
    
    return h.split('').map((j) {
      if (j.toLowerCase() != j.toUpperCase()) {
        return j == j.toLowerCase() ? j.toUpperCase() : j.toLowerCase();
      }
      return j;
    }).join('');
  }

  static String generateSignature(String appId, int timestamp, String apiPath, String appSecret) {
    final signatureString = '$appId$timestamp$apiPath$appSecret';
    final hash = sha256.convert(utf8.encode(signatureString));
    return base64.encode(hash.bytes);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final appSecret = await getAppSecret();
      final now = DateTime.now();
      final utcNow = now.toUtc();
      final timestamp = (utcNow.millisecondsSinceEpoch / 1000).round();
      final hashString = '$appId$password$timestamp$username$appSecret';
      final hash = md5.convert(utf8.encode(hashString)).toString();

      final response = await http.post(
        Uri.parse('${await _getApiBaseUrl()}/api/v2/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, '/api/v2/login', appSecret),
          'X-Timestamp': '$timestamp',
        },
        body: json.encode({
          'userName': username,
          'password': password,
          'appId': appId,
          'unixTimestamp': timestamp,
          'hash': hash,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['token'] != null) {
          // 保存完整的登录信息，包括状态
          final screenName = data['user']?['screenName'] ?? username;
          await saveLoginInfo(data['token'], username, screenName);
          return {'success': true, 'message': '登录成功'};
        } else {
          return {'success': false, 'message': data['errorMessage'] ?? '登录失败，请检查用户名和密码'};
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? response.body;
        return {'success': false, 'message': '网络请求失败 (${response.statusCode}): $errorMessage'};
      }
    } catch (e) {
      return {'success': false, 'message': '登录失败: ${e.toString()}'};
    }
  }

  /// 注册弹弹play账号
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String email,
    required String screenName,
  }) async {
    final logService = DebugLogService();
    logService.startCollecting();
    
    try {
      print('[弹弹play服务] 注册参数详情:');
      print('用户名: $username');
      print('邮箱: $email');
      print('昵称: $screenName');
      
      // 调试：打印当前的应用ID
      //print('[弹弹play服务] 当前应用ID: $appId');
      
      //logService.addLog('[弹弹play服务] 开始注册流程', level: 'INFO', tag: 'Register');
      //logService.addLog('[弹弹play服务] 用户名: $username, 邮箱: $email, 昵称: $screenName', level: 'INFO', tag: 'Register');
      
      // 验证参数（保持不变）
      if (username.length < 5 || username.length > 20) {
        logService.addError('[弹弹play服务] 用户名长度不符合要求: ${username.length}', tag: 'Register');
        return {'success': false, 'message': '用户名长度必须在5-20位之间'};
      }
      
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9]*$').hasMatch(username)) {
        logService.addError('[弹弹play服务] 用户名格式不符合要求: $username', tag: 'Register');
        return {'success': false, 'message': '用户名只能包含英文或数字，且首位不能为数字'};
      }
      
      if (password.length < 5 || password.length > 20) {
        logService.addError('[弹弹play服务] 密码长度不符合要求: ${password.length}', tag: 'Register');
        return {'success': false, 'message': '密码长度必须在5-20位之间'};
      }
      
      if (email.isEmpty || email.length > 50) {
        logService.addError('[弹弹play服务] 邮箱长度不符合要求: ${email.length}', tag: 'Register');
        return {'success': false, 'message': '请输入有效的邮箱地址'};
      }
      
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        logService.addError('[弹弹play服务] 邮箱格式不正确: $email', tag: 'Register');
        return {'success': false, 'message': '请输入有效的邮箱格式'};
      }
      
      if (screenName.isEmpty || screenName.length > 50) {
        logService.addError('[弹弹play服务] 昵称长度不符合要求: ${screenName.length}', tag: 'Register');
        return {'success': false, 'message': '昵称不能为空且长度不能超过50个字符'};
      }

      //logService.addLog('[弹弹play服务] 参数验证通过，开始获取AppSecret', level: 'INFO', tag: 'Register');
      
      final appSecret = await getAppSecret();
      
      // 调试：打印获取的AppSecret
      //print('[弹弹play服务] 获取的AppSecret: ${appSecret.substring(0, 8)}...');
      //logService.addLog('[弹弹play服务] AppSecret获取成功', level: 'INFO', tag: 'Register');
      
      final now = DateTime.now();
      final utcNow = now.toUtc();
      final timestamp = (utcNow.millisecondsSinceEpoch / 1000).round();
      
      // 计算hash：appId + password + unixTimestamp + userName + email + screenName + AppSecret
      final hashString = '$appId$email$password$screenName$timestamp$username$appSecret';
      final hash = md5.convert(utf8.encode(hashString)).toString();
      
      //logService.addLog('[弹弹play服务] Hash计算完成: ${hash.substring(0, 8)}...', level: 'INFO', tag: 'Register');
      //ogService.addLog('[弹弹play服务] 时间戳: $timestamp', level: 'INFO', tag: 'Register');

      final requestBody = {
        'appId': appId,
        'userName': username,
        'password': password,
        'email': email,
        'screenName': screenName,
        'unixTimestamp': timestamp,
        'hash': hash,
      };
      // 调试：打印签名生成细节
      final signature = generateSignature(appId, timestamp, '/api/v2/register', appSecret);
      final response = await http.post(
        Uri.parse('${await _getApiBaseUrl()}/api/v2/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': signature,
          'X-Timestamp': '$timestamp',
        },
        body: json.encode(requestBody),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        //logService.addLog('[弹弹play服务] 注册响应体: ${json.encode(data)}', level: 'INFO', tag: 'Register');
        
        if (data['success'] == true) {
          //logService.addLog('[弹弹play服务] 注册成功', level: 'INFO', tag: 'Register');
          // 注册成功，如果响应中包含token，则自动登录
          if (data['token'] != null) {
            await saveLoginInfo(data['token'], username, screenName);
            //logService.addLog('[弹弹play服务] 注册成功并自动登录', level: 'INFO', tag: 'Register');
            return {'success': true, 'message': '注册成功并已自动登录'};
          } else {
            //logService.addLog('[弹弹play服务] 注册成功，但未返回token', level: 'INFO', tag: 'Register');
            return {'success': true, 'message': '注册成功，请使用新账号登录'};
          }
        } else {
          final errorMsg = data['errorMessage'] ?? '注册失败，请检查填写信息';
          logService.addError('[弹弹play服务] 注册失败: $errorMsg', tag: 'Register');
          return {'success': false, 'message': errorMsg};
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? response.body;
        logService.addError('[弹弹play服务] 注册请求失败: HTTP ${response.statusCode}, $errorMessage', tag: 'Register');
        return {'success': false, 'message': '网络请求失败 (${response.statusCode}): $errorMessage'};
      }
    } catch (e, stackTrace) {
      logService.addError('[弹弹play服务] 注册时发生异常: $e', tag: 'Register');
      logService.addError('[弹弹play服务] 异常堆栈: $stackTrace', tag: 'Register');
      return {'success': false, 'message': '注册失败: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> getVideoInfo(String videoPath) async {
    if (kIsWeb) {
      throw Exception('Web版不支持从本地文件获取视频信息。');
    }

    try {
      final bool isRemotePath = videoPath.startsWith('http://') || videoPath.startsWith('https://');

      if (isRemotePath) {
        try {
          final remoteHead = await RemoteMediaFetcher.fetchHead(Uri.parse(videoPath));
          return _getVideoInfoWithMetadata(
            fileName: remoteHead.fileName,
            fileHash: remoteHead.hash,
            fileSize: remoteHead.fileSize,
          );
        } catch (e) {
          debugPrint('DandanplayService: 获取远程媒体信息失败: $e');
          rethrow;
        }
      }

      final file = File(videoPath);
      if (!file.existsSync()) {
        throw Exception('文件不存在: $videoPath');
      }

      final fileName = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path.split('/').last;
      final fileSize = await file.length();
      final fileHash = await _d(file);

      return _getVideoInfoWithMetadata(
        fileName: fileName,
        fileHash: fileHash,
        fileSize: fileSize,
      );
    } catch (e) {
      throw Exception('获取视频信息失败: ${e.toString()}');
    }
  }

  static Future<Map<String, dynamic>> _getVideoInfoWithMetadata({
    required String fileName,
    required String fileHash,
    required int fileSize,
  }) async {
    // 尝试从缓存获取视频信息
    final cachedInfo = await getCachedVideoInfo(fileHash);
    if (cachedInfo != null) {
      if (cachedInfo['matches'] != null && cachedInfo['matches'].isNotEmpty) {
        final match = cachedInfo['matches'][0];
        if (match['episodeId'] != null && match['animeId'] != null) {
          try {
            final episodeId = match['episodeId'].toString();
            final animeId = match['animeId'] as int;
            final danmakuData = await getDanmaku(episodeId, animeId);
            cachedInfo['comments'] = danmakuData['comments'];
          } catch (e) {
            debugPrint('从缓存匹配信息获取弹幕失败: $e');
          }
        }
      }

      _ensureVideoInfoTitles(cachedInfo);
      return cachedInfo;
    }

    final appSecret = await getAppSecret();
    final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();

    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('dandanplay_logged_in') ?? false;

    final baseUrl = await _getApiBaseUrl();
    final apiUrl = '$baseUrl/api/v2/match';

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': userAgent,
      'X-AppId': appId,
      'X-Signature': generateSignature(appId, timestamp, '/api/v2/match', appSecret),
      'X-Timestamp': '$timestamp',
      if (isLoggedIn && _token != null) 'Authorization': 'Bearer $_token',
    };

    final body = json.encode({
      'fileName': fileName,
      'fileHash': fileHash,
      'fileSize': fileSize,
      'matchMode': 'hashAndFileName',
      if (isLoggedIn && _token != null) 'token': _token,
    });

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['isMatched'] == true) {
        _ensureVideoInfoTitles(data);

        await saveVideoInfoToCache(fileHash, data);

        if (data['matches'] != null && data['matches'].isNotEmpty) {
          final match = data['matches'][0];
          if (match['episodeId'] != null && match['animeId'] != null) {
            try {
              final episodeId = match['episodeId'].toString();
              final animeId = match['animeId'] as int;
              final danmakuData = await getDanmaku(episodeId, animeId);
              data['comments'] = danmakuData['comments'];
            } catch (e) {
              debugPrint('获取弹幕失败: $e');
            }
          }
        }

        return data;
      } else {
        throw Exception('无法识别该视频');
      }
    } else {
      final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
      throw Exception('获取视频信息失败: $errorMessage');
    }
  }

  static Future<String> _d(File file) async {
    if (kIsWeb) return '';
    const int maxBytes = 16 * 1024 * 1024; // 16MB
    final bytes = await file.openRead(0, maxBytes).expand((chunk) => chunk).toList();
    return md5.convert(bytes).toString();
  }

  static Future<Map<String, dynamic>> getDanmaku(String episodeId, int animeId) async {
    try {
      debugPrint('开始获取弹幕: episodeId=$episodeId, animeId=$animeId');
      
      // 先检查缓存
      final cachedDanmaku = await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        ////debugPrint('从缓存加载弹幕成功: $episodeId, 数量: ${cachedDanmaku.length}');
        return {
          'comments': cachedDanmaku,
          'fromCache': true,
          'count': cachedDanmaku.length
        };
      }
      
      ////debugPrint('缓存未命中，从网络加载弹幕');
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/comment/$episodeId';
      
      // 从设置中读取弹幕转换选项
      final prefs = await SharedPreferences.getInstance();
      final chConvert = prefs.getBool('danmaku_convert_to_simplified') ?? true ? 1 : 0;
      
      final baseUrl = await _getApiBaseUrl();
      final apiUrl = '$baseUrl$apiPath?withRelated=true&chConvert=$chConvert';
      
      ////debugPrint('发送弹幕请求: $apiUrl');
      ////debugPrint('请求头: X-AppId: $appId, X-Timestamp: $timestamp, 是否包含token: ${_token != null}');
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      );

      ////debugPrint('弹幕API响应: 状态码=${response.statusCode}, 内容长度=${response.body.length}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['comments'] != null) {
          final comments = data['comments'] as List;
          ////debugPrint('获取到原始弹幕数: ${comments.length}');
          
          final formattedComments = comments.map((comment) {
            // 解析 p 字段，格式为 "时间,模式,颜色,用户ID"
            final pParts = (comment['p'] as String).split(',');
            final time = double.tryParse(pParts[0]) ?? 0.0;
            final mode = int.tryParse(pParts[1]) ?? 1;
            final color = int.tryParse(pParts[2]) ?? 16777215; // 默认白色
            final content = comment['m'] as String;
            
            // 转换颜色格式
            final r = (color >> 16) & 0xFF;
            final g = (color >> 8) & 0xFF;
            final b = color & 0xFF;
            final colorValue = 'rgb($r,$g,$b)';
            
            return {
              'time': time,
              'content': content,
              'type': mode == 1 ? 'scroll' : mode == 5 ? 'top' : 'bottom',
              'color': colorValue,
              'isMe': false,
            };
          }).toList();

          ////debugPrint('从网络加载弹幕成功: $episodeId, 格式化后数量: ${formattedComments.length}');
          
          // 异步保存到缓存
          DanmakuCacheManager.saveDanmakuToCache(episodeId, animeId, formattedComments)
              .then((_) => debugPrint('弹幕已保存到缓存: $episodeId'));
          
          return {
            'comments': formattedComments,
            'fromCache': false,
            'count': formattedComments.length
          };
        } else {
          ////debugPrint('API响应中没有comments字段: ${data.keys.toList()}');
          throw Exception('该视频暂无弹幕');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        ////debugPrint('获取弹幕失败: 状态码=${response.statusCode}, 错误信息=$errorMessage');
        throw Exception('获取弹幕失败: $errorMessage');
      }
    } catch (e) {
      ////debugPrint('获取弹幕时出错: $e');
      rethrow;
    }
  }

  // 确保视频信息中包含格式化后的动画标题和集数标题
  static void _ensureVideoInfoTitles(Map<String, dynamic> videoInfo) {
    if (videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
      final match = videoInfo['matches'][0];
      
      // 确保animeTitle字段存在
      if (videoInfo['animeTitle'] == null || videoInfo['animeTitle'].toString().isEmpty) {
        videoInfo['animeTitle'] = match['animeTitle'];
      }
      
      // 确保episodeTitle字段存在
      if (videoInfo['episodeTitle'] == null || videoInfo['episodeTitle'].toString().isEmpty) {
        // 尝试从match中获取
        String? episodeTitle = match['episodeTitle'] as String?;
        
        // 如果仍然没有集数标题，尝试从episodeId生成
        if (episodeTitle == null || episodeTitle.isEmpty) {
          final episodeId = match['episodeId'];
          if (episodeId != null) {
            final episodeIdStr = episodeId.toString();
            
            // 从episodeId中提取集数信息
            if (episodeIdStr.length >= 8) {
              final episodeNumber = int.tryParse(episodeIdStr.substring(6, 8));
              if (episodeNumber != null) {
                episodeTitle = '第$episodeNumber话';
                
                // 如果match中有episodeTitle，添加到生成的标题中
                if (match['episodeTitle'] != null && match['episodeTitle'].toString().isNotEmpty) {
                  episodeTitle += ' ${match['episodeTitle']}';
                }
              }
            }
          }
        }
        
        videoInfo['episodeTitle'] = episodeTitle;
      }
      
      ////debugPrint('确保标题完整性: 动画=${videoInfo['animeTitle']}, 集数=${videoInfo['episodeTitle']}');
    }
  }


  // 获取用户播放历史
  static Future<Map<String, dynamic>> getUserPlayHistory({DateTime? fromDate, DateTime? toDate}) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能获取播放历史');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/playhistory';
      
      // 构建查询参数
      final queryParams = <String, String>{};
      if (fromDate != null) {
        queryParams['fromDate'] = fromDate.toUtc().toIso8601String();
      }
      if (toDate != null) {
        queryParams['toDate'] = toDate.toUtc().toIso8601String();
      }
      
      final baseUrl = await _getApiBaseUrl();
      final uri = Uri.parse('$baseUrl$apiPath${queryParams.isNotEmpty ? '?' + Uri(queryParameters: queryParams).query : ''}');
      
      debugPrint('[弹弹play服务] 获取播放历史: $uri');
      
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint('[弹弹play服务] 播放历史响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '获取播放历史失败');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('获取播放历史失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 获取播放历史时出错: $e');
      rethrow;
    }
  }

  // 提交播放历史记录
  static Future<Map<String, dynamic>> addPlayHistory({
    required List<int> episodeIdList,
    bool addToFavorite = false,
    int rating = 0,
  }) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能提交播放历史');
    }

    if (episodeIdList.isEmpty) {
      throw Exception('集数ID列表不能为空');
    }

    if (episodeIdList.length > 100) {
      throw Exception('单次最多只能提交100条播放历史');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/playhistory';
      
      final requestBody = {
        'episodeIdList': episodeIdList,
        'addToFavorite': addToFavorite,
        'rating': rating,
      };
      
      debugPrint('[弹弹play服务] 提交播放历史: $episodeIdList');
      
      final response = await http.post(
        Uri.parse('${await _getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode(requestBody),
      );

      debugPrint('[弹弹play服务] 提交播放历史响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('[弹弹play服务] 播放历史提交成功');
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '提交播放历史失败');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('提交播放历史失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 提交播放历史时出错: $e');
      rethrow;
    }
  }

  // 获取番剧详情（包含用户观看状态）
  static Future<Map<String, dynamic>> getBangumiDetails(int bangumiId) async {
    try {
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$bangumiId';
      
      final headers = {
        'Accept': 'application/json',
        'User-Agent': userAgent,
        'X-AppId': appId,
        'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
        'X-Timestamp': '$timestamp',
      };
      
      // 如果已登录，添加认证头
      if (_isLoggedIn && _token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }
      
      debugPrint('[弹弹play服务] 获取番剧详情: $bangumiId');
      
      final response = await http.get(
        Uri.parse('${await _getApiBaseUrl()}$apiPath'),
        headers: headers,
      );

      debugPrint('[弹弹play服务] 番剧详情响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('获取番剧详情失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 获取番剧详情时出错: $e');
      rethrow;
    }
  }

  // 获取用户对特定剧集的观看状态
  static Future<Map<int, bool>> getEpisodesWatchStatus(List<int> episodeIds) async {
    final Map<int, bool> watchStatus = {};
    
    // 如果未登录，返回空状态
    if (!_isLoggedIn || _token == null) {
      debugPrint('[弹弹play服务] 未登录，无法获取观看状态');
      for (final episodeId in episodeIds) {
        watchStatus[episodeId] = false;
      }
      return watchStatus;
    }

    try {
      // 获取用户播放历史
      final historyData = await getUserPlayHistory();
      
      if (historyData['success'] == true && historyData['playHistoryAnimes'] != null) {
        final List<dynamic> animes = historyData['playHistoryAnimes'];
        
        // 遍历所有动画的观看历史
        for (final anime in animes) {
          if (anime['episodes'] != null) {
            final List<dynamic> episodes = anime['episodes'];
            
            // 检查每个剧集的观看状态
            for (final episode in episodes) {
              final episodeId = episode['episodeId'] as int?;
              final lastWatched = episode['lastWatched'] as String?;
              
              if (episodeId != null && episodeIds.contains(episodeId)) {
                // 如果有lastWatched时间，说明已看过
                watchStatus[episodeId] = lastWatched != null && lastWatched.isNotEmpty;
              }
            }
          }
        }
      }
      
      // 确保所有请求的episodeId都有状态
      for (final episodeId in episodeIds) {
        watchStatus.putIfAbsent(episodeId, () => false);
      }
      
      debugPrint('[弹弹play服务] 获取观看状态完成: ${watchStatus.length}个剧集');
      return watchStatus;
    } catch (e) {
      debugPrint('[弹弹play服务] 获取观看状态失败: $e');
      // 出错时返回默认状态（未看）
      for (final episodeId in episodeIds) {
        watchStatus[episodeId] = false;
      }
      return watchStatus;
    }
  }

  // 获取用户收藏列表
  static Future<Map<String, dynamic>> getUserFavorites({bool onlyOnAir = false}) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能获取收藏列表');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/favorite';
      
      final queryParams = <String, String>{};
      if (onlyOnAir) {
        queryParams['onlyOnAir'] = 'true';
      }
      
      final baseUrl = await _getApiBaseUrl();
      final uri = Uri.parse('$baseUrl$apiPath${queryParams.isNotEmpty ? '?' + Uri(queryParameters: queryParams).query : ''}');
      
      debugPrint('[弹弹play服务] 获取用户收藏列表: $uri');
      
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint('[弹弹play服务] 收藏列表响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '获取收藏列表失败');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('获取收藏列表失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 获取收藏列表时出错: $e');
      rethrow;
    }
  }

  // 添加收藏
  static Future<Map<String, dynamic>> addFavorite({
    required int animeId,
    String? favoriteStatus, // 'favorited', 'finished', 'abandoned'
    int rating = 0, // 1-10分，0代表不修改
    String? comment,
  }) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能添加收藏');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/favorite';
      
      final requestBody = {
        'animeId': animeId,
        if (favoriteStatus != null) 'favoriteStatus': favoriteStatus,
        'rating': rating,
        if (comment != null) 'comment': comment,
      };
      
      debugPrint('[弹弹play服务] 添加收藏: animeId=$animeId, status=$favoriteStatus');
      
      final response = await http.post(
        Uri.parse('${await _getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode(requestBody),
      );

      debugPrint('[弹弹play服务] 添加收藏响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('[弹弹play服务] 收藏添加成功');
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '添加收藏失败');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('添加收藏失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 添加收藏时出错: $e');
      rethrow;
    }
  }

  // 取消收藏
  static Future<Map<String, dynamic>> removeFavorite(int animeId) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能取消收藏');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/favorite/$animeId';
      
      debugPrint('[弹弹play服务] 取消收藏: animeId=$animeId');
      
      final response = await http.delete(
        Uri.parse('${await _getApiBaseUrl()}$apiPath'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint('[弹弹play服务] 取消收藏响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('[弹弹play服务] 收藏取消成功');
          return data;
        } else {
          throw Exception(data['errorMessage'] ?? '取消收藏失败');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('取消收藏失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 取消收藏时出错: $e');
      rethrow;
    }
  }

  // 检查动画是否已收藏
  static Future<bool> isAnimeFavorited(int animeId) async {
    if (!_isLoggedIn || _token == null) {
      return false; // 未登录时返回false
    }

    try {
      final favoritesData = await getUserFavorites();
      
      if (favoritesData['success'] == true && favoritesData['favorites'] != null) {
        final List<dynamic> favorites = favoritesData['favorites'];
        
        // 检查列表中是否包含指定的animeId
        for (final favorite in favorites) {
          if (favorite['animeId'] == animeId) {
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('[弹弹play服务] 检查收藏状态失败: $e');
      return false; // 出错时返回false
    }
  }

  // 获取用户对番剧的评分
  static Future<int> getUserRatingForAnime(int animeId) async {
    if (!_isLoggedIn || _token == null) {
      return 0; // 未登录时返回0
    }

    try {
      final bangumiDetails = await getBangumiDetails(animeId);
      
      if (bangumiDetails['success'] == true && bangumiDetails['bangumi'] != null) {
        final bangumi = bangumiDetails['bangumi'];
        return bangumi['userRating'] as int? ?? 0;
      }
      
      return 0;
    } catch (e) {
      debugPrint('[弹弹play服务] 获取用户评分失败: $e');
      return 0; // 出错时返回0
    }
  }

  // 提交用户评分（不影响收藏状态）
  static Future<Map<String, dynamic>> submitUserRating({
    required int animeId,
    required int rating, // 1-10分
  }) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能评分');
    }

    if (rating < 1 || rating > 10) {
      throw Exception('评分必须在1-10分之间');
    }

    try {
      // 使用addFavorite接口提交评分，但不修改收藏状态
      return await addFavorite(
        animeId: animeId,
        rating: rating,
        // 不传favoriteStatus参数，这样不会影响现有的收藏状态
      );
    } catch (e) {
      debugPrint('[弹弹play服务] 提交用户评分失败: $e');
      rethrow;
    }
  }

  // 发送弹幕
  static Future<Map<String, dynamic>> sendDanmaku({
    required int episodeId,
    required double time,
    required int mode,
    required int color,
    required String comment,
  }) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能发送弹幕');
    }

    try {
      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/comment/$episodeId';
      
      final requestBody = {
        'time': time,
        'mode': mode,
        'color': color,
        'comment': comment,
      };
      
      debugPrint('[弹弹play服务] 发送弹幕到: $episodeId, 内容: $comment');
      
      final response = await http.post(
        Uri.parse('${await _getApiBaseUrl()}$apiPath'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode(requestBody),
      );

      debugPrint('[弹弹play服务] 发送弹幕响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('[弹弹play服务] 弹幕发送成功: cid=${data['cid']}');
          
          // 将发送的弹幕格式化为与getDanmaku一致的格式
          final r = (color >> 16) & 0xFF;
          final g = (color >> 8) & 0xFF;
          final b = color & 0xFF;
          final colorValue = 'rgb($r,$g,$b)';
          
          final formattedDanmaku = {
            'time': time,
            'content': comment,
            'type': mode == 1 ? 'scroll' : mode == 5 ? 'top' : 'bottom',
            'color': colorValue,
            'isMe': true,
          };
          
          return {'success': true, 'danmaku': formattedDanmaku};
        } else {
          throw Exception(data['errorMessage'] ?? '发送弹幕失败');
        }
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '请检查网络连接';
        throw Exception('发送弹幕失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 发送弹幕时出错: $e');
      rethrow;
    }
  }

  // 获取WebToken（用于账号注销等特殊场景）
  static Future<Map<String, dynamic>> getWebToken({
    required String business,
  }) async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能获取WebToken');
    }

    try {
      debugPrint('[弹弹play服务] 获取WebToken: business=$business');

      final appSecret = await getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/oauth/webToken';

      final response = await http.get(
        Uri.parse('${await _getApiBaseUrl()}$apiPath?business=$business'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
          'X-AppId': appId,
          'X-Signature': generateSignature(appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
          'Authorization': 'Bearer $_token',
        },
      );

      debugPrint('[弹弹play服务] 获取WebToken响应: ${response.statusCode}');
      debugPrint('[弹弹play服务] 获取WebToken响应内容: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('[弹弹play服务] WebToken解析后数据: $data');
        debugPrint('[弹弹play服务] WebToken获取成功');
        return data;
      } else {
        final errorMessage = response.headers['x-error-message'] ?? '获取WebToken失败';
        throw Exception('获取WebToken失败: $errorMessage');
      }
    } catch (e) {
      debugPrint('[弹弹play服务] 获取WebToken时出错: $e');
      rethrow;
    }
  }

  // 开启账号注销流程
  static Future<String> startDeleteAccountProcess() async {
    if (!_isLoggedIn || _token == null) {
      throw Exception('需要登录才能注销账号');
    }

    try {
      debugPrint('[弹弹play服务] 开始账号注销流程');

      // 1. 获取用于账号注销的WebToken
      final webTokenData = await getWebToken(business: 'deleteAccount');
      debugPrint('[弹弹play服务] 获取到的WebToken数据: $webTokenData');

      // 检查数据结构和webToken字段
      final webToken = webTokenData['webToken'];
      debugPrint('[弹弹play服务] 提取的webToken: $webToken');

      if (webToken == null || webToken.toString().isEmpty) {
        debugPrint('[弹弹play服务] WebToken为空或null，完整响应数据: $webTokenData');
        throw Exception('获取账号注销WebToken失败：响应中没有webToken字段');
      }

      // 2. 构建注销页面URL
      final deleteAccountUrl = '${await _getApiBaseUrl()}/api/v2/oauth/deleteAccount?webToken=$webToken';

      debugPrint('[弹弹play服务] 账号注销URL: $deleteAccountUrl');

      return deleteAccountUrl;
    } catch (e) {
      debugPrint('[弹弹play服务] 启动账号注销流程时出错: $e');
      rethrow;
    }
  }

  // 完成账号注销后的清理工作
  static Future<void> completeAccountDeletion() async {
    debugPrint('[弹弹play服务] 执行账号注销后的清理工作');

    try {
      // 清除本地登录信息
      await clearLoginInfo();

      // 清除弹幕缓存
      await DanmakuCacheManager.clearExpiredCache();

      debugPrint('[弹弹play服务] 账号注销清理完成');
    } catch (e) {
      debugPrint('[弹弹play服务] 账号注销清理时出错: $e');
      // 即使清理出错，也不抛出异常，因为主要的注销操作已经完成
    }
  }
}
