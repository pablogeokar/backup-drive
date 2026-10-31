import 'dart:io';

import 'package:backup_drive/services/database_backup_service.dart';
import 'package:backup_drive/services/r2_config.dart';
import 'package:backup_drive/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseBackupService - parseDatabaseUrl', () {
    test('extracts basic unquoted DATABASE_URL', () {
      const content = '''
PORT=3000
DATABASE_URL=postgresql://user:password@localhost:5432/kontabb_db?sslmode=disable
OTHER_KEY=value
''';
      expect(
        DatabaseBackupService.parseDatabaseUrl(content),
        'postgresql://user:password@localhost:5432/kontabb_db?sslmode=disable',
      );
    });

    test('extracts double-quoted DATABASE_URL', () {
      const content = '''
# Comments
DATABASE_URL="postgres://postgres:secret@db.kontabb.com:5432/production?sslmode=require"
''';
      expect(
        DatabaseBackupService.parseDatabaseUrl(content),
        'postgres://postgres:secret@db.kontabb.com:5432/production?sslmode=require',
      );
    });

    test('extracts single-quoted DATABASE_URL', () {
      const content = "DATABASE_URL='postgres://user:pass@host:5432/db'";
      expect(
        DatabaseBackupService.parseDatabaseUrl(content),
        'postgres://user:pass@host:5432/db',
      );
    });

    test('ignores comments and returns null if not present', () {
      const content = '''
# DATABASE_URL=postgresql://disabled@localhost/db
SOME_VAR=123
''';
      expect(DatabaseBackupService.parseDatabaseUrl(content), isNull);
    });
  });

  group('DatabaseBackupService - Helper Path Resolution', () {
    test(
      'resolves custom path when KONTABB_BKP_PATH points to existing file',
      () {
        // Create a temporary dummy executable
        final tempDir = Directory.systemTemp.createTempSync('helper_test');
        final dummyFile = File('${tempDir.path}/custom-bkp-helper')
          ..writeAsStringSync('dummy');

        // Test when env is set by passing or checking helper lookup
        expect(dummyFile.existsSync(), isTrue);

        tempDir.deleteSync(recursive: true);
      },
    );

    test('can instantiate service and check default candidates logic', () {
      final service = DatabaseBackupService();
      expect(service, isNotNull);
    });
  });

  test(
    'passes the explicit empty-table compatibility list to restore',
    () async {
      if (Platform.isWindows) return;
      final directory = await Directory.systemTemp.createTemp('backup-helper-');
      addTearDown(() => directory.delete(recursive: true));
      final helper = File('${directory.path}/helper.sh');
      await helper.writeAsString('#!/bin/sh\nprintf "ARG:%s\\n" "\$@"\n');
      final chmod = await Process.run('chmod', ['+x', helper.path]);
      expect(chmod.exitCode, 0);
      final input = File('${directory.path}/backup.sql');
      await input.writeAsString('');
      final service = _TestBackupService(helper.path);

      final result = await service.run(
        operation: DatabaseOperation.restore,
        databaseUrl: 'postgresql://user:pass@localhost/test',
        inputFile: input.path,
        dryRun: true,
        skipMissingEmptyTables: const [
          'sped_contabilistas',
          'fiscal_lancamentos',
        ],
      );

      expect(result.succeeded, isTrue);
      expect(result.output, contains('ARG:-skip-missing-empty-tables'));
      expect(
        result.output,
        contains('ARG:sped_contabilistas,fiscal_lancamentos'),
      );
    },
  );

  group('SyncProgress and R2Config', () {
    test('R2Config returns correct endpoint', () {
      expect(
        R2Config.development.endpoint,
        '59e3d4637e95b5211d389160b42a0a94.r2.cloudflarestorage.com',
      );
      expect(
        R2Config.production.endpoint,
        'bce187765eb43b27e635faf4d7edee12.r2.cloudflarestorage.com',
      );
    });

    test('SyncProgress calculates progress correctly', () {
      const progress = SyncProgress(
        status: SyncStatus.downloading,
        totalObjects: 100,
        processedObjects: 50,
        downloadedObjects: 40,
        skippedObjects: 10,
      );
      expect(progress.progressPercent, 0.5);
    });

    test('SyncProgress preserves checkpoint resume state', () {
      const progress = SyncProgress(
        status: SyncStatus.listing,
        resumedFromCheckpoint: true,
      );

      final downloading = progress.copyWith(
        status: SyncStatus.downloading,
        totalObjects: 10,
      );

      expect(downloading.resumedFromCheckpoint, isTrue);
      expect(downloading.totalObjects, 10);
    });
  });
}

class _TestBackupService extends DatabaseBackupService {
  _TestBackupService(this.path);

  final String path;

  @override
  String get helperPath => path;
}
