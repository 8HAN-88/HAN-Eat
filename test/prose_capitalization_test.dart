import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/widgets/create_poll_form_section.dart';

void main() {
  testWidgets('poll fields ask the keyboard to start with a capital',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatePollFormSection(
            questionController: TextEditingController(),
            optionControllers: [
              TextEditingController(),
              TextEditingController(),
            ],
            onAddOption: () {},
            onRemoveOption: (_) {},
          ),
        ),
      ),
    );

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, isNotEmpty);
    expect(
      fields.every(
          (field) => field.textCapitalization == TextCapitalization.sentences),
      isTrue,
    );
  });
}
