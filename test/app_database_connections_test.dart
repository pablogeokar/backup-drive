import 'dart:io';

import 'package:backup_drive/services/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database sqlite;
  late AppDatabase repository;

  setUp(() async {
    sqlite = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await sqlite.execute('''
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
    await sqlite.execute('''
      CREATE UNIQUE INDEX database_connections_one_default
      ON database_connections(is_default) WHERE is_default = 1
    ''');
    repository = AppDatabase.forTesting(sqlite);
  });

  tearDown(() async => sqlite.close());

  test('saves distinct connections and switches the active database', () async {
    final first = await repository.saveDatabaseConnection(
      name: 'Origem',
      databaseUrl: 'postgresql://localhost/origem',
      schema: 'public',
    );
    final second = await repository.saveDatabaseConnection(
      name: 'Destino',
      databaseUrl: 'postgresql://localhost/destino',
      schema: 'teste',
    );

    expect((await repository.getDatabaseConnections()).length, 2);
    expect((await repository.getDefaultDatabaseConnection())?.id, first.id);

    await repository.setDefaultDatabaseConnection(second.id);
    expect((await repository.getDefaultDatabaseConnection())?.id, second.id);
    expect((await repository.getDefaultDatabaseConnection())?.schema, 'teste');

    await repository.saveDatabaseConnection(
      id: second.id,
      name: 'Destino revisado',
      databaseUrl: 'postgresql://localhost/destino2',
      schema: 'public',
    );
    final connections = await repository.getDatabaseConnections();
    expect(connections.length, 2);
    expect(connections.first.name, 'Destino revisado');
    expect(connections.last.databaseUrl, first.databaseUrl);
  });

  test(
    'deleting the active connection selects another saved profile',
    () async {
      final first = await repository.saveDatabaseConnection(
        name: 'A',
        databaseUrl: 'postgresql://localhost/a',
        schema: 'public',
      );
      final second = await repository.saveDatabaseConnection(
        name: 'B',
        databaseUrl: 'postgresql://localhost/b',
        schema: 'public',
      );

      await repository.deleteDatabaseConnection(first.id);
      expect((await repository.getDefaultDatabaseConnection())?.id, second.id);
      await repository.deleteDatabaseConnection(second.id);
      expect(await repository.getDefaultDatabaseConnection(), isNull);
    },
  );

  test(
    'imports previous profiles once and selects the previous default',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kontabb-import-test-',
      );
      final path = p.join(directory.path, 'settings.sqlite3');
      try {
        final previous = await databaseFactoryFfi.openDatabase(path);
        await previous.execute('''
        CREATE TABLE database_connections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          database_url TEXT NOT NULL,
          schema_name TEXT NOT NULL,
          is_default INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
        for (final (name, databaseUrl, isDefault) in [
          ('Teste', 'postgresql://localhost/teste', 0),
          ('Ativo', 'postgresql://localhost/ativo', 1),
        ]) {
          await previous.insert('database_connections', {
            'name': name,
            'database_url': databaseUrl,
            'schema_name': 'public',
            'is_default': isDefault,
            'created_at': '2026-01-01',
            'updated_at': '2026-01-01',
          });
        }
        await previous.close();

        expect(await repository.importDatabaseConnections(path), 2);
        expect(
          (await repository.getDefaultDatabaseConnection())?.name,
          'Ativo',
        );
        expect(await repository.importDatabaseConnections(path), 0);
        expect((await repository.getDatabaseConnections()).length, 2);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
