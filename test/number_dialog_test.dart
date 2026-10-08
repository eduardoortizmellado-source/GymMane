import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/l10n/app_localizations.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/widgets/dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing a custom weight closes cleanly and returns the value', (tester) async {
    double? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await askNumber(context, title: 'Peso (kg)', initial: '30', decimal: true);
                },
                child: const Text('Editar'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '28');
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(result, 28);
    expect(tester.takeException(), isNull);
  });
}
