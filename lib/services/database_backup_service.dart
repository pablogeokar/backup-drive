import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum DatabaseOperation { backup, restore, validate }

class DatabaseBackupResult {
  const DatabaseBackupResult({required this.exitCode, required this.output});
  final int exitCode;
  final String output;
  bool get succeeded => exitCode == 0;
}

/// Runs the signed helper shipped beside the desktop executable. Arguments are
/// passed as a list so paths and connection settings never go through a shell.
class DatabaseBackupService {
  Process? _process;

  /// Obtém o caminho do binário auxiliar kontabb-bkp compatível com Windows e macOS.
  String get helperPath {
    final customPath = Platform.environment['KONTABB_BKP_PATH'];
    if (customPath != null && customPath.isNotEmpty && File(customPath).existsSync()) {
      return customPath;
    }

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final isWin = Platform.isWindows;
    final exeNames = isWin
        ? const ['kontabb-bkp.exe', 'kontabb-bkp']
        : const ['kontabb-bkp', 'kontabb-bkp.exe'];

    final candidates = <String>[];
    for (final name in exeNames) {
      // 1. Ao lado do executável principal (Windows release ou macOS Contents/MacOS)
      candidates.add(p.join(executableDir, name));

      // 2. macOS app bundle Resources ou MacOS
      final appContentsDir = Directory(executableDir).parent.path;
      candidates.add(p.join(appContentsDir, 'Resources', name));
      candidates.add(p.join(appContentsDir, 'MacOS', name));

      // 3. Estrutura do workspace em desenvolvimento
      candidates.add(p.join(Directory.current.path, '..', 'Kontabb-backup-restore', 'bin', name));
      candidates.add(p.join(Directory.current.path, '..', 'backup-restore', 'bin', name));
      candidates.add(p.join(Directory.current.path, 'Kontabb-backup-restore', 'bin', name));
      candidates.add(p.join(Directory.current.path, 'backup-restore', 'bin', name));
      candidates.add(p.join(Directory.current.path, 'bin', name));
    }

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return p.normalize(candidate);
    }
    throw ProcessException(
      'kontabb-bkp',
      const [],
      'Helper PostgreSQL não encontrado. Recompile o aplicativo para empacotar o binário.',
      127,
    );
  }

  Future<DatabaseBackupResult> run({
    required DatabaseOperation operation,
    required String envFile,
    String? outputFile,
    String? inputFile,
    bool dryRun = false,
    bool noTruncate = false,
    String schema = 'public',
    void Function(String line)? onLine,
  }) async {
    final envContents = await File(envFile).readAsString();
    final databaseUrl = parseDatabaseUrl(envContents);
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw const ProcessException('kontabb-bkp', [], 'O arquivo .env não contém DATABASE_URL.', 2);
    }
    final args = <String>['-database-url-from-env', '-schema', schema];
    final temporaryOutput = operation == DatabaseOperation.backup
        ? p.join(
            Directory.systemTemp.path,
            'kontabb-backup-${DateTime.now().microsecondsSinceEpoch}.sql.gz',
          )
        : null;
    final temporaryInput = operation == DatabaseOperation.restore
        ? p.join(
            Directory.systemTemp.path,
            'kontabb-restore-${DateTime.now().microsecondsSinceEpoch}${inputFile!.toLowerCase().endsWith('.gz') ? '.sql.gz' : '.sql'}',
          )
        : null;
    if (temporaryInput != null) await File(inputFile!).copy(temporaryInput);
    switch (operation) {
      case DatabaseOperation.backup:
        args.addAll(['-mode', 'backup', '-output', temporaryOutput!]);
      case DatabaseOperation.restore:
        args.addAll(['-mode', 'restore', '-input', temporaryInput!]);
        if (dryRun) args.add('-dry-run');
        if (noTruncate) args.add('-no-truncate');
      case DatabaseOperation.validate:
        args.add('-validate');
    }
    final environment = Map<String, String>.from(Platform.environment)
      ..['DATABASE_URL'] = databaseUrl;
    final process = await Process.start(helperPath, args, runInShell: false, environment: environment);
    _process = process;
    final lines = <String>[];
    Future<void> collect(Stream<List<int>> stream) async {
      await for (final line
          in stream.transform(utf8.decoder).transform(const LineSplitter())) {
        lines.add(line);
        onLine?.call(line);
      }
    }

    await Future.wait([collect(process.stdout), collect(process.stderr)]);
    final code = await process.exitCode;
    _process = null;
    if (code == 0 && temporaryOutput != null) {
      await File(temporaryOutput).copy(outputFile!);
    }
    if (temporaryOutput != null) {
      try { await File(temporaryOutput).delete(); } catch (_) {}
    }
    if (temporaryInput != null) {
      try { await File(temporaryInput).delete(); } catch (_) {}
    }
    return DatabaseBackupResult(exitCode: code, output: lines.join('\n'));
  }

  /// Extrai o valor de DATABASE_URL a partir do conteúdo de um arquivo .env.
  static String? parseDatabaseUrl(String contents) {
    for (final raw in const LineSplitter().convert(contents)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(r'^DATABASE_URL\s*=\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      var value = match.group(1)!.trim();
      if (value.length >= 2 && ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
    return null;
  }

  Future<void> cancel() async {
    final process = _process;
    if (process == null) return;
    if (Platform.isWindows) {
      process.kill();
    } else {
      process.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      process.kill(ProcessSignal.sigkill);
    }
  }
}
