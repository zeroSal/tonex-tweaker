import 'package:flutter/material.dart';

import 'tonex/tonex_controller.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TonexTweakerApp(controller: TonexController()..start()));
}

class TonexTweakerApp extends StatelessWidget {
  const TonexTweakerApp({super.key, required this.controller});

  final TonexController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToneX Tweaker',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7A00), brightness: Brightness.dark),
      ),
      home: HomePage(controller: controller),
    );
  }
}
