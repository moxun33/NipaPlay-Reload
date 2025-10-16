import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers/alist_provider.dart';

class AlistDialog extends StatefulWidget {
  const AlistDialog({super.key});

  @override
  State<AlistDialog> createState() => _AlistDialogState();
}

class _AlistDialogState extends State<AlistDialog> {
  bool _showServerForm = false;
  String? _editingHostId;
  bool _enabled = true;
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController(text: 'AList');
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFormController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFormController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlistProvider>(
      builder: (context, provider, child) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 12,
          backgroundColor: const Color(0xFF3A3A3A),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
            child: Scaffold(
              backgroundColor: const Color(0xFF2F2F2F),
              appBar: AppBar(
                title: const Text('AList 媒体库'),
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                  splashRadius: 20,
                ),
                backgroundColor: const Color(0xFF3A3A3A),
                elevation: 0,
                shape: const Border(
                  bottom: BorderSide(color: Colors.transparent),
                ),
              ),
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: _showServerForm
                    ? _buildServerForm(provider)
                    : _buildServerList(provider),
              ),
              floatingActionButton: !_showServerForm
                  ? FloatingActionButton.extended(
                      onPressed: () =>
                          _showServerFormMethod(provider: provider),
                      icon: const Icon(Icons.add),
                      label: const Text('添加服务器'),
                      elevation: 6,
                      backgroundColor: const Color(0xFF96F7E4),
                      foregroundColor: Colors.black,
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildServerList(AlistProvider provider) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (provider.errorMessage != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade700),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: provider.hosts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3A),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(Icons.cloud_off,
                            size: 60, color: theme.hintColor),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无AList服务器',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击右下角按钮添加服务器',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: provider.hosts.length,
                  itemBuilder: (context, index) {
                    final host = provider.hosts[index];
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: const Color(0xFF3A3A3A),
                      child: InkWell(
                        onTap: () async {
                          await provider.setActiveHost(host.id);
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: host.isOnline
                                  ? Colors.green.shade900
                                      .withValues(alpha: 0.3)
                                  : Colors.red.shade900
                                      .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/alist.svg',
                                width: 24,
                                height: 24,
                                colorFilter: ColorFilter.mode(
                                  host.isOnline ? Colors.green : Colors.red,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      host.displayName,
                                      style: theme.textTheme.titleMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(width: 8),
                                    if (!host.enabled)
                                      Chip(
                                        label: const Text('已禁用', style: TextStyle(fontSize: 10)),
                                        backgroundColor: Colors.grey.shade700,
                                        labelStyle: const TextStyle(color: Colors.grey),
                                        padding: EdgeInsets.zero,
                                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                                      ),
                                  ],
                                ),
                                Text(
                                  host.baseUrl,
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (host.username.isNotEmpty)
                                  Text(
                                    '用户名: ${host.username}',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: theme.hintColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                              PopupMenuButton<String>(
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'connect',
                                    child: Text('连接'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                                onSelected: (value) async {
                                  if (value == 'connect') {
                                    try {
                                      await provider.setActiveHost(host.id);
                                    } catch (e) {
                                      // 错误已经在provider中处理
                                    }
                                  } else if (value == 'edit') {
                                    _showServerFormMethod(
                                        hostId: host.id, provider: provider);
                                  } else if (value == 'delete') {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('确认删除'),
                                        content: Text(
                                            '确定要删除服务器 "${host.displayName}" 吗？'),
                                        backgroundColor:
                                            const Color(0xFF3A3A3A),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              await provider
                                                  .removeHost(host.id);
                                              Navigator.of(context).pop();
                                            },
                                            child: const Text('删除',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showServerFormMethod(
      {String? hostId, required AlistProvider provider}) {
    setState(() {
      _showServerForm = true;
      _editingHostId = hostId;
      _formKey.currentState?.reset();
      _displayNameController.clear();
      _baseUrlController.clear();
      _usernameController.clear();
      _passwordController.clear();

      // 如果是编辑模式，填充现有服务器信息
      if (hostId != null) {
        final host = provider.hosts.firstWhere((h) => h.id == hostId);
        _displayNameController.text = host.displayName;
        _baseUrlController.text = host.baseUrl;
        _usernameController.text = host.username;
        _enabled = host.enabled;
      } else {
        _enabled = true; // 新增服务器默认启用
      }
    });
  }

  Widget _buildServerForm(AlistProvider provider) {
    final theme = Theme.of(context);
    final isEditMode = _editingHostId != null;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditMode ? '编辑AList服务器' : '添加AList服务器',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            if (provider.errorMessage != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade700),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            TextFormField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: '服务器昵称',
                hintText: 'AList',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                filled: true,
                fillColor: const Color(0xFF3A3A3A),
                labelStyle: TextStyle(color: theme.hintColor),
                hintStyle:
                    TextStyle(color: theme.hintColor.withValues(alpha: 0.3)),
              ),
              validator: (value) {
                /* if (value?.trim().isEmpty ?? true) {
                  return '请输入服务器昵称';
                } */
                return null;
              },
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _baseUrlController,
              decoration: InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://example.com',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                filled: true,
                fillColor: const Color(0xFF3A3A3A),
                labelStyle: TextStyle(color: theme.hintColor),
                hintStyle:
                    TextStyle(color: theme.hintColor.withValues(alpha: 0.6)),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (value) {
                if (value?.trim().isEmpty ?? true) {
                  return '请输入服务器地址';
                }
                if (!Uri.tryParse(value!)!.hasScheme) {
                  return '请输入有效的URL (包含http/https)';
                }
                return null;
              },
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: '用户名',
                hintText: '可选',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                filled: true,
                fillColor: const Color(0xFF3A3A3A),
                labelStyle: TextStyle(color: theme.hintColor),
                hintStyle:
                    TextStyle(color: theme.hintColor.withValues(alpha: 0.6)),
              ),
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '可选',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                filled: true,
                fillColor: const Color(0xFF3A3A3A),
                labelStyle: TextStyle(color: theme.hintColor),
                hintStyle:
                    TextStyle(color: theme.hintColor.withValues(alpha: 0.6)),
              ),
              obscureText: true,
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text('启用服务器', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
              value: _enabled,
              onChanged: (bool value) {
                setState(() {
                  _enabled = value;
                });
              },
              activeColor: const Color(0xFF96F7E4),
              activeTrackColor: const Color(0xFF96F7E4).withOpacity(0.3),
              inactiveThumbColor: Colors.grey.shade600,
              inactiveTrackColor: Colors.grey.shade700,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showServerForm = false;
                      _editingHostId = null;
                      _formKey.currentState?.reset();
                      _displayNameController.clear();
                      _baseUrlController.clear();
                      _usernameController.clear();
                      _passwordController.clear();
                      _enabled = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.grey.shade700,
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) {
                      return;
                    }

                    final displayName = _displayNameController.text.trim();
                    final baseUrl = _baseUrlController.text.trim();
                    final username = _usernameController.text.trim();
                    final password = _passwordController.text;

                    try {
                      if (isEditMode) {
                        // 编辑模式
                        await provider.updateHost(
                          _editingHostId!,
                          displayName: displayName,
                          baseUrl: baseUrl,
                          username: username,
                          password: password,
                          enabled: _enabled,
                        );
                      } else {
                        // 添加模式
                        await provider.addHost(
                          displayName,
                          baseUrl: baseUrl,
                          username: username,
                          password: password,
                          enabled: _enabled,
                        );
                      }

                      setState(() {
                        _showServerForm = false;
                        _editingHostId = null;
                        _formKey.currentState?.reset();
                        _displayNameController.clear();
                        _baseUrlController.clear();
                        _usernameController.clear();
                        _passwordController.clear();
                      });
                    } catch (e) {
                      // 错误处理已在provider中完成
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: const Color(0xFF96F7E4),
                    foregroundColor: Colors.black,
                  ),
                  child: Text(isEditMode ? '保存' : '添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
