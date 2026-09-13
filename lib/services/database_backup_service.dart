import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  String get helperPath {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$executableDir/kontabb-bkp',
      '${Directory(executableDir).parent.path}/Resources/kontabb-bkp',
      // Flutter macOS debug runs the Dart executable outside the app bundle.
      '${Directory.current.path}/../backup-restore/bin/kontabb-bkp',
      '${Directory.current.path}/backup-restore/bin/kontabb-bkp',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
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
    final databaseUrl = _readDatabaseUrl(envContents);
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw const ProcessException('kontabb-bkp', [], 'O arquivo .env não contém DATABASE_URL.', 2);
    }
    final args = <String>['-database-url-from-env', '-schema', schema];
    final temporaryOutput = operation == DatabaseOperation.backup
        ? '${Directory.systemTemp.path}/kontabb-backup-${DateTime.now().microsecondsSinceEpoch}.sql.gz'
        : null;
    final temporaryInput = operation == DatabaseOperation.restore
        ? '${Directory.systemTemp.path}/kontabb-restore-${DateTime.now().microsecondsSinceEpoch}${inputFile!.toLowerCase().endsWith('.gz') ? '.sql.gz' : '.sql'}'
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

  String? _readDatabaseUrl(String contents) {
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
    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    process.kill(ProcessSignal.sigkill);
  }
}
