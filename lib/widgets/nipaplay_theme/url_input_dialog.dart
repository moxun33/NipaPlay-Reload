import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

/// URL输入对话框组件，用于输入视频URL进行播放
class UrlInputDialog extends StatefulWidget {
  final String title;
  final String initialUrl;
  final Function(String url) onUrlConfirmed;

  const UrlInputDialog({
    super.key,
    this.title = '输入视频URL',
    this.initialUrl = '',
    required this.onUrlConfirmed,
  });

  @override
  State<UrlInputDialog> createState() => _UrlInputDialogState();

  static Future<void> show(
    BuildContext context, {
    String title = '输入视频URL',
    String initialUrl = '',
    required Function(String url) onUrlConfirmed,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => UrlInputDialog(
        title: title,
        initialUrl: initialUrl,
        onUrlConfirmed: onUrlConfirmed,
      ),
    );
  }
}

class _UrlInputDialogState extends State<UrlInputDialog> {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  String? _errorText;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl;
    // 如果有初始URL，选中全部文本
    if (widget.initialUrl.isNotEmpty) {
      _urlController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialUrl.length,
      );
    }
    // 延迟请求焦点，确保对话框已经完全显示
    Future.delayed(const Duration(milliseconds: 100), () {
      _urlFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  bool _validateUrl(String url) {
    // 检查是否为空
    if (url.trim().isEmpty) {
      setState(() {
        _errorText = '请输入URL';
      });
      return false;
    }

    // 检查是否是有效的HTTP/HTTPS URL
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() {
        _errorText = '请输入有效的HTTP或HTTPS URL';
      });
      return false;
    }

    setState(() {
      _errorText = null;
    });
    return true;
  }

  void _handleConfirm() async {
    final url = _urlController.text.trim();
    if (!_validateUrl(url)) {
      return;
    }

    // 显示加载状态
    setState(() {
      _isLoading = true;
    });

    try {
      // 模拟网络请求延迟
      await Future.delayed(const Duration(milliseconds: 500));
      // 调用回调函数处理确认的URL
      widget.onUrlConfirmed(url);
      // 关闭对话框
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _errorText = '处理URL时出错：$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final enableBlur = 
        context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Container(
          width: dialogWidth,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: enableBlur ? 25 : 0,
                sigmaY: enableBlur ? 25 : 0,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 标题
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // URL输入框
                    TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: '视频URL',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'http://或https://',
                        hintStyle: const TextStyle(color: Colors.white54),
                        errorText: _errorText,
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        errorBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red),
                        ),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleConfirm(),
                      onChanged: (_) {
                        if (_errorText != null) {
                          setState(() {
                            _errorText = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    // 按钮区域
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 取消按钮
                        TextButton(
                          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                          child: const Text(
                            '取消',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 确认按钮
                        TextButton(
                          onPressed: _isLoading ? null : _handleConfirm,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  '确认',
                                  style: TextStyle(color: Colors.white),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}