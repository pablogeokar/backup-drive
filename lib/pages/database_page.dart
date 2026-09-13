import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/database_backup_service.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key});
  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  final _service = DatabaseBackupService();
  final _env = TextEditingController();
  final _schema = TextEditingController(text: 'public');
  String? _output;
  String? _input;
  String _log = '';
  bool _busy = false;
  bool _dryRun = true;
  bool _noTruncate = false;

  Future<void> _pickEnv() async {
    final r = await FilePicker.pickFiles(type: FileType.any);
    if (r?.files.single.path != null) {
      setState(() => _env.text = r!.files.single.path!);
    }
  }

  Future<void> _pickOutput() async {
    final r = await FilePicker.saveFile(
      fileName: 'backup.sql.gz',
      type: FileType.any,
    );
    if (r != null) {
      setState(() => _output = r);
    }
  }

  Future<void> _pickInput() async {
    final r = await FilePicker.pickFiles(type: FileType.any);
    if (r?.files.single.path != null) {
      setState(() => _input = r!.files.single.path!);
    }
  }

  Future<void> _run(DatabaseOperation op) async {
    if (_env.text.trim().isEmpty) {
      return _message('Selecione o arquivo .env do banco.');
    }
    if (op == DatabaseOperation.restore && _input == null) {
      return _message('Selecione o arquivo de backup.');
    }
    if (op == DatabaseOperation.backup && _output == null) {
      return _message('Escolha o arquivo de saída.');
    }
    if (op == DatabaseOperation.restore && !_dryRun) {
      final ok = await _confirmRestore();
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _log = '';
    });
    final result = await _service.run(
      operation: op,
      envFile: _env.text.trim(),
      outputFile: _output,
      inputFile: _input,
      dryRun: _dryRun,
      noTruncate: _noTruncate,
      schema: _schema.text.trim().isEmpty ? 'public' : _schema.text.trim(),
      onLine: (line) {
        if (mounted) setState(() => _log += '$line\n');
      },
    );
    if (mounted) {
      setState(() => _busy = false);
      _message(
        result.succeeded
            ? 'Operação concluída.'
            : 'Operação falhou (código ${result.exitCode}).',
      );
    }
  }

  Future<bool> _confirmRestore() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Confirmar restauração'),
          content: const Text(
            'A restauração pode truncar tabelas e substituir dados no banco indicado pelo .env. Confirme somente após validar o destino.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      ) ??
      false;
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  void dispose() {
    _env.dispose();
    _schema.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Backup e restauração PostgreSQL'),
      actions: [
        if (_busy)
          IconButton(
            onPressed: _service.cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Interromper',
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Banco de dados',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'O executável PostgreSQL é embarcado no aplicativo. As credenciais permanecem no arquivo .env selecionado.',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _env,
                decoration: const InputDecoration(
                  labelText: 'Arquivo .env',
                  prefixIcon: Icon(Icons.key_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickEnv,
              icon: const Icon(Icons.folder_open),
              label: const Text('Selecionar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _schema,
          decoration: const InputDecoration(
            labelText: 'Esquema',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pickOutput,
              icon: const Icon(Icons.save_alt),
              label: const Text('Escolher saída'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(DatabaseOperation.backup),
              icon: const Icon(Icons.backup),
              label: const Text('Backup'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickInput,
              icon: const Icon(Icons.file_open),
              label: Text(
                _input == null ? 'Selecionar backup' : 'Backup selecionado',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(DatabaseOperation.restore),
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(DatabaseOperation.validate),
              icon: const Icon(Icons.verified),
              label: const Text('Validar integridade'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _dryRun,
          onChanged: _busy ? null : (v) => setState(() => _dryRun = v),
          title: const Text('Restore em modo simulação (dry-run)'),
          subtitle: const Text(
            'Executa e valida dentro de uma transação com rollback.',
          ),
        ),
        SwitchListTile(
          value: _noTruncate,
          onChanged: _busy ? null : (v) => setState(() => _noTruncate = v),
          title: const Text('Não truncar tabelas antes do restore'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Log da operação',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        Container(
          height: 280,
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(_log.isEmpty ? 'Aguardando operação…' : _log),
          ),
        ),
      ],
    ),
  );
}
