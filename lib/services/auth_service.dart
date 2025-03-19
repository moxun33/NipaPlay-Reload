class AuthService {
  String? _username;
  String? _email;

  String? get username => _username;
  String? get email => _email;

  // 登录
  void login(String username, String email) {
    _username = username;
    _email = email;
    print('User logged in: $username');
  }

  // 退出登录
  void logout() {
    _username = null;
    _email = null;
    print('User logged out');
  }
}