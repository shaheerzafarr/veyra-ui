import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veyra/core/theme/app_theme.dart';
import 'package:veyra/features/app_ui/veyra_feature_screens.dart';
import 'package:veyra/main.dart';

void main() {
  testWidgets('Chats filters and New Chat route are available', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
        MaterialApp(theme: veyraTheme(), home: const MainNavigation()));

    expect(find.text('RECENT CONVERSATIONS'), findsOneWidget);
    expect(find.text('Message requests'), findsOneWidget);
    expect(find.text('Shaheer Malik'), findsNothing);
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('Aisha Khan'), findsOneWidget);
    expect(find.text('Leila Hassan'), findsNothing);

    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);
  });

  testWidgets('Settings opens a functional Privacy page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
        MaterialApp(theme: veyraTheme(), home: const MainNavigation()));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Discoverable profile'), findsOneWidget);
    expect(find.text('Who can send requests'), findsOneWidget);
    await tester.tap(find.text('Who can send requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nobody'));
    await tester.pumpAndSettle();
    expect(find.text('Nobody'), findsOneWidget);
  });

  testWidgets('Message long press can add a reaction and copy text',
      (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(
        theme: veyraTheme(),
        home: const VeyraConversationScreen(name: 'Aisha Khan')));

    await tester.longPress(find.text('Hey! How is it going?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('React with a heart'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.longPress(find.text('Hey! How is it going?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy message'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(copiedText, 'Hey! How is it going?');
  });

  testWidgets('Sent messages show delivery ticks and voice recorder opens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(
        theme: veyraTheme(),
        home: const VeyraConversationScreen(name: 'Aisha Khan')));

    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Voice message'));
    await tester.pumpAndSettle();
    expect(find.text('Record voice message'), findsOneWidget);
    expect(find.textContaining('Mock recording'), findsOneWidget);
  });

  testWidgets('Profile fields save without lifecycle errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
        MaterialApp(theme: veyraTheme(), home: const MainNavigation()));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display name'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Shaheer Veyra');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Shaheer Veyra'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
