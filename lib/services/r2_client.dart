import 'dart:io';

import 'package:minio/minio.dart';
import 'package:minio/models.dart';

import 'r2_config.dart';

/// Cliente para interagir com o Cloudflare R2 via protocolo S3.
class R2Client {
  final R2Config config;
  late final Minio _minio;

  R2Client({required this.config}) {
    _minio = Minio(
      endPoint: config.endpoint,
      accessKey: config.accessKeyId,
      secretKey: config.secretAccessKey,
      useSSL: true,
      region: 'auto',
    );
  }

  /// Verifica se a conexão com o bucket está funcionando.
  Future<bool> testConnection() async {
    try {
      final exists = await _minio.bucketExists(config.bucketName);
      return exists;
    } catch (e) {
      return false;
    }
  }

  /// Lista todos os objetos no bucket, retornando metadados completos.
  Stream<ListObjectsResult> listAllObjects({String prefix = ''}) {
    return _minio.listObjects(
      config.bucketName,
      prefix: prefix,
      recursive: true,
    );
  }

  /// Obtém os metadados (stat) de um objeto específico.
  Future<StatObjectResult> statObject(String objectName) {
    return _minio.statObject(config.bucketName, objectName);
  }

  /// Faz download de um objeto e retorna o stream de bytes.
  Future<MinioByteStream> getObject(String objectName) {
    return _minio.getObject(config.bucketName, objectName);
  }

  /// Faz download de um objeto diretamente para um arquivo local.
  ///
  /// Usa getObject + pipe ao invés de fGetObject para evitar problema
  /// com etag contendo aspas (caractere inválido em nomes de arquivo no Windows).
  Future<void> downloadToFile(String objectName, String filePath) async {
    final dir = File(filePath).parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final stream = await _minio.getObject(config.bucketName, objectName);
    final file = File(filePath);
    final sink = file.openWrite();

    try {
      await stream.pipe(sink);
    } catch (e) {
      // Limpar arquivo parcial em caso de erro
      await sink.close();
      if (file.existsSync()) {
        file.deleteSync();
      }
      rethrow;
    }
  }
}
