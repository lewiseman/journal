import 'package:flutter/material.dart';
import 'package:journal/common.dart';
import 'package:journal/modules/root/views/widgets/onboarding_body.dart';
import 'package:journal/modules/assistant/qvac_assistant_scope.dart';

class OnboardingPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return QvacAssistantPage(enabled: false, child: OnboardingBody());
  }
}
