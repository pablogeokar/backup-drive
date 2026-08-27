import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late SyncService _syncService;
  SyncProgress _progress = const SyncProgress();
  bool _isInitialized = false;
  bool _connectionOk = false;
  bool _testingConnection = false;
  String _localPath = '';
  String _selectedEnv = 'development';

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initService();
  }

  Future<void> _initService() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final defaultPath = p.join(docsDir.path, 'KontabbBackup');

    setState(() {
      _localPath = defaultPath;
    });

    _createSyncService();
  }

  void _createSyncService() {
    final config = _selectedEnv == 'production'
        ? R2Config.production
        : R2Config.development;

    _syncService = SyncService(config: config, localBasePath: _localPath);

    _syncService.onProgressChanged = (progress) {
      if (mounted) {
        setState(() => _progress = progress);
      }
    };

    setState(() => _isInitialized = true);
  }

  Future<void> _testConnection() async {
    setState(() => _testingConnection = true);
    final ok = await _syncService.testConnection();
    if (!mounted) return;
    setState(() {
      _connectionOk = ok;
      _testingConnection = false;
    });
  }

  Future<void> _startSync() async {
    final dir = Directory(_localPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    await _syncService.sync();
  }

  void _cancelSync() {
    _syncService.cancelSync();
  }

  Future<void> _pickDirectory() async {
    // Garantir que o initialDirectory existe, caso contrário usar o parent
    // ou null para evitar exceção no Windows
    String? initialDir;
    if (_localPath.isNotEmpty) {
      var dir = Directory(_localPath);
      // Subir na hierarquia até encontrar um diretório existente
      while (!dir.existsSync() && dir.parent.path != dir.path) {
        dir = dir.parent;
      }
      if (dir.existsSync()) {
        initialDir = dir.path;
      }
    }

    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecione o diretório de backup',
      initialDirectory: initialDir,
      lockParentWindow: true,
    );

    if (result != null) {
      setState(() => _localPath = result);
      _createSyncService();
    }
  }

  bool get _isSyncing =>
      _progress.status == SyncStatus.listing ||
      _progress.status == SyncStatus.downloading;

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsivo: sidebar fixa em telas largas, colapsada em estreitas
          final isWide = constraints.maxWidth > 720;

          if (isWide) {
            return Row(
              children: [
                _buildSidebar(colorScheme),
                const VerticalDivider(width: 1),
                Expanded(child: _buildMainContent(colorScheme)),
              ],
            );
          }

          return Column(
            children: [
              _buildCompactHeader(colorScheme),
              Expanded(child: _buildMainContent(colorScheme)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar(ColorScheme colorScheme) {
    return Container(
      width: 260,
      color: colorScheme.surfaceContainer,
      child: Column(
        children: [
          // Logo / título
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_sync,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Backup Drive',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Ambiente
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildEnvSelector(colorScheme),
          ),
          const SizedBox(height: 24),

          // Status da conexão
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildConnectionStatus(colorScheme),
          ),

          const Spacer(),

          // Último sync
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildLastSync(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.cloud_sync,
                color: colorScheme.onPrimary,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Backup Drive',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            _buildConnectionChip(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionChip(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _connectionOk
            ? Colors.green.withAlpha(25)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _connectionOk
              ? Colors.green.withAlpha(80)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _connectionOk
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
            size: 14,
            color: _connectionOk ? Colors.green : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            _connectionOk ? 'Conectado' : 'Desconectado',
            style: TextStyle(
              fontSize: 11,
              color: _connectionOk
                  ? Colors.green
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AMBIENTE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _buildEnvOption(
          'development',
          'Desenvolvimento',
          'Bucket: teste',
          Icons.science_outlined,
          colorScheme,
        ),
        const SizedBox(height: 4),
        _buildEnvOption(
          'production',
          'Produção',
          'Bucket: documents',
          Icons.verified_outlined,
          colorScheme,
        ),
      ],
    );
  }

  Widget _buildEnvOption(
    String value,
    String title,
    String subtitle,
    IconData icon,
    ColorScheme colorScheme,
  ) {
    final isSelected = _selectedEnv == value;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _isSyncing
            ? null
            : () {
                setState(() => _selectedEnv = value);
                _createSyncService();
                setState(() => _connectionOk = false);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withAlpha(140)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withAlpha(80)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, size: 16, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONEXÃO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _connectionOk
                ? Colors.green.withAlpha(20)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _connectionOk
                  ? Colors.green.withAlpha(60)
                  : colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _connectionOk ? Icons.check_circle : Icons.cloud_off_outlined,
                size: 18,
                color: _connectionOk
                    ? Colors.green
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _connectionOk ? 'R2 conectado' : 'Não verificado',
                  style: TextStyle(
                    fontSize: 12,
                    color: _connectionOk
                        ? Colors.green.shade700
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: TextButton(
                  onPressed: _testingConnection ? null : _testConnection,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: _testingConnection
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Text('Testar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLastSync(ColorScheme colorScheme) {
    return FutureBuilder<DateTime?>(
      future: _isInitialized ? _syncService.getLastSyncTime() : null,
      builder: (context, snapshot) {
        final lastSync = snapshot.data;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lastSync != null
                      ? 'Sync: ${DateFormat('dd/MM/yy HH:mm').format(lastSync)}'
                      : 'Nenhum sync realizado',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainContent(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDirectorySection(colorScheme),
          const SizedBox(height: 28),
          _buildSyncSection(colorScheme),
          if (_progress.status != SyncStatus.idle ||
              _progress.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 28),
              child: _buildProgressCard(colorScheme),
            ),
        ],
      ),
    );
  }

  Widget _buildDirectorySection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Diretório de backup',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Escolha onde os arquivos do R2 serão salvos localmente.',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant.withAlpha(180),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(100),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _isSyncing ? null : _pickDirectory,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withAlpha(160),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.folder_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getDirectoryName(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _localPath,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Alterar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_localPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildDirectoryInfo(colorScheme),
          ),
      ],
    );
  }

  Widget _buildDirectoryInfo(ColorScheme colorScheme) {
    final dir = Directory(_localPath);
    final exists = dir.existsSync();

    return Row(
      children: [
        Icon(
          exists ? Icons.check_circle_outline : Icons.info_outline,
          size: 13,
          color: exists ? Colors.green : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          exists
              ? 'Diretório existente — pronto para sync'
              : 'Diretório será criado automaticamente',
          style: TextStyle(
            fontSize: 11,
            color: exists ? Colors.green : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSyncSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _isSyncing
            ? LinearGradient(
                colors: [
                  colorScheme.primaryContainer.withAlpha(60),
                  colorScheme.primaryContainer.withAlpha(30),
                ],
              )
            : null,
        color: _isSyncing ? null : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isSyncing
              ? colorScheme.primary.withAlpha(60)
              : colorScheme.outlineVariant.withAlpha(100),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isSyncing ? 'Sincronização em andamento' : 'Sincronizar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isSyncing
                      ? 'Baixando arquivos do bucket ${_selectedEnv == 'production' ? 'documents' : 'teste'}...'
                      : 'Baixar todos os objetos do bucket para a pasta local.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (_isSyncing)
            FilledButton.tonalIcon(
              onPressed: _cancelSync,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Parar'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.withAlpha(30),
                foregroundColor: Colors.red,
              ),
            )
          else
            FilledButton.icon(
              onPressed: _connectionOk ? _startSync : null,
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Iniciar'),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _progress.status == SyncStatus.error
              ? Colors.red.withAlpha(60)
              : _progress.status == SyncStatus.completed
              ? Colors.green.withAlpha(60)
              : colorScheme.outlineVariant.withAlpha(100),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header do progresso
          Row(
            children: [
              _buildProgressIcon(colorScheme),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusTitle(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _statusSubtitle(),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_progress.status == SyncStatus.downloading)
                Text(
                  '${(_progress.progressPercent * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),

          // Barra de progresso
          if (_progress.status == SyncStatus.downloading ||
              _progress.status == SyncStatus.listing) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress.status == SyncStatus.listing
                    ? null
                    : _progress.progressPercent,
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            if (_progress.currentFile.isNotEmpty)
              Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _progress.currentFile,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],

          // Estatísticas finais
          if (_progress.status == SyncStatus.completed) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatChip(
                  Icons.download_done,
                  '${_progress.downloadedObjects}',
                  'Baixados',
                  Colors.green,
                  colorScheme,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.skip_next_rounded,
                  '${_progress.skippedObjects}',
                  'Ignorados',
                  Colors.orange,
                  colorScheme,
                ),
                const SizedBox(width: 8),
                if (_progress.errorCount > 0)
                  _buildStatChip(
                    Icons.error_outline,
                    '${_progress.errorCount}',
                    'Erros',
                    Colors.red,
                    colorScheme,
                  ),
              ],
            ),
            if (_progress.errorCount > 0 && _progress.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Último erro: ${_progress.errorMessage}',
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],

          // Erro
          if (_progress.status == SyncStatus.error &&
              _progress.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _progress.errorMessage!,
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(
    IconData icon,
    String value,
    String label,
    Color color,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIcon(ColorScheme colorScheme) {
    switch (_progress.status) {
      case SyncStatus.listing:
      case SyncStatus.downloading:
        return SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: _progress.status == SyncStatus.listing
                ? null
                : _progress.progressPercent,
            color: colorScheme.primary,
          ),
        );
      case SyncStatus.completed:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.green),
        );
      case SyncStatus.error:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded, size: 16, color: Colors.red),
        );
      case SyncStatus.idle:
        return Icon(
          Icons.info_outline,
          size: 24,
          color: colorScheme.onSurfaceVariant,
        );
    }
  }

  String _getDirectoryName() {
    if (_localPath.isEmpty) return 'Nenhum diretório selecionado';
    return p.basename(_localPath);
  }

  String _statusTitle() {
    switch (_progress.status) {
      case SyncStatus.listing:
        return 'Listando objetos...';
      case SyncStatus.downloading:
        return '${_progress.processedObjects} de ${_progress.totalObjects} objetos';
      case SyncStatus.completed:
        return 'Sincronização concluída';
      case SyncStatus.error:
        return 'Falha na sincronização';
      case SyncStatus.idle:
        return _progress.errorMessage ?? 'Pronto';
    }
  }

  String _statusSubtitle() {
    switch (_progress.status) {
      case SyncStatus.listing:
        return 'Consultando bucket R2...';
      case SyncStatus.downloading:
        return 'Baixando: ${_progress.downloadedObjects} | Ignorados: ${_progress.skippedObjects}';
      case SyncStatus.completed:
        return 'Todos os arquivos foram sincronizados';
      case SyncStatus.error:
        return 'Ocorreu um erro durante o processo';
      case SyncStatus.idle:
        return '';
    }
  }
}
