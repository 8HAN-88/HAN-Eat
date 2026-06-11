import 'package:flutter/material.dart';

/// Экран загрузки (внутри единого GoRouter, без второго MaterialApp).
class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  static const path = '/boot';

  static const _orange = Color(0xFFFF6B35);
  static const _canvas = Color(0xFFF7F8FA);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _orange,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: Icon(
                      Icons.restaurant_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  'HAN Eat',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 20),
                CircularProgressIndicator(color: _orange),
                SizedBox(height: 16),
                Text(
                  'Запуск…',
                  style: TextStyle(fontSize: 16, color: Color(0xFF5C5C5C)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
