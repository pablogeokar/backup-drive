import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SavedDatabaseConnection {
  const SavedDatabaseConnection({
    required this.id,
    required this.name,
    required this.databaseUrl,
    required this.schema,
  });

  final int id;
  final String name;
  final String databaseUrl;
  final String schema;

  factory SavedDatabaseConnection.fromMap(Map<String, Object?> row) =>
      SavedDatabaseConnection(
        id: row['id']! as int,
        name: row['name']! as String,
        databaseUrl: row['database_url']! as String,
        schema: row['schema_name']! as String,
      );
}

/// Fonte única das configurações locais do aplicativo.
///
/// O arquivo fica na pasta de suporte do usuário e nunca é incluído nos
/// backups. Credenciais são persistidas localmente, sem sincronização externa.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;
  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('AppDatabase ainda não foi inicializado.');
    }
    return database;
  }

  Future<void> initialize() async {
    if (_database != null) return;
    sqfliteFfiInit();
    final supportDirectory = await getApplicationSupportDirectory();
    final dataDirectory = Directory(
      p.join(supportDirectory.path, 'Kontabb Backup Drive'),
    );
    await dataDirectory.create(recursive: true);
    await _protectDataDirectory(dataDirectory.path);
    final databasePath = p.join(dataDirectory.path, 'settings.sqlite3');
    _database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE database_connections (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              database_url TEXT NOT NULL,
              schema_name TEXT NOT NULL DEFAULT 'public',
              is_default INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE UNIQUE INDEX database_connections_one_default
            ON database_connections(is_default)
            WHERE is_default = 1
          ''');
        },
      ),
    );
    await _protectDatabaseFile(databasePath);
    await _migrateLegacyPreferences();
  }

  Future<void> _protectDatabaseFile(String databasePath) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['600', databasePath], runInShell: false);
    } catch (_) {
      // Permissões padrão do diretório de suporte ainda protegem o arquivo.
    }
  }

  Future<void> _protectDataDirectory(String directoryPath) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['700', directoryPath], runInShell: false);
    } catch (_) {
      // O sistema mantém as permissões padrão se chmod não estiver disponível.
    }
  }

  Future<void> _migrateLegacyPreferences() async {
    if (await getBool('legacy_preferences_migrated') ?? false) return;
    final preferences = await SharedPreferences.getInstance();
    const stringKeys = [
      'backup_path',
      'selected_env',
      'last_sync_time',
      'database_output_path',
      'database_input_path',
      'database_schema',
    ];
    const boolKeys = ['database_dry_run', 'database_no_truncate'];

    await _db.transaction((txn) async {
      for (final key in stringKeys) {
        final value = preferences.getString(key);
        if (value != null) await _setString(txn, key, value);
      }
      for (final key in boolKeys) {
        final value = preferences.getBool(key);
        if (value != null) await _setString(txn, key, jsonEncode(value));
      }

      final envPath = preferences.getString('database_env_path');
      if (envPath != null && envPath.isNotEmpty) {
        final envFile = File(envPath);
        try {
          if (await envFile.exists()) {
            final databaseUrl = _parseDatabaseUrl(await envFile.readAsString());
            if (databaseUrl != null && databaseUrl.isNotEmpty) {
              final now = DateTime.now().toIso8601String();
              await txn.insert('database_connections', {
                'name': 'Conexão migrada',
                'database_url': databaseUrl,
                'schema_name':
                    preferences.getString('database_schema') ?? 'public',
                'is_default': 1,
                'created_at': now,
                'updated_at': now,
              });
            }
          }
        } on FileSystemException {
          // O sandbox pode bloquear o arquivo antigo. Nesse caso, o app abre
          // normalmente e oferece a importação manual ou o cadastro direto.
        }
      }
      await _setString(txn, 'legacy_preferences_migrated', jsonEncode(true));
    });
  }

  static String? _parseDatabaseUrl(String contents) {
    for (final raw in const LineSplitter().convert(contents)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(r'^DATABASE_URL\s*=\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      var value = match.group(1)!.trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
    return null;
  }

  Future<String?> getString(String key) async {
    final rows = await _db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setString(String key, String? value) async {
    if (value == null) {
      await _db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await _setString(_db, key, value);
  }

  Future<void> _setString(
    DatabaseExecutor executor,
    String key,
    String value,
  ) async {
    await executor.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool?> getBool(String key) async {
    final value = await getString(key);
    return value == null ? null : jsonDecode(value) as bool;
  }

  Future<void> setBool(String key, bool value) =>
      setString(key, jsonEncode(value));

  Future<SavedDatabaseConnection?> getDefaultDatabaseConnection() async {
    final rows = await _db.query(
      'database_connections',
      where: 'is_default = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : SavedDatabaseConnection.fromMap(rows.first);
  }

  Future<SavedDatabaseConnection> saveDefaultDatabaseConnection({
    required String name,
    required String databaseUrl,
    required String schema,
  }) async {
    return _db.transaction((txn) async {
      final existing = await txn.query(
        'database_connections',
        columns: ['id', 'created_at'],
        where: 'is_default = 1',
        limit: 1,
      );
      final now = DateTime.now().toIso8601String();
      late final int id;
      if (existing.isEmpty) {
        id = await txn.insert('database_connections', {
          'name': name,
          'database_url': databaseUrl,
          'schema_name': schema,
          'is_default': 1,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        id = existing.first['id']! as int;
        await txn.update(
          'database_connections',
          {
            'name': name,
            'database_url': databaseUrl,
            'schema_name': schema,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return SavedDatabaseConnection(
        id: id,
        name: name,
        databaseUrl: databaseUrl,
        schema: schema,
      );
    });
  }
}
