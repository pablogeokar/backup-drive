import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/app_database.dart';
import '../services/database_backup_service.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key});

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  static const _bookmarkChannel = MethodChannel(
    'backup_drive/security_scoped_bookmarks',
  );
  static const _envPickerChannel = MethodChannel('backup_drive/env_picker');
  final _service = DatabaseBackupService();
  final _formKey = GlobalKey<FormState>();
  final _connectionName = TextEditingController(text: 'PostgreSQL principal');
  final _databaseUrl = TextEditingController();
  final _schema = TextEditingController(text: 'public');

  String? _outputDirectory;
  String? _input;
  String _log = '';
  bool _loading = true;
  bool _busy = false;
  bool _dryRun = true;
  bool _noTruncate = false;
  bool _hideDatabaseUrl = true;
  bool _connectionSaved = false;
  bool _showConnectionForm = true;

  @override
  void initState() {
    super.initState();
    _databaseUrl.addListener(_markConnectionAsChanged);
    _connectionName.addListener(_markConnectionAsChanged);
    _schema.addListener(_markConnectionAsChanged);
    _loadPreferences();
  }

  void _markConnectionAsChanged() {
    if (_loading || !_connectionSaved || !mounted) return;
    setState(() => _connectionSaved = false);
  }

  bool _isTemporaryPath(String? path) {
    if (path == null) return false;
    final lower = path.toLowerCase();
    return lower.contains('/tmp/') ||
        lower.contains(r'\temp\') ||
        lower.contains(r'\tmp\') ||
        lower.contains('/var/folders/');
  }

  Future<void> _loadPreferences() async {
    final database = AppDatabase.instance;
    final connection = await database.getDefaultDatabaseConnection();
    var outputDirectory = await database.getString('database_output_directory');
    var outputBookmark = await database.getString(
      'database_output_directory_bookmark',
    );
    final legacyOutput = await database.getString('database_output_path');
    if (outputDirectory == null && legacyOutput != null) {
      outputDirectory = p.dirname(legacyOutput);
    }
    final documents = await getApplicationDocumentsDirectory();
    final defaultOutput = p.join(documents.path, 'KontabbBackup', 'PostgreSQL');
    if (Platform.isMacOS && outputBookmark != null) {
      final restored = await _restoreBookmark(outputBookmark);
      outputDirectory = restored?.path ?? defaultOutput;
      outputBookmark = restored?.bookmark;
    } else if (Platform.isMacOS &&
        outputDirectory != null &&
        !p.isWithin(documents.path, outputDirectory)) {
      // Caminhos externos migrados não possuem autorização persistente.
      outputDirectory = defaultOutput;
    }
    if (outputDirectory == null || _isTemporaryPath(outputDirectory)) {
      outputDirectory = defaultOutput;
    }
    var savedInput = await database.getString('database_input_path');
    final inputBookmark = await database.getString(
      'database_input_path_bookmark',
    );
    if (Platform.isMacOS) {
      final restoredInput = inputBookmark == null
          ? null
          : await _restoreBookmark(inputBookmark);
      savedInput = restoredInput?.path;
      if (restoredInput != null) {
        await database.setString(
          'database_input_path_bookmark',
          restoredInput.bookmark,
        );
      }
    }
    await database.setString('database_output_directory', outputDirectory);
    await database.setString(
      'database_output_directory_bookmark',
      outputBookmark,
    );
    final dryRun = await database.getBool('database_dry_run');
    final noTruncate = await database.getBool('database_no_truncate');
    if (!mounted) return;
    setState(() {
      if (connection != null) {
        _connectionName.text = connection.name;
        _databaseUrl.text = connection.databaseUrl;
        _schema.text = connection.schema;
      }
      _outputDirectory = outputDirectory;
      _input = _isTemporaryPath(savedInput) ? null : savedInput;
      _dryRun = dryRun ?? true;
      _noTruncate = noTruncate ?? false;
      _connectionSaved = connection != null;
      _showConnectionForm = connection == null;
      _loading = false;
    });
  }

  String? _validateDatabaseUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe a URL de conexão.';
    if (!text.startsWith('postgres://') && !text.startsWith('postgresql://')) {
      return 'Use uma URL iniciada por postgres:// ou postgresql://.';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty || uri.path.length <= 1) {
      return 'Informe host e nome do banco na URL.';
    }
    return null;
  }

  Future<bool> _saveConnection({bool showMessage = true}) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _showConnectionForm = true);
      return false;
    }
    final schema = _schema.text.trim().isEmpty ? 'public' : _schema.text.trim();
    await AppDatabase.instance.saveDefaultDatabaseConnection(
      name: _connectionName.text.trim().isEmpty
          ? 'PostgreSQL principal'
          : _connectionName.text.trim(),
      databaseUrl: _databaseUrl.text.trim(),
      schema: schema,
    );
    if (!mounted) return true;
    setState(() {
      _connectionSaved = true;
      _showConnectionForm = false;
    });
    if (showMessage) _message('Conexão salva neste computador.');
    return true;
  }

  Future<void> _importEnv() async {
    String? path;
    if (Platform.isMacOS) {
      path = await _envPickerChannel.invokeMethod<String>('pickEnv');
    } else {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        dialogTitle: 'Importar DATABASE_URL de um arquivo .env',
        lockParentWindow: true,
      );
      path = result?.files.single.path;
    }
    if (path == null) return;
    final databaseUrl = DatabaseBackupService.parseDatabaseUrl(
      await File(path).readAsString(),
    );
    if (databaseUrl == null || databaseUrl.isEmpty) {
      return _message('O arquivo selecionado não contém DATABASE_URL.');
    }
    _databaseUrl.text = databaseUrl;
    final saved = await _saveConnection(showMessage: false);
    if (saved && mounted) {
      _message(
        'Dados importados. Você não precisará selecionar o .env novamente.',
      );
    }
  }

  Future<void> _pickOutputDirectory() async {
    if (Platform.isMacOS) {
      final selection = await _pickScoped('pickDirectory');
      if (selection == null) return;
      setState(() => _outputDirectory = selection.path);
      await AppDatabase.instance.setString(
        'database_output_directory',
        selection.path,
      );
      await AppDatabase.instance.setString(
        'database_output_directory_bookmark',
        selection.bookmark,
      );
      return;
    }
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecione a pasta dos backups PostgreSQL',
      initialDirectory: _existingParent(_outputDirectory),
      lockParentWindow: true,
    );
    if (path == null) return;
    setState(() => _outputDirectory = path);
    await AppDatabase.instance.setString('database_output_directory', path);
  }

  String? _existingParent(String? path) {
    if (path == null) return null;
    var directory = Directory(path);
    while (!directory.existsSync() && directory.parent.path != directory.path) {
      directory = directory.parent;
    }
    return directory.existsSync() ? directory.path : null;
  }

  Future<void> _pickInput() async {
    if (Platform.isMacOS) {
      final selection = await _pickScoped('pickBackupFile');
      if (selection == null) return;
      setState(() => _input = selection.path);
      await AppDatabase.instance.setString(
        'database_input_path',
        selection.path,
      );
      await AppDatabase.instance.setString(
        'database_input_path_bookmark',
        selection.bookmark,
      );
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gz', 'sql'],
      dialogTitle: 'Selecione um backup PostgreSQL',
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _input = path);
    await AppDatabase.instance.setString('database_input_path', path);
  }

  Future<_ScopedSelection?> _pickScoped(String method) async {
    final value = await _bookmarkChannel.invokeMapMethod<String, dynamic>(
      method,
    );
    return _ScopedSelection.fromMap(value);
  }

  Future<_ScopedSelection?> _restoreBookmark(String bookmark) async {
    try {
      final value = await _bookmarkChannel.invokeMapMethod<String, dynamic>(
        'restore',
        {'bookmark': bookmark},
      );
      return _ScopedSelection.fromMap(value);
    } on PlatformException {
      return null;
    }
  }

  String _newBackupPath() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final timestamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return p.join(_outputDirectory!, 'kontabb-$timestamp.sql.gz');
  }

  Future<void> _saveOperationPreferences() async {
    final database = AppDatabase.instance;
    await Future.wait([
      database.setString('database_output_directory', _outputDirectory),
      database.setString('database_input_path', _input),
      database.setBool('database_dry_run', _dryRun),
      database.setBool('database_no_truncate', _noTruncate),
    ]);
  }

  Future<void> _run(DatabaseOperation operation) async {
    if (!await _saveConnection(showMessage: false)) return;
    if (operation == DatabaseOperation.restore && _input == null) {
      return _message('Selecione o backup que será restaurado.');
    }
    if (operation == DatabaseOperation.restore && !_dryRun) {
      final confirmed = await _confirmRestore();
      if (!confirmed) return;
    }
    final outputFile = operation == DatabaseOperation.backup
        ? _newBackupPath()
        : null;
    if (outputFile != null) {
      await Directory(p.dirname(outputFile)).create(recursive: true);
    }
    setState(() {
      _busy = true;
      _log = '';
    });
    await _saveOperationPreferences();
    try {
      final result = await _service.run(
        operation: operation,
        databaseUrl: _databaseUrl.text.trim(),
        outputFile: outputFile,
        inputFile: _input,
        dryRun: _dryRun,
        noTruncate: _noTruncate,
        schema: _schema.text.trim().isEmpty ? 'public' : _schema.text.trim(),
        onLine: (line) {
          if (mounted) setState(() => _log += '$line\n');
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _message(
        result.succeeded
            ? operation == DatabaseOperation.backup
                  ? 'Backup salvo em $outputFile'
                  : 'Operação concluída.'
            : 'Operação falhou (código ${result.exitCode}).',
      );
    } on ProcessException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _log = error.message;
      });
      _message(error.message);
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _log = error.message;
      });
      _message(
        Platform.isMacOS && operation == DatabaseOperation.backup
            ? 'O macOS bloqueou a pasta de destino. Selecione a pasta novamente para autorizar o acesso.'
            : 'Não foi possível acessar o arquivo: ${error.message}',
      );
    }
  }

  Future<bool> _confirmRestore() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Confirmar restauração'),
          content: Text(
            'A restauração pode substituir dados de "${_connectionName.text}". '
            'Confirme somente após validar o destino.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restaurar agora'),
            ),
          ],
        ),
      ) ??
      false;

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _databaseUrl.removeListener(_markConnectionAsChanged);
    _connectionName.removeListener(_markConnectionAsChanged);
    _schema.removeListener(_markConnectionAsChanged);
    _databaseUrl.dispose();
    _connectionName.dispose();
    _schema.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PostgreSQL'),
        actions: [
          if (_busy)
            IconButton(
              onPressed: _service.cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Interromper operação',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Text(
                  'Backup e restauração',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'A conexão e suas preferências ficam salvas localmente. '
                  'Depois da configuração inicial, basta escolher a operação.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                _buildConnectionCard(colorScheme),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final backup = _buildBackupCard(colorScheme);
                    final restore = _buildRestoreCard(colorScheme);
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: backup),
                              const SizedBox(width: 16),
                              Expanded(child: restore),
                            ],
                          )
                        : Column(
                            children: [
                              backup,
                              const SizedBox(height: 16),
                              restore,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),
                _buildLog(colorScheme),
              ],
            ),
    );
  }

  Widget _buildConnectionCard(ColorScheme colorScheme) {
    final configured = _databaseUrl.text.trim().isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: configured
                  ? colorScheme.primaryContainer
                  : colorScheme.errorContainer,
              child: Icon(
                configured ? Icons.dns_outlined : Icons.link_off_outlined,
                color: configured
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onErrorContainer,
              ),
            ),
            title: Text(
              configured ? _connectionName.text : 'Configure sua conexão',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              configured
                  ? '${Uri.tryParse(_databaseUrl.text)?.host ?? 'PostgreSQL'} • esquema ${_schema.text}'
                  : 'Informe os dados uma única vez.',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_connectionSaved)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: Icon(Icons.check, size: 16),
                      label: Text('Salva'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _showConnectionForm = !_showConnectionForm,
                        ),
                  icon: Icon(
                    _showConnectionForm
                        ? Icons.expand_less
                        : Icons.edit_outlined,
                  ),
                  tooltip: _showConnectionForm
                      ? 'Recolher configuração'
                      : 'Editar conexão',
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _showConnectionForm
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _connectionName,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Nome da conexão',
                        prefixIcon: Icon(Icons.label_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _databaseUrl,
                      enabled: !_busy,
                      obscureText: _hideDatabaseUrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      validator: _validateDatabaseUrl,
                      decoration: InputDecoration(
                        labelText: 'URL do PostgreSQL',
                        hintText: 'postgresql://usuario:senha@host:5432/banco',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _hideDatabaseUrl = !_hideDatabaseUrl,
                          ),
                          icon: Icon(
                            _hideDatabaseUrl
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _hideDatabaseUrl
                              ? 'Mostrar URL'
                              : 'Ocultar URL',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _schema,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Esquema',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _importEnv,
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('Importar .env'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _busy ? null : _saveConnection,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Salvar conexão'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCard(ColorScheme colorScheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.backup_outlined, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text('Criar backup', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'O nome do arquivo é gerado automaticamente com data e hora.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Pasta de destino'),
            subtitle: Text(_outputDirectory ?? 'Não selecionada'),
            trailing: IconButton(
              onPressed: _busy ? null : _pickOutputDirectory,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Alterar pasta',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _run(DatabaseOperation.backup),
              icon: const Icon(Icons.backup),
              label: const Text('Fazer backup agora'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _run(DatabaseOperation.validate),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Validar conexão e integridade'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildRestoreCard(ColorScheme colorScheme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.restore_outlined, color: colorScheme.primary),
          const SizedBox(height: 12),
          Text('Restaurar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Selecione um arquivo .sql ou .sql.gz e revise as opções.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickInput,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(
              _input == null ? 'Selecionar backup' : p.basename(_input!),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _dryRun,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() => _dryRun = value ?? true);
                    _saveOperationPreferences();
                  },
            title: const Text('Simular primeiro'),
            subtitle: const Text('Valida em uma transação com rollback.'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _noTruncate,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() => _noTruncate = value ?? false);
                    _saveOperationPreferences();
                  },
            title: const Text('Não truncar tabelas'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(DatabaseOperation.restore),
              icon: const Icon(Icons.restore),
              label: Text(_dryRun ? 'Simular restauração' : 'Restaurar agora'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildLog(ColorScheme colorScheme) => Card(
    child: ExpansionTile(
      initiallyExpanded: _log.isNotEmpty,
      leading: const Icon(Icons.terminal_outlined),
      title: const Text('Log da operação'),
      subtitle: Text(_busy ? 'Operação em andamento…' : 'Detalhes técnicos'),
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 140, maxHeight: 280),
          padding: const EdgeInsets.all(16),
          color: colorScheme.surfaceContainerHighest,
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              _log.isEmpty ? 'Nenhuma operação executada nesta sessão.' : _log,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScopedSelection {
  const _ScopedSelection({required this.path, required this.bookmark});

  final String path;
  final String bookmark;

  static _ScopedSelection? fromMap(Map<String, dynamic>? value) {
    final path = value?['path'] as String?;
    final bookmark = value?['bookmark'] as String?;
    if (path == null || bookmark == null) return null;
    return _ScopedSelection(path: path, bookmark: bookmark);
  }
}
