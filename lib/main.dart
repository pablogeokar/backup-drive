import 'dart:io';

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/database_page.dart';

void main() {
  runApp(const BackupDriveApp());
}

class BackupDriveApp extends StatelessWidget {
  const BackupDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    final defaultFont = Platform.isWindows ? 'Segoe UI' : null;

    return MaterialApp(
      title: 'Kontabb Backup Drive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F62FE),
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: defaultFont,
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
        fontFamily: defaultFont,
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
      home: const _BackupShell(),
    );
  }
}

class _BackupShell extends StatefulWidget {
  const _BackupShell();
  @override
  State<_BackupShell> createState() => _BackupShellState();
}

class _BackupShellState extends State<_BackupShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: index,
      children: const [HomePage(), DatabasePage()],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (v) => setState(() => index = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.cloud_sync_outlined),
          selectedIcon: Icon(Icons.cloud_sync),
          label: 'Cloudflare R2',
        ),
        NavigationDestination(
          icon: Icon(Icons.storage_outlined),
          selectedIcon: Icon(Icons.storage),
          label: 'PostgreSQL',
        ),
      ],
    ),
  );
}
