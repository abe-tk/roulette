import 'package:flutter/material.dart';
import 'package:roulette/roulette/roulette_page.dart';

void main() {
  runApp(const RouletteApp());
}

/// アプリのルート。
class RouletteApp extends StatelessWidget {
  /// ルートウィジェットを作る。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roulette',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFB8860B),
      ),
      home: const RoulettePage(),
    );
  }
}
