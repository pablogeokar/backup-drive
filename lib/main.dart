import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/database_page.dart';
import 'services/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.initialize();
  runApp(const BackupDriveApp());
}

class BackupDriveApp extends StatelessWidget {
  const BackupDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF1456A3);
    const ink = Color(0xFF0B1F3A);
    const muted = Color(0xFF5F6B7A);
    const canvas = Color(0xFFF5F7FA);
    const border = Color(0xFFCCE1F5);
    final scheme = ColorScheme.fromSeed(seedColor: brand).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE6F0FA),
      onPrimaryContainer: const Color(0xFF0C2D56),
      surface: Colors.white,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
      surfaceContainer: Colors.white,
      surfaceContainerLowest: canvas,
      surfaceContainerHighest: const Color(0xFFE6F0FA),
    );
    return MaterialApp(
      title: 'Kontabb Backup Drive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE6F0FA),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ),
      themeMode: ThemeMode.light,
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
