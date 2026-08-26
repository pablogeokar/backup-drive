import 'dart:io';

import 'package:minio/models.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'r2_client.dart';
import 'r2_config.dart';

/// Status de uma operação de sincronização.
enum SyncStatus { idle, listing, downloading, completed, error }

/// Informações de progresso da sincronização.
class SyncProgress {
  final SyncStatus status;
  final int totalObjects;
  final int processedObjects;
  final int downloadedObjects;
  final int skippedObjects;
  final int errorCount;
  final String currentFile;
  final String? errorMessage;
  final DateTime? lastSyncTime;

  const SyncProgress({
    this.status = SyncStatus.idle,
    this.totalObjects = 0,
    this.processedObjects = 0,
    this.downloadedObjects = 0,
    this.skippedObjects = 0,
    this.errorCount = 0,
    this.currentFile = '',
    this.errorMessage,
    this.lastSyncTime,
  });

  double get progressPercent =>
      totalObjects > 0 ? processedObjects / totalObjects : 0.0;

  SyncProgress copyWith({
    SyncStatus? status,
    int? totalObjects,
    int? processedObjects,
    int? downloadedObjects,
    int? skippedObjects,
    int? errorCount,
    String? currentFile,
    String? errorMessage,
    DateTime? lastSyncTime,
  }) {
    return SyncProgress(
      status: status ?? this.status,
      totalObjects: totalObjects ?? this.totalObjects,
      processedObjects: processedObjects ?? this.processedObjects,
      downloadedObjects: downloadedObjects ?? this.downloadedObjects,
      skippedObjects: skippedObjects ?? this.skippedObjects,
      errorCount: errorCount ?? this.errorCount,
      currentFile: currentFile ?? this.currentFile,
      errorMessage: errorMessage ?? this.errorMessage,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// Serviço principal de sincronização R2 → disco local.
class SyncService {
  final R2Client _client;
  final String _localBasePath;

  SyncProgress _progress = const SyncProgress();
  SyncProgress get progress => _progress;

  /// Callback para notificar mudanças no progresso.
  void Function(SyncProgress)? onProgressChanged;

  /// Flag para cancelar a operação em andamento.
  bool _cancelRequested = false;

  SyncService({
    required R2Config config,
    required String localBasePath,
  })  : _client = R2Client(config: config),
        _localBasePath = localBasePath;

  /// Caminho base onde os arquivos são salvos localmente.
  String get localBasePath => _localBasePath;

  /// Testa a conexão com o R2.
  Future<bool> testConnection() => _client.testConnection();

  /// Solicita cancelamento da sync em andamento.
  void cancelSync() {
    _cancelRequested = true;
  }

  /// Executa a sincronização completa (incremental).
  ///
  /// Para cada objeto no bucket:
  /// 1. Verifica se já existe localmente.
  /// 2. Se existe, compara o tamanho e data de modificação.
  /// 3. Se diferente ou não existe, faz download.
  Future<void> sync() async {
    _cancelRequested = false;
    _progress = const SyncProgress(status: SyncStatus.listing);
    _notifyProgress();

    try {
      // Fase 1: Listar todos os objetos
      final objects = <Object>[];
      await for (final obj in _client.listAllObjects()) {
        if (_cancelRequested) {
          _progress = _progress.copyWith(
            status: SyncStatus.idle,
            errorMessage: 'Sync cancelado pelo usuário.',
          );
          _notifyProgress();
          return;
        }
        objects.add(obj);
      }

      _progress = _progress.copyWith(
        status: SyncStatus.downloading,
        totalObjects: objects.length,
      );
      _notifyProgress();

      // Fase 2: Download incremental
      int downloaded = 0;
      int skipped = 0;
      int errors = 0;

      for (final obj in objects) {
        if (_cancelRequested) {
          _progress = _progress.copyWith(
            status: SyncStatus.idle,
            errorMessage: 'Sync cancelado pelo usuário.',
          );
          _notifyProgress();
          return;
        }

        final key = obj.key ?? '';
        if (key.isEmpty || key.endsWith('/')) {
          // Ignorar "pastas" vazias
          skipped++;
          _progress = _progress.copyWith(
            processedObjects: downloaded + skipped + errors,
            skippedObjects: skipped,
          );
          _notifyProgress();
          continue;
        }

        _progress = _progress.copyWith(currentFile: key);
        _notifyProgress();

        try {
          final needsDownload = await _shouldDownload(key, obj);

          if (needsDownload) {
            await _downloadObject(key);
            downloaded++;
          } else {
            skipped++;
          }
        } catch (e) {
          errors++;
        }

        _progress = _progress.copyWith(
          processedObjects: downloaded + skipped + errors,
          downloadedObjects: downloaded,
          skippedObjects: skipped,
          errorCount: errors,
        );
        _notifyProgress();
      }

      // Salvar timestamp do último sync
      await _saveLastSyncTime();

      _progress = _progress.copyWith(
        status: SyncStatus.completed,
        currentFile: '',
        lastSyncTime: DateTime.now(),
      );
      _notifyProgress();
    } catch (e) {
      _progress = _progress.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
      _notifyProgress();
    }
  }

  /// Determina se um objeto precisa ser baixado.
  ///
  /// Compara tamanho do arquivo local com o tamanho remoto.
  /// Se o arquivo local não existe ou tem tamanho diferente, precisa baixar.
  Future<bool> _shouldDownload(String key, Object remoteObj) async {
    final localPath = p.join(_localBasePath, key);
    final localFile = File(localPath);

    if (!localFile.existsSync()) {
      return true;
    }

    final localSize = localFile.lengthSync();
    final remoteSize = remoteObj.size ?? 0;

    // Se o tamanho difere, precisa re-baixar
    if (localSize != remoteSize) {
      return true;
    }

    // Se tamanho é igual, verificar data de modificação
    final localModified = localFile.lastModifiedSync();
    final remoteModified = remoteObj.lastModified;

    if (remoteModified != null && remoteModified.isAfter(localModified)) {
      return true;
    }

    return false;
  }

  /// Faz download de um objeto para o disco local.
  Future<void> _downloadObject(String key) async {
    final localPath = p.join(_localBasePath, key);
    final localFile = File(localPath);

    // Garantir que o diretório pai existe
    final dir = localFile.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Usar fGetObject para download direto ao arquivo
    await _client.downloadToFile(key, localPath);
  }

  /// Salva o timestamp da última sincronização.
  Future<void> _saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'last_sync_time',
      DateTime.now().toIso8601String(),
    );
  }

  /// Carrega o timestamp da última sincronização.
  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('last_sync_time');
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  void _notifyProgress() {
    onProgressChanged?.call(_progress);
  }
}
