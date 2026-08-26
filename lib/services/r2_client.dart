import 'package:minio/minio.dart';

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
  /// Usa paginação interna para listar tudo independente do tamanho.
  Stream<Object> listAllObjects({String prefix = ''}) {
    return _minio.listObjects(config.bucketName, prefix: prefix, recursive: true);
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
  Future<void> downloadToFile(String objectName, String filePath) async {
    await _minio.fGetObject(config.bucketName, objectName, filePath);
  }
}
