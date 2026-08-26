import 'package:flutter/material.dart';

import 'pages/home_page.dart';

void main() {
  runApp(const BackupDriveApp());
}

class BackupDriveApp extends StatelessWidget {
  const BackupDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kontabb Backup Drive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F62FE),
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Segoe UI',
        visualDensity: VisualDensity.compact,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F62FE),
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        visualDensity: VisualDensity.compact,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
