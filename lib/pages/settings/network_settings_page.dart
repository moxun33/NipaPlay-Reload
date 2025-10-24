import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  String _currentServer = '';
  bool _isLoading = true;
  List<Map<String, String>> _servers = [];
  final GlobalKey _serverDropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final server = await NetworkSettings.getDandanplayServer();
    final servers = await NetworkSettings.getAllAvailableServers();
    
    if (mounted) {
      setState(() {
        _currentServer = server;
        _servers = servers;
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshServers() async {
    final servers = await NetworkSettings.getAllAvailableServers();
    if (mounted) {
      setState(() {
        _servers = servers;
      });
    }
  }

  Future<void> _changeServer(String serverUrl) async {
    await NetworkSettings.setDandanplayServer(serverUrl);
    if (mounted) {
      setState(() {
        _currentServer = serverUrl;
      });
      
      final serverName = _getServerDisplayName(serverUrl);
      BlurSnackBar.show(context, '弹弹play服务器已切换到: $serverName');
    }
  }

  String _getServerDisplayName(String serverUrl) {
    final server = _servers.firstWhere(
      (s) => s['url'] == serverUrl,
      orElse: () => {'name': serverUrl}
    );
    return server['name']!;
  }

  List<DropdownMenuItemData> _getServerDropdownItems() {
    return _servers.map((server) {
      return DropdownMenuItemData(
        title: server['name']!,
        value: server['url']!,
        isSelected: _currentServer == server['url']!,
      );
    }).toList();
  }

  void _showAddServerDialog() {
    _showEditServerDialog();
  }

  void _showEditServerDialog({Map<String, String>? server}) {
    final isEdit = server != null;
    final nameController = TextEditingController(text: isEdit ? server['name'] : '');
    final urlController = TextEditingController(text: isEdit ? server['url'] : '');
    final descController = TextEditingController(text: isEdit ? server['description'] : '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.8),
          title: Text(isEdit ? '编辑服务器' : '添加服务器'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '服务器名称',
                    labelStyle: TextStyle(color: Colors.white70),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: '服务器URL',
                    hintText: 'http://example.com',
                    labelStyle: TextStyle(color: Colors.white70),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: '服务器描述（可选）',
                    labelStyle: TextStyle(color: Colors.white70),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                final description = descController.text.trim();

                if (name.isEmpty || url.isEmpty) {
                  BlurSnackBar.show(context, '请填写服务器名称和URL',);
                  return;
                }

                if (!NetworkSettings.isValidUrl(url)) {
                  BlurSnackBar.show(context, '请输入有效的URL（http或https开头）',);
                  return;
                }

                Navigator.pop(context);
                
                if (isEdit) {
                  await NetworkSettings.updateCustomServer(
                    server!['url']!,
                    name,
                    url,
                    description,
                  );
                  BlurSnackBar.show(context, '服务器已更新');
                } else {
                  await NetworkSettings.addCustomServer(name, url, description);
                  BlurSnackBar.show(context, '服务器已添加');
                }
                
                await _refreshServers();
              },
              child: Text(isEdit ? '保存' : '添加'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteServer(String url) async {
    final isCurrentServer = _currentServer == url;
    
    if (isCurrentServer) {
      BlurSnackBar.show(context, '不能删除当前正在使用的服务器',);
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.8),
          title: const Text('确认删除'),
          content: const Text('确定要删除此服务器吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await NetworkSettings.deleteCustomServer(url);
                BlurSnackBar.show(context, '服务器已删除');
                await _refreshServers();
              },
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          // 服务器选择
          SettingsItem.dropdown(
            title: "弹弹play服务器",
            subtitle: "选择弹弹play弹幕服务器。备用服务器可在主服务器无法访问时使用。",
            icon: Ionicons.server_outline,
            items: _getServerDropdownItems(),
            onChanged: (serverUrl) => _changeServer(serverUrl),
            dropdownKey: _serverDropdownKey,
          ),
          const Divider(color: Colors.white12, height: 1),
          
          // 显示当前服务器信息
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Ionicons.information_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '当前服务器信息',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '服务器: ${_getServerDisplayName(_currentServer)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'URL: $_currentServer',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 服务器列表管理
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Ionicons.server_outline,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '服务器管理',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: _showAddServerDialog,
                        icon: const Icon(Ionicons.add_circle_outline, size: 16),
                        label: const Text('添加服务器'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: _servers.map((server) {
                      final isCustom = server['isCustom'] == 'true';
                      final isSelected = _currentServer == server['url'];
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.black.withOpacity(0.3),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    server['name']!,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      if (isSelected)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: Icon(
                                            Ionicons.checkmark_circle,
                                            color: Colors.green,
                                            size: 16,
                                          ),
                                        ),
                                      if (isCustom)
                                        Row(
                                          children: [
                                            IconButton(
                                              onPressed: () => _showEditServerDialog(server: server),
                                              icon: const Icon(Ionicons.create_outline, size: 16),
                                              color: Colors.white70,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 32),
                                            ),
                                            IconButton(
                                              onPressed: () => _deleteServer(server['url']!),
                                              icon: const Icon(Ionicons.trash_outline, size: 16),
                                              color: Colors.red,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 32),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                server['url']!,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (server['description'] != null && server['description']!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    server['description']!,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (!isCustom)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    '系统默认服务器，不可编辑或删除',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}