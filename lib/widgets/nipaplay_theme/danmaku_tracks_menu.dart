import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_button.dart';
import 'dart:convert';
import 'dart:io' as io;
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

class DanmakuTracksMenu extends StatefulWidget {
  final VoidCallback onClose;

  const DanmakuTracksMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<DanmakuTracksMenu> createState() => _DanmakuTracksMenuState();
}

class _DanmakuTracksMenuState extends State<DanmakuTracksMenu> {
  bool _isLoadingLocalDanmaku = false;
  bool _isLoadingRemoteDanmaku = false;
  bool _showRemoteUrlInput = false;
  final TextEditingController _remoteUrlController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _remoteUrlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 加载本地JSON弹幕文件
  Future<void> _loadLocalDanmakuFile() async {
    if (_isLoadingLocalDanmaku) return;

    setState(() {
      _isLoadingLocalDanmaku = true;
    });

    try {
      // 使用文件选择器选择弹幕文件
      final XTypeGroup jsonTypeGroup = XTypeGroup(
        label: 'JSON弹幕文件',
        extensions: const ['json'],
        uniformTypeIdentifiers: io.Platform.isIOS
            ? ['public.json', 'public.text', 'public.plain-text']
            : null,
      );

      final XTypeGroup xmlTypeGroup = XTypeGroup(
        label: 'XML弹幕文件',
        extensions: const ['xml'],
        uniformTypeIdentifiers: io.Platform.isIOS
            ? ['public.xml', 'public.text', 'public.plain-text']
            : null,
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: [jsonTypeGroup, xmlTypeGroup],
        confirmButtonText: '选择弹幕文件',
      );

      if (file == null) {
        // 用户取消选择
        setState(() {
          _isLoadingLocalDanmaku = false;
        });
        return;
      }

      // 读取文件内容并根据扩展名处理
      final fileContent = await file.readAsString();
      final fileName = file.name.toLowerCase();
      Map<String, dynamic> jsonData;

      if (fileName.endsWith('.xml')) {
        // XML文件，先转换为JSON格式
        jsonData = _convertXmlToJson(fileContent);
      } else {
        // JSON文件，直接解析
        jsonData = json.decode(fileContent);
      }

      // 解析弹幕数据，支持多种格式
      List<dynamic> comments = [];

      if (jsonData.containsKey('comments') && jsonData['comments'] is List) {
        // 标准格式：comments字段包含数组
        comments = jsonData['comments'];
      } else if (jsonData.containsKey('data')) {
        // 兼容格式：data字段
        final data = jsonData['data'];
        if (data is List) {
          // data是数组
          comments = data;
        } else if (data is String) {
          // data是字符串，需要解析
          try {
            final parsedData = json.decode(data);
            if (parsedData is List) {
              comments = parsedData;
            } else {
              throw Exception('data字段的JSON字符串不是数组格式');
            }
          } catch (e) {
            throw Exception('data字段的JSON字符串解析失败: $e');
          }
        } else {
          throw Exception('data字段格式不正确，应为数组或JSON字符串');
        }
      } else {
        throw Exception('JSON文件格式不正确，必须包含comments数组或data字段');
      }

      if (comments.isEmpty) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      // 获取VideoPlayerState并计算轨道编号
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      final localTrackCount = videoState.danmakuTracks.values
          .where((track) => track['source'] == 'local')
          .length;
      final trackName = '本地弹幕${localTrackCount + 1}';

      // 添加弹幕轨道
      await videoState.loadDanmakuFromLocal(jsonData, trackName: trackName);

      if (mounted) {
        BlurSnackBar.show(context, '弹幕轨道添加成功，共${comments.length}条弹幕');
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '加载弹幕文件失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocalDanmaku = false;
        });
      }
    }
  }

  // 切换到URL输入模式
  void _toggleRemoteUrlInput() {
    setState(() {
      _showRemoteUrlInput = true;
    });
    // 立即聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  // 取消URL输入
  void _cancelRemoteUrlInput() {
    setState(() {
      _showRemoteUrlInput = false;
      _remoteUrlController.clear();
    });
  }

  // 加载远程弹幕URL
  Future<void> _loadRemoteDanmakuUrl() async {
    // 验证URL
    final inputUrl = _remoteUrlController.text.trim();
    if (inputUrl.isEmpty) {
      BlurSnackBar.show(context, '请输入弹幕URL');
      return;
    }

    final uri = Uri.tryParse(inputUrl);
    if (uri == null || !uri.hasAbsolutePath) {
      BlurSnackBar.show(context, '请输入有效的URL地址');
      return;
    }

    // 开始加载
    setState(() {
      _isLoadingRemoteDanmaku = true;
      _showRemoteUrlInput = false;
    });

    try {
      // 发送HTTP请求获取弹幕文件
      final response = await http.get(Uri.parse(inputUrl));

      if (response.statusCode != 200) {
        throw Exception('请求失败，状态码: ${response.statusCode}');
      }

      // 读取响应内容
      final fileContent = response.body,
          contentType = response.headers['content-type']?.toLowerCase();
      Map<String, dynamic> jsonData;

      // 根据响应文本判断是XML还是JSON
      if (contentType?.contains('application/xml') == true ||
          fileContent.trim().startsWith('<')) {
        // XML文件，转换为JSON格式
        jsonData = _convertXmlToJson(fileContent);
      } else {
        // JSON文件，直接解析
        jsonData = json.decode(fileContent);
      }

      // 解析弹幕数据，支持多种格式
      List<dynamic> comments = [];

      if (jsonData.containsKey('comments') && jsonData['comments'] is List) {
        // 标准格式：comments字段包含数组
        comments = jsonData['comments'];
      } else if (jsonData.containsKey('data')) {
        // 兼容格式：data字段
        final data = jsonData['data'];
        if (data is List) {
          // data是数组
          comments = data;
        } else if (data is String) {
          // data是字符串，需要解析
          try {
            final parsedData = json.decode(data);
            if (parsedData is List) {
              comments = parsedData;
            } else {
              throw Exception('data字段的JSON字符串不是数组格式');
            }
          } catch (e) {
            throw Exception('data字段的JSON字符串解析失败: $e');
          }
        } else {
          throw Exception('data字段格式不正确，应为数组或JSON字符串');
        }
      } else {
        throw Exception('JSON文件格式不正确，必须包含comments数组或data字段');
      }

      if (comments.isEmpty) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      // 获取VideoPlayerState并计算轨道编号
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      final remoteTrackCount = videoState.danmakuTracks.values
          .where((track) => track['source'] == 'remote')
          .length;
      final trackName = '远程弹幕${remoteTrackCount + 1}';

      // 添加弹幕轨道 - 使用trackName和source参数
      await videoState.loadDanmakuFromLocal(jsonData, trackName: trackName);

      if (mounted) {
        BlurSnackBar.show(context, '远程弹幕轨道添加成功，共${comments.length}条弹幕');
        _remoteUrlController.clear();
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '加载远程弹幕失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRemoteDanmaku = false;
        });
      }
    }
  }

  // XML弹幕转换为JSON格式
  Map<String, dynamic> _convertXmlToJson(String xmlContent) {
    final List<Map<String, dynamic>> comments = [];

    // 使用正则表达式解析XML弹幕格式: <d p="参数">内容</d>
    final RegExp danmakuRegex = RegExp(r'<d p="([^"]+)">([^<]+)</d>');
    final Iterable<RegExpMatch> matches = danmakuRegex.allMatches(xmlContent);

    for (final match in matches) {
      try {
        final String pAttr = match.group(1) ?? '';
        final String textContent = match.group(2) ?? '';

        if (textContent.isEmpty) continue;

        // 解析p属性中的参数，用逗号分隔
        final List<String> pParams = pAttr.split(',');

        if (pParams.length >= 4) {
          // XML弹幕格式参数：时间,类型,字号,颜色,时间戳,池,用户id,弹幕id
          final double time = double.tryParse(pParams[0]) ?? 0.0;
          final int typeCode = int.tryParse(pParams[1]) ?? 1;
          final int fontSize = int.tryParse(pParams[2]) ?? 25;
          final int colorCode = int.tryParse(pParams[3]) ?? 16777215; // 默认白色

          // 将类型代码转换为弹幕类型
          String danmakuType;
          switch (typeCode) {
            case 4:
              danmakuType = 'bottom';
              break;
            case 5:
              danmakuType = 'top';
              break;
            case 1:
            case 6:
            default:
              danmakuType = 'scroll';
              break;
          }

          // 将颜色代码转换为RGB格式
          final int r = (colorCode >> 16) & 0xFF;
          final int g = (colorCode >> 8) & 0xFF;
          final int b = colorCode & 0xFF;
          final String color = 'rgb($r,$g,$b)';

          // 创建标准化的弹幕对象
          final Map<String, dynamic> comment = {
            't': time, // 时间
            'c': textContent, // 内容
            'y': danmakuType, // 类型
            'r': color, // 颜色
            'fontSize': fontSize, // 字号
            'originalType': typeCode, // 原始类型代码
          };

          comments.add(comment);
        }
      } catch (e) {
        // 跳过无效的弹幕项，继续处理下一个
        continue;
      }
    }

    return {
      'count': comments.length,
      'comments': comments,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final tracks = videoState.danmakuTracks;
        final trackEnabled = videoState.danmakuTrackEnabled;
        final totalDanmakuCount = videoState.totalDanmakuCount;
        final filteredDanmakuCount = videoState.danmakuList.length;

        return BaseSettingsMenu(
          title: '弹幕轨道',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 总览信息
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withOpacity(0.5),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '弹幕轨道总览',
                            locale: Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '共${tracks.length}个轨道，合计$totalDanmakuCount条弹幕',
                            locale: Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                          if (totalDanmakuCount != filteredDanmakuCount)
                            Text(
                              '显示: $filteredDanmakuCount条 (已过滤${totalDanmakuCount - filteredDanmakuCount}条)',
                              locale: Locale("zh-Hans", "zh"),
                              style: TextStyle(
                                color: Colors.orange.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 轨道列表
              ...tracks.entries.map((entry) {
                final trackId = entry.key;
                if (trackId == 'timeline')
                  return const SizedBox.shrink(); // 不在列表中显示时间轴轨道
                final trackData = entry.value;
                final isEnabled = trackEnabled[trackId] ?? false;
                final trackName = trackData['name'] as String;
                final source = trackData['source'] as String;
                final count = trackData['count'] as int;

                IconData trackIcon;

                switch (source) {
                  case 'dandanplay':
                    trackIcon = Icons.cloud;
                    break;
                  case 'remote':
                    trackIcon = Icons.cloud_download;
                    break;
                  case 'local':
                    trackIcon = Icons.folder;
                    break;
                  default:
                    trackIcon = Icons.track_changes;
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        videoState.toggleDanmakuTrack(trackId, !isEnabled),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? Colors.white.withOpacity(0.1)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withOpacity(0.5),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isEnabled
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            trackIcon,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trackName,
                                  locale: Locale("zh-Hans", "zh"),
                                  style: TextStyle(
                                    color: isEnabled
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                    fontWeight: isEnabled
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  '$count条弹幕',
                                  locale: Locale("zh-Hans", "zh"),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 删除按钮（本地和远程轨道都显示）
                          if (source == 'local' || source == 'remote')
                            GestureDetector(
                              onTap: () =>
                                  videoState.removeDanmakuTrack(trackId),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // 添加本地弹幕轨道按钮
              _isLoadingLocalDanmaku
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '正在加载弹幕文件...',
                            locale: Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : BlurButton(
                      icon: Icons.add_circle_outline,
                      text: "加载本地弹幕文件",
                      onTap: _loadLocalDanmakuFile,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      margin: const EdgeInsets.symmetric(horizontal: 0),
                      expandHorizontally: true,
                      borderRadius: BorderRadius.zero,
                    ),
              const SizedBox(height: 12),
              // 远程弹幕URL输入区域
              if (_isLoadingRemoteDanmaku)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '正在加载远程弹幕...',
                        locale: Locale("zh-Hans", "zh"),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_showRemoteUrlInput)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '输入弹幕URL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          TextField(
                            controller: _remoteUrlController,
                            focusNode: _focusNode,
                            decoration: InputDecoration(
                              hintText: 'https://example.com/danmaku.json',
                              hintStyle: const TextStyle(color: Colors.grey),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.1),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: const BorderSide(
                                  color: Colors.white,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                            ),
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.url,
                            onSubmitted: (_) => _loadRemoteDanmakuUrl(),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: _cancelRemoteUrlInput,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  child: const Text('取消'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _loadRemoteDanmakuUrl,
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor: Colors.black,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  child: const Text('加载'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                BlurButton(
                  icon: Icons.cloud_download_outlined,
                  text: "加载远程弹幕URL",
                  onTap: _toggleRemoteUrlInput,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  margin: const EdgeInsets.symmetric(horizontal: 0),
                  expandHorizontally: true,
                  borderRadius: BorderRadius.zero,
                )
            ],
          ),
        );
      },
    );
  }
}
