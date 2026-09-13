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
    final args = <String>['-env', envFile, '-schema', schema];
    switch (operation) {
      case DatabaseOperation.backup:
        args.addAll(['-mode', 'backup', '-output', outputFile!]);
      case DatabaseOperation.restore:
        args.addAll(['-mode', 'restore', '-input', inputFile!]);
        if (dryRun) args.add('-dry-run');
        if (noTruncate) args.add('-no-truncate');
      case DatabaseOperation.validate:
        args.add('-validate');
    }
    final process = await Process.start(helperPath, args, runInShell: false);
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
    return DatabaseBackupResult(exitCode: code, output: lines.join('\n'));
  }

  Future<void> cancel() async {
    final process = _process;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    process.kill(ProcessSignal.sigkill);
  }
}
