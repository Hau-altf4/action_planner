import 'package:action_planner/main.dart';
import 'package:action_planner/data/task_repository.dart';
import 'package:action_planner/models/task.dart';
import 'package:action_planner/state/app_state.dart';
import 'package:action_planner/ui/task_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schedule start is fixed and survives JSON round-trip', () async {
    final appState = AppState(MockTaskRepository());
    final fixedStart = DateTime(2026, 10, 2, 18, 55);
    final task = PlannerTask(
      id: 'local-fixed-time',
      title: 'Viết báo cáo',
      estimatedMinutes: 30,
      deadline: DateTime.now().add(const Duration(hours: 3)),
      scheduledStart: fixedStart,
    );

    appState.tasks.add(task);
    final first = appState.schedule.single;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = appState.schedule.single;
    final restored = PlannerTask.fromJson(task.toJson());

    expect(first.start, fixedStart);
    expect(second.start, first.start);
    expect(second.end, first.end);
    expect(restored.scheduledStart, task.scheduledStart);
  });

  testWidgets('shows the sign-in screen', (tester) async {
    await tester.pumpWidget(const ActionPlannerApp());
    await tester.pump();

    expect(find.text('Action Planner AI'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsWidgets);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    expect(
      tester.widget<TextFormField>(fields.at(0)).controller?.text,
      isEmpty,
    );
    expect(
      tester.widget<TextFormField>(fields.at(1)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('accepts Vietnamese text and keeps account fields empty', (
    tester,
  ) async {
    await tester.pumpWidget(const ActionPlannerApp());
    await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
    await tester.pump();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Nguyễn Hậu');
    await tester.enterText(fields.at(1), 'hau@gmail.com');

    expect(find.text('Nguyễn Hậu'), findsOneWidget);
    expect(find.text('hau@gmail.com'), findsOneWidget);
  });

  testWidgets('AI reply rebuilds without inherited widget assertion', (
    tester,
  ) async {
    await tester.pumpWidget(ActionPlannerApp(repository: MockTaskRepository()));
    final loginFields = find.byType(TextFormField);
    await tester.enterText(loginFields.at(0), 'hau@gmail.com');
    await tester.enterText(loginFields.at(1), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('AI'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Sắp xếp công việc');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Gợi ý:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login does not apply registration password length rule', (
    tester,
  ) async {
    await tester.pumpWidget(ActionPlannerApp(repository: MockTaskRepository()));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'admin@gmail.com');
    await tester.enterText(fields.at(1), '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump();

    expect(find.text('Mật khẩu cần ít nhất 6 ký tự'), findsNothing);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('leaving task editor while AI runs does not call setState', (
    tester,
  ) async {
    final appState = AppState(MockTaskRepository());
    await tester.pumpWidget(
      MaterialApp(home: TaskEditorPage(appState: appState)),
    );
    await tester.enterText(find.byType(TextFormField).first, 'Việc phức tạp');
    await tester.tap(find.text('AI phân tích và chia nhỏ công việc'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('requesting a revised plan safely replaces the dialog', (
    tester,
  ) async {
    await tester.pumpWidget(ActionPlannerApp(repository: MockTaskRepository()));
    final loginFields = find.byType(TextFormField);
    await tester.enterText(loginFields.at(0), 'hau@gmail.com');
    await tester.enterText(loginFields.at(1), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Lịch'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Đề xuất'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Phương án AI đề xuất'), findsOneWidget);

    await tester.tap(find.text('Chưa hợp lý'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Bạn muốn điều chỉnh thế nào?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
