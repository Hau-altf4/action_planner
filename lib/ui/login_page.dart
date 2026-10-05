import 'dart:async';

import 'package:flutter/material.dart';

import '../data/task_repository.dart';
import '../state/app_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _register = false;
  bool _hidePassword = true;
  bool _loading = false;
  bool _checkingBackend = true;
  bool _backendAvailable = false;
  String _backendStatus = 'Đang kiểm tra kết nối máy chủ...';
  String? _error;
  Timer? _backendRetryTimer;

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    if (mounted) {
      setState(() {
        _checkingBackend = true;
        _backendStatus = 'Đang kiểm tra kết nối máy chủ...';
      });
    }
    try {
      final selectedUrl = await widget.appState.repository.checkConnection();
      if (!mounted) return;
      setState(() {
        _checkingBackend = false;
        _backendAvailable = true;
        _backendStatus = 'Máy chủ đã sẵn sàng qua $selectedUrl';
      });
      _backendRetryTimer?.cancel();
      _backendRetryTimer = null;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingBackend = false;
        _backendAvailable = false;
        _backendStatus = '$error';
      });
      _backendRetryTimer?.cancel();
      _backendRetryTimer = Timer(const Duration(seconds: 5), () {
        _backendRetryTimer = null;
        if (mounted) _checkBackend();
      });
    }
  }

  @override
  void dispose() {
    _backendRetryTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.appState.signIn(
        name: _nameController.text,
        email: _emailController.text.trim(),
        password: _passwordController.text,
        register: _register,
      );
    } catch (exception) {
      if (mounted) {
        setState(
          () => _error = _register
              ? 'Không thể tạo tài khoản: $exception'
              : 'Không thể đăng nhập: $exception',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      child: Icon(Icons.auto_awesome, size: 34),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Action Planner AI',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _register
                          ? 'Tạo tài khoản để bắt đầu lập kế hoạch'
                          : 'Đăng nhập để quản lý ngày làm việc của bạn',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: _backendStatus,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_checkingBackend)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              _backendAvailable
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_off_outlined,
                              size: 18,
                              color: _backendAvailable
                                  ? Colors.green.shade700
                                  : Theme.of(context).colorScheme.error,
                            ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _backendStatus,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: _backendAvailable
                                    ? Colors.green.shade700
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          if (!_checkingBackend && !_backendAvailable)
                            IconButton(
                              tooltip: 'Thử kết nối lại',
                              onPressed: _checkBackend,
                              icon: const Icon(Icons.refresh, size: 18),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_register) ...[
                      TextFormField(
                        controller: _nameController,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        autocorrect: true,
                        enableSuggestions: true,
                        decoration: const InputDecoration(
                          labelText: 'Họ và tên',
                          hintText: 'Nhập họ và tên',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Vui lòng nhập họ tên'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'Nhập tài khoản email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) => value != null && value.contains('@')
                          ? null
                          : 'Email chưa hợp lệ',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        hintText: 'Nhập mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Vui lòng nhập mật khẩu';
                        }
                        if (_register && value.length < 6) {
                          return 'Mật khẩu cần ít nhất 6 ký tự';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_register ? 'Tạo tài khoản' : 'Đăng nhập'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _register = !_register),
                      child: Text(
                        _register
                            ? 'Đã có tài khoản? Đăng nhập'
                            : 'Chưa có tài khoản? Đăng ký',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      TaskRepository.usesMockData
                          ? 'Chế độ hiện tại dùng dữ liệu mẫu — không gửi thông tin ra ngoài.'
                          : '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
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
