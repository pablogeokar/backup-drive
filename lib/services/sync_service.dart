import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'app_database.dart';
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
  final bool resumedFromCheckpoint;

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
    this.resumedFromCheckpoint = false,
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
    bool? resumedFromCheckpoint,
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
      resumedFromCheckpoint:
          resumedFromCheckpoint ?? this.resumedFromCheckpoint,
    );
  }
}

/// Representação simplificada de um objeto remoto para sync.
class _RemoteObject {
  final String key;
  final int size;
  final DateTime? lastModified;

  const _RemoteObject({
    required this.key,
    required this.size,
    this.lastModified,
  });
}

class _SyncCheckpoint {
  const _SyncCheckpoint({
    required this.lastProcessedKey,
    required this.startedAt,
  });

  final String lastProcessedKey;
  final DateTime startedAt;

  Map<String, Object> toJson() => {
    'lastProcessedKey': lastProcessedKey,
    'startedAt': startedAt.toIso8601String(),
  };

  static _SyncCheckpoint? fromJson(String? value) {
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final key = json['lastProcessedKey'] as String?;
      final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
      if (key == null || key.isEmpty || startedAt == null) return null;
      return _SyncCheckpoint(lastProcessedKey: key, startedAt: startedAt);
    } catch (_) {
      return null;
    }
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

  SyncService({required R2Config config, required String localBasePath})
    : _client = R2Client(config: config),
      _localBasePath = localBasePath;

  /// Caminho base onde os arquivos são salvos localmente.
  String get localBasePath => _localBasePath;

  /// Testa a conexão com o R2.
  Future<bool> testConnection() => _client.testConnection();

  /// Solicita cancelamento da sync em andamento.
  void cancelSync() {
    _cancelRequested = true;
  }

  /// Executa a sincronização completa (incremental) com retomada persistente.
  ///
  /// Para cada objeto no bucket:
  /// 1. Verifica se já existe localmente.
  /// 2. Se existe, compara o tamanho e data de modificação.
  /// 3. Se diferente ou não existe, faz download.
  /// 4. Persiste checkpoints periódicos para retomar após interrupções.
  ///
  /// Uma execução concluída ainda faz uma nova listagem no próximo ciclo. A
  /// API S3 não oferece um cursor de "alterações desde a última sincronização";
  /// ignorar permanentemente chaves anteriores perderia arquivos atualizados.
  Future<void> sync() async {
    _cancelRequested = false;
    final checkpoint = await _loadCheckpoint();
    final resumed = checkpoint != null;
    _progress = SyncProgress(
      status: SyncStatus.listing,
      resumedFromCheckpoint: resumed,
      currentFile: resumed
          ? 'Retomando após ${checkpoint.lastProcessedKey}'
          : '',
    );
    _notifyProgress();

    try {
      // Fase 1: Listar todos os objetos
      final objects = <_RemoteObject>[];
      await for (final chunk in _client.listAllObjects(
        startAfter: checkpoint?.lastProcessedKey,
      )) {
        if (_cancelRequested) {
          _progress = _progress.copyWith(
            status: SyncStatus.idle,
            errorMessage: 'Sync cancelado pelo usuário.',
          );
          _notifyProgress();
          return;
        }
        for (final obj in chunk.objects) {
          final key = obj.key ?? '';
          if (key.isNotEmpty && !key.endsWith('/')) {
            objects.add(
              _RemoteObject(
                key: key,
                size: obj.size ?? 0,
                lastModified: obj.lastModified,
              ),
            );
          }
        }
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
      int sinceLastCheckpoint = 0;
      String? lastSafeKey = checkpoint?.lastProcessedKey;
      bool checkpointBlockedByError = false;
      final startedAt = checkpoint?.startedAt ?? DateTime.now();

      for (final obj in objects) {
        if (_cancelRequested) {
          if (lastSafeKey != null) {
            await _saveCheckpoint(lastSafeKey, startedAt);
          }
          _progress = _progress.copyWith(
            status: SyncStatus.idle,
            errorMessage: 'Sync cancelado pelo usuário.',
          );
          _notifyProgress();
          return;
        }

        _progress = _progress.copyWith(currentFile: obj.key);
        _notifyProgress();

        try {
          final needsDownload = await _shouldDownload(obj);

          if (needsDownload) {
            await _downloadObject(obj.key);
            downloaded++;
          } else {
            skipped++;
          }
          if (!checkpointBlockedByError) {
            lastSafeKey = obj.key;
            sinceLastCheckpoint++;
            if (sinceLastCheckpoint >= 25) {
              await _saveCheckpoint(lastSafeKey, startedAt);
              sinceLastCheckpoint = 0;
            }
          }
        } catch (e) {
          errors++;
          checkpointBlockedByError = true;
          // Guardar último erro para diagnóstico
          _progress = _progress.copyWith(errorMessage: '[${obj.key}] $e');
        }

        _progress = _progress.copyWith(
          processedObjects: downloaded + skipped + errors,
          downloadedObjects: downloaded,
          skippedObjects: skipped,
          errorCount: errors,
        );
        _notifyProgress();
      }

      if (errors == 0) {
        await _clearCheckpoint();
      } else if (lastSafeKey != null) {
        await _saveCheckpoint(lastSafeKey, startedAt);
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
  Future<bool> _shouldDownload(_RemoteObject remoteObj) async {
    final localPath = p.join(_localBasePath, remoteObj.key);
    final localFile = File(localPath);

    if (!localFile.existsSync()) {
      return true;
    }

    final localSize = localFile.lengthSync();

    // Se o tamanho difere, precisa re-baixar
    if (localSize != remoteObj.size) {
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
    await _client.downloadToFile(key, localPath);
  }

  /// Salva o timestamp da última sincronização.
  Future<void> _saveLastSyncTime() async {
    await AppDatabase.instance.setString(
      'last_sync_time',
      DateTime.now().toIso8601String(),
    );
  }

  /// Carrega o timestamp da última sincronização.
  Future<DateTime?> getLastSyncTime() async {
    final stored = await AppDatabase.instance.getString('last_sync_time');
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  String get _checkpointKey {
    final identity =
        '${_client.config.bucketName}|${p.normalize(_localBasePath)}';
    final encoded = base64Url.encode(utf8.encode(identity));
    return 'r2_sync_checkpoint.$encoded';
  }

  Future<_SyncCheckpoint?> _loadCheckpoint() async {
    final value = await AppDatabase.instance.getString(_checkpointKey);
    return _SyncCheckpoint.fromJson(value);
  }

  Future<void> _saveCheckpoint(String lastProcessedKey, DateTime startedAt) {
    final checkpoint = _SyncCheckpoint(
      lastProcessedKey: lastProcessedKey,
      startedAt: startedAt,
    );
    return AppDatabase.instance.setString(
      _checkpointKey,
      jsonEncode(checkpoint.toJson()),
    );
  }

  Future<void> _clearCheckpoint() =>
      AppDatabase.instance.setString(_checkpointKey, null);

  void _notifyProgress() {
    onProgressChanged?.call(_progress);
  }
}
