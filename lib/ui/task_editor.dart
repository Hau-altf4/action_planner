import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/app_state.dart';

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({super.key, required this.appState, this.task});

  final AppState appState;
  final PlannerTask? task;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _minutes;
  late String _category;
  late TaskPriority _priority;
  late DateTime _deadline;
  bool _saving = false;
  bool _analyzing = false;
  List<TaskStep> _steps = [];
  String? _aiSuggestion;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title);
    _description = TextEditingController(text: task?.description);
    _minutes = TextEditingController(text: '${task?.estimatedMinutes ?? 30}');
    _category = task?.category ?? 'Cá nhân';
    _priority = task?.priority ?? TaskPriority.medium;
    _deadline = task?.deadline ?? DateTime.now().add(const Duration(hours: 3));
    _steps = List.of(task?.steps ?? const []);
    _aiSuggestion = task?.aiSuggestion;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _deadline.isBefore(DateTime.now())
          ? DateTime.now()
          : _deadline,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (time == null) return;
    setState(
      () => _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    final old = widget.task;
    final task = PlannerTask(
      id: old?.id ?? 'local-${DateTime.now().millisecondsSinceEpoch}',
      title: _title.text.trim(),
      description: _description.text.trim(),
      category: _category,
      priority: _priority,
      status: old?.status ?? TaskStatus.pending,
      estimatedMinutes: int.parse(_minutes.text),
      deadline: _deadline,
      scheduledStart: old?.scheduledStart,
      steps: _steps,
      aiSuggestion: _aiSuggestion,
    );
    try {
      await widget.appState.saveTask(task);
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể lưu công việc: $exception')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _analyze() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy nhập tên công việc trước.')),
      );
      return;
    }
    setState(() => _analyzing = true);
    try {
      final result = await widget.appState.analyzeTask(
        _title.text.trim(),
        _description.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _priority = result.priority;
        _minutes.text = '${result.estimatedMinutes}';
        _steps = [
          for (var i = 0; i < result.steps.length; i++)
            TaskStep(id: 'ai-$i', title: result.steps[i]),
        ];
        _aiSuggestion = result.suggestion;
      });
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể phân tích: $exception')),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Công việc mới' : 'Chỉnh sửa'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _title,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
              decoration: const InputDecoration(labelText: 'Tên công việc'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Vui lòng nhập tên công việc'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Mô tả'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _analyzing ? null : _analyze,
              icon: _analyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: const Text('AI phân tích và chia nhỏ công việc'),
            ),
            if (_steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Các bước AI đề xuất',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      ..._steps.map((step) => Text('• ${step.title}')),
                      if (_aiSuggestion != null) ...[
                        const SizedBox(height: 8),
                        Text(_aiSuggestion!),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Danh mục'),
              items: ['Cá nhân', 'Học tập', 'Công việc', 'Sức khỏe']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TaskPriority>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Mức ưu tiên'),
              items: TaskPriority.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _priority = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Thời gian ước tính',
                suffixText: 'phút',
              ),
              validator: (value) {
                final minutes = int.tryParse(value ?? '');
                return minutes == null || minutes <= 0
                    ? 'Thời gian phải lớn hơn 0'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: const BorderSide(color: Colors.black26),
              ),
              leading: const Icon(Icons.event_outlined),
              title: const Text('Hạn hoàn thành'),
              subtitle: Text(_date(_deadline)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDeadline,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Lưu công việc'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
