import 'package:flutter/material.dart';

import '../data/task_repository.dart';
import '../state/app_state.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key, required this.appState, this.admin = false});

  final AppState appState;
  final bool admin;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  String _provider = 'ollama';
  bool _enabled = false;
  bool _hasApiKey = false;
  bool _loading = true;
  bool _saving = false;
  bool _hideKey = true;

  static const _defaultModels = {
    'ollama': 'qwen3:1.7b',
    'openai': 'gpt-5.4-mini',
    'gemini': 'gemini-2.5-flash',
    'anthropic': 'claude-sonnet-4-5',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.appState.getAiSettings(admin: widget.admin);
      if (!mounted) return;
      setState(() {
        _provider = settings.provider;
        _model.text = settings.model;
        _baseUrl.text = settings.baseUrl;
        _enabled = widget.admin || settings.customAiEnabled;
        _hasApiKey = settings.hasApiKey;
      });
    } catch (error) {
      if (mounted) _show('Không thể tải cài đặt: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save({bool test = false}) async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    try {
      await widget.appState.saveAiSettings(
        AiSettings(
          provider: _provider,
          model: _model.text.trim(),
          baseUrl: _baseUrl.text.trim(),
          apiKey: _apiKey.text.trim(),
          customAiEnabled: widget.admin || _enabled,
          hasApiKey: _hasApiKey,
        ),
        admin: widget.admin,
      );
      if (test && !widget.admin) {
        await widget.appState.testAiSettings();
      }
      if (!mounted) return;
      _apiKey.clear();
      setState(() => _hasApiKey = _hasApiKey || _provider == 'ollama');
      _show(test ? 'Kết nối AI hoạt động tốt.' : 'Đã lưu cài đặt AI.');
    } catch (error) {
      if (mounted) _show('Không thể lưu/kết nối AI: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _model.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.admin ? 'AI mặc định hệ thống' : 'Cài đặt AI'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (!widget.admin)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _enabled,
                      title: const Text('Dùng AI riêng của tôi'),
                      subtitle: const Text(
                        'Tắt để sử dụng cấu hình mặc định của quản trị viên.',
                      ),
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    decoration: const InputDecoration(
                      labelText: 'Nhà cung cấp',
                      prefixIcon: Icon(Icons.auto_awesome),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'ollama',
                        child: Text('Ollama (local)'),
                      ),
                      DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                      DropdownMenuItem(
                        value: 'gemini',
                        child: Text('Google Gemini'),
                      ),
                      DropdownMenuItem(
                        value: 'anthropic',
                        child: Text('Anthropic Claude'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _provider = value;
                        _model.text = _defaultModels[value]!;
                        if (value == 'ollama' && _baseUrl.text.isEmpty) {
                          _baseUrl.text = 'http://127.0.0.1:11434';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _model,
                    decoration: const InputDecoration(
                      labelText: 'Tên model',
                      prefixIcon: Icon(Icons.memory),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Vui lòng nhập model'
                        : null,
                  ),
                  if (widget.admin) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _baseUrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Base URL (không bắt buộc)',
                        hintText: _provider == 'ollama'
                            ? 'http://127.0.0.1:11434'
                            : 'Để trống để dùng địa chỉ mặc định',
                        prefixIcon: const Icon(Icons.link),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        return text.isNotEmpty &&
                                !text.startsWith('http://') &&
                                !text.startsWith('https://')
                            ? 'URL phải bắt đầu bằng http:// hoặc https://'
                            : null;
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Địa chỉ máy chủ do quản trị viên quản lý để bảo vệ mạng nội bộ.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                  if (_provider != 'ollama') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _apiKey,
                      obscureText: _hideKey,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _hasApiKey
                            ? 'API key (đã lưu — nhập để thay đổi)'
                            : 'API key',
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hideKey = !_hideKey),
                          icon: Icon(
                            _hideKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          !_hasApiKey &&
                              (widget.admin || _enabled) &&
                              (value == null || value.trim().isEmpty)
                          ? 'Vui lòng nhập API key'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Khóa được mã hóa AES-256-GCM trên backend và không bao giờ được gửi trả về ứng dụng.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Đang lưu…' : 'Lưu cài đặt'),
                  ),
                  if (!widget.admin) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _save(test: true),
                      icon: const Icon(Icons.network_check),
                      label: const Text('Lưu và kiểm tra kết nối'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
