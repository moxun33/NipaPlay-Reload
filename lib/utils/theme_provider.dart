import 'package:flutter/material.dart';

bool isDarkMode(BuildContext context) {
  Brightness brightness = MediaQuery.of(context).platformBrightness;
  bool systemDarkMode = brightness == Brightness.dark;
  return systemDarkMode;
}
class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;
  // 切换主题模式
  void toggleDarkMode(String mode, BuildContext context) {
    if (mode == 'day') {
      _isDarkMode = false; // 设置为日间模式
    } else if (mode == 'night') {
      _isDarkMode = true; // 设置为夜间模式
    }
    notifyListeners(); // 通知所有监听者
  }

  // 新增方法：更新主色调
  void updateDraw() {
    notifyListeners();
  }
}
