import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/r2_config.dart';
import '../services/sync_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late SyncService _syncService;
  SyncProgress _progress = const SyncProgress();
  bool _isInitialized = false;
  bool _connectionOk = false;
  String _localPath = '';
  String _selectedEnv = 'development';

  // Controle para escolha de diretório customizado
  final TextEditingController _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final defaultPath = p.join(docsDir.path, 'KontabbBackup');

    setState(() {
      _localPath = defaultPath;
      _pathController.text = defaultPath;
    });

    _createSyncService();
  }

  void _createSyncService() {
    final config = _selectedEnv == 'production'
        ? R2Config.production
        : R2Config.development;

    _syncService = SyncService(
      config: config,
      localBasePath: _localPath,
    );

    _syncService.onProgressChanged = (progress) {
      if (mounted) {
        setState(() => _progress = progress);
      }
    };

    setState(() => _isInitialized = true);
  }

  Future<void> _testConnection() async {
    final ok = await _syncService.testConnection();
    setState(() => _connectionOk = ok);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Conexão com R2 estabelecida com sucesso!'
              : 'Falha ao conectar com o R2. Verifique as credenciais.'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _startSync() async {
    // Garantir que o diretório existe
    final dir = Directory(_localPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    await _syncService.sync();
  }

  void _cancelSync() {
    _syncService.cancelSync();
  }

  void _updatePath() {
    final newPath = _pathController.text.trim();
    if (newPath.isNotEmpty) {
      setState(() => _localPath = newPath);
      _createSyncService();
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontabb Backup Drive'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Indicador de conexão
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _connectionOk ? Icons.cloud_done : Icons.cloud_off,
              color: _connectionOk ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildConfigSection(),
            const SizedBox(height: 24),
            _buildPathSection(),
            const SizedBox(height: 24),
            _buildActionsSection(),
            const SizedBox(height: 24),
            _buildProgressSection(),
            const Spacer(),
            _buildStatsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuração',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Ambiente: '),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'development',
                      label: Text('Desenvolvimento'),
                      icon: Icon(Icons.developer_mode),
                    ),
                    ButtonSegment(
                      value: 'production',
                      label: Text('Produção'),
                      icon: Icon(Icons.cloud),
                    ),
                  ],
                  selected: {_selectedEnv},
                  onSelectionChanged: (value) {
                    setState(() => _selectedEnv = value.first);
                    _createSyncService();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Bucket: ${_selectedEnv == 'production' ? 'documents' : 'teste'}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diretório de Backup',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Caminho local',
                      prefixIcon: Icon(Icons.folder),
                    ),
                    onSubmitted: (_) => _updatePath(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _updatePath,
                  icon: const Icon(Icons.check),
                  label: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection() {
    final isSyncing = _progress.status == SyncStatus.listing ||
        _progress.status == SyncStatus.downloading;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ElevatedButton.icon(
              onPressed: isSyncing ? null : _testConnection,
              icon: const Icon(Icons.wifi_find),
              label: const Text('Testar Conexão'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: isSyncing ? null : _startSync,
              icon: const Icon(Icons.sync),
              label: const Text('Iniciar Sync'),
            ),
            const SizedBox(width: 12),
            if (isSyncing)
              OutlinedButton.icon(
                onPressed: _cancelSync,
                icon: const Icon(Icons.stop),
                label: const Text('Cancelar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    if (_progress.status == SyncStatus.idle &&
        _progress.errorMessage == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 8),
                Text(
                  _statusText(),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_progress.status == SyncStatus.downloading ||
                _progress.status == SyncStatus.listing)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _progress.status == SyncStatus.listing
                        ? null
                        : _progress.progressPercent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_progress.processedObjects} / ${_progress.totalObjects} objetos processados',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  if (_progress.currentFile.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _progress.currentFile,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            if (_progress.status == SyncStatus.completed)
              Text(
                'Baixados: ${_progress.downloadedObjects} | '
                'Ignorados: ${_progress.skippedObjects} | '
                'Erros: ${_progress.errorCount}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            if (_progress.status == SyncStatus.error &&
                _progress.errorMessage != null)
              Text(
                _progress.errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return FutureBuilder<DateTime?>(
      future: _isInitialized ? _syncService.getLastSyncTime() : null,
      builder: (context, snapshot) {
        final lastSync = snapshot.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  lastSync != null
                      ? 'Último sync: ${DateFormat('dd/MM/yyyy HH:mm').format(lastSync)}'
                      : 'Nenhuma sincronização realizada ainda.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon() {
    switch (_progress.status) {
      case SyncStatus.listing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncStatus.downloading:
        return const Icon(Icons.downloading, color: Colors.blue);
      case SyncStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case SyncStatus.error:
        return const Icon(Icons.error, color: Colors.red);
      case SyncStatus.idle:
        return const Icon(Icons.pause_circle, color: Colors.grey);
    }
  }

  String _statusText() {
    switch (_progress.status) {
      case SyncStatus.listing:
        return 'Listando objetos no bucket...';
      case SyncStatus.downloading:
        return 'Baixando arquivos...';
      case SyncStatus.completed:
        return 'Sincronização concluída!';
      case SyncStatus.error:
        return 'Erro durante sincronização';
      case SyncStatus.idle:
        return _progress.errorMessage ?? 'Pronto';
    }
  }
}
