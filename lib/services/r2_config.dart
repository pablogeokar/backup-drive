/// Configuração de conexão com o Cloudflare R2.
///
/// As credenciais são carregadas diretamente aqui para simplificar o app
/// de backup local (Windows desktop). Em produção, considere usar um
/// mecanismo de secrets mais robusto.
class R2Config {
  /// Account ID da Cloudflare.
  final String accountId;

  /// Access Key ID (equivalente ao AWS Access Key).
  final String accessKeyId;

  /// Secret Access Key (equivalente ao AWS Secret Key).
  final String secretAccessKey;

  /// Nome do bucket no R2.
  final String bucketName;

  const R2Config({
    required this.accountId,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.bucketName,
  });

  /// Endpoint S3-compatible do Cloudflare R2.
  /// Formato: `https://<account_id>.r2.cloudflarestorage.com`
  String get endpoint => '$accountId.r2.cloudflarestorage.com';

  /// Configuração de desenvolvimento (bucket "teste").
  static const development = R2Config(
    accountId: '59e3d4637e95b5211d389160b42a0a94',
    accessKeyId: '84905d05accb0e8a8841ae59b403d0e6',
    secretAccessKey:
        'f4da87d6f498494d6e5fe771fc8aaf3d49591bf659afb5d32935c72994c5a2d8',
    bucketName: 'teste',
  );

  /// Configuração de produção (bucket "documents").
  static const production = R2Config(
    accountId: 'bce187765eb43b27e635faf4d7edee12',
    accessKeyId: '7558dc89cdbd2b9eeb84768a3de24ce4',
    secretAccessKey:
        '66c6833b6ebc0150918d29a9b3e528f4f7746d0465683bbf4a1edf9e103d5c10',
    bucketName: 'documents',
  );
}
