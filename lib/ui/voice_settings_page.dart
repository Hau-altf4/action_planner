import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/task_repository.dart';
import '../state/app_state.dart';

class VoiceSettingsPage extends StatefulWidget {
  const VoiceSettingsPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends State<VoiceSettingsPage> {
  final FlutterTts _tts = FlutterTts();
  String _gender = 'female';
  String _region = 'northern';
  List<_DeviceVoiceOption> _deviceVoices = const [];
  String? _selectedDeviceVoice;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.appState.loadVoiceSettings();
    if (!mounted) return;
    final settings = widget.appState.voiceSettings;
    final rawVoices = await _tts.getVoices;
    if (!mounted) return;
    final available = <_DeviceVoiceOption>[];
    if (rawVoices is List) {
      for (final item in rawVoices) {
        if (item is! Map) continue;
        final name = '${item['name'] ?? ''}'.trim();
        final locale = '${item['locale'] ?? ''}'.trim();
        if (name.isEmpty || !locale.toLowerCase().startsWith('vi')) continue;
        final option = _DeviceVoiceOption(name, locale);
        if (!available.any((voice) => voice.key == option.key)) {
          available.add(option);
        }
      }
    }
    final savedKey =
        '${settings.deviceVoiceName}|${settings.deviceVoiceLocale}';
    setState(() {
      _gender = settings.gender;
      _region = settings.region;
      _deviceVoices = available;
      _selectedDeviceVoice = available.any((voice) => voice.key == savedKey)
          ? savedKey
          : available.firstOrNull?.key;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final selected = _deviceVoices
          .where((voice) => voice.key == _selectedDeviceVoice)
          .firstOrNull;
      await widget.appState.saveVoiceSettings(
        VoiceSettings(
          gender: _gender,
          region: _region,
          deviceVoiceName: selected?.name ?? '',
          deviceVoiceLocale: selected?.locale ?? '',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cài đặt giọng đọc.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể lưu giọng đọc: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.appState.voiceSettings;
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt giọng đọc')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (settings.customizable) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: 'Giọng đọc',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('Nữ')),
                      DropdownMenuItem(value: 'male', child: Text('Nam')),
                    ],
                    onChanged: (value) => setState(() => _gender = value!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _region,
                    decoration: const InputDecoration(
                      labelText: 'Vùng miền',
                      prefixIcon: Icon(Icons.language_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'northern',
                        child: Text('Miền Bắc'),
                      ),
                      DropdownMenuItem(
                        value: 'central',
                        child: Text('Miền Trung'),
                      ),
                      DropdownMenuItem(
                        value: 'southern',
                        child: Text('Miền Nam'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _region = value!),
                  ),
                ] else if (_deviceVoices.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDeviceVoice,
                    decoration: const InputDecoration(
                      labelText: 'Giọng tiếng Việt trên thiết bị',
                      prefixIcon: Icon(Icons.record_voice_over_outlined),
                    ),
                    items: _deviceVoices
                        .map(
                          (voice) => DropdownMenuItem(
                            value: voice.key,
                            child: Text(voice.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedDeviceVoice = value),
                  )
                else
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Chưa tìm thấy giọng tiếng Việt'),
                      subtitle: Text(
                        'Hãy cài giọng tiếng Việt trong phần Chuyển văn bản thành giọng nói của điện thoại.',
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Card(
                  child: ListTile(
                    leading: Icon(
                      settings.configured
                          ? Icons.cloud_done_outlined
                          : Icons.phone_android_outlined,
                    ),
                    title: Text(
                      settings.configured
                          ? 'Đang dùng ${settings.engine}'
                          : 'TTS thiết bị — phản hồi tức thì',
                    ),
                    subtitle: const Text(
                      'Chỉ hiển thị các giọng tiếng Việt thực sự có trên điện thoại này.',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Đang lưu…' : 'Lưu giọng đọc'),
                ),
              ],
            ),
    );
  }
}

class _DeviceVoiceOption {
  const _DeviceVoiceOption(this.name, this.locale);

  final String name;
  final String locale;

  String get key => '$name|$locale';
  String get label => '$name ($locale)';
}
