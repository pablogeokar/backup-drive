# Kontabb Backup Drive

Aplicativo desktop Flutter para gerenciamento de backups da Kontabb:
1. **Cloudflare R2**: Backup local completo e sincronização incremental de buckets (`teste` e `documents`).
2. **PostgreSQL**: Backup, restauração com validação de integridade e simulação (*dry-run*) utilizando o utilitário nativo embarcado `kontabb-bkp`.

Compatível com **Windows** e **macOS**.

---

## Requisitos

- **Flutter SDK**: `>= 3.11.5`
- **Go**: `>= 1.21` (opcional, apenas para recompilar o helper PostgreSQL `kontabb-bkp`)
- **Windows**: Visual Studio 2022 com suporte a Desktop C++
- **macOS**: Xcode 15+ e CocoaPods

---

## Executando o Projeto

### No Windows
```powershell
# Instalar dependências
flutter pub get

# Executar em modo Debug
flutter run -d windows

# Gerar executável de Release
flutter build windows
```
*O executável `kontabb-bkp.exe` é automaticamente copiado para a pasta de saída do build pelo CMake.*

### No macOS
```bash
# Instalar dependências
flutter pub get

# Executar em modo Debug
flutter run -d macos

# Gerar bundle .app de Release
flutter build macos
```
*O binário `kontabb-bkp` é automaticamente embarcado no diretório `Contents/MacOS/` do App Bundle pelo Xcode.*

---

## Estrutura do Projeto

- `lib/main.dart`: Ponto de entrada, temas e fontes nativas (`Segoe UI` no Windows, `SF Pro` no macOS).
- `lib/pages/home_page.dart`: Interface de sincronização com o Cloudflare R2.
- `lib/pages/database_page.dart`: Interface para backup/restore PostgreSQL com suporte a seleção de arquivos ocultos (`.env`).
- `lib/services/database_backup_service.dart`: Gerenciamento de processos e localização do binário auxiliar `kontabb-bkp` no Windows e macOS.
- `lib/services/r2_client.dart` & `sync_service.dart`: Cliente S3 MinIO e motor de sincronização incremental.
- `windows/`: Configuração de build CMake e Runner Windows.
- `macos/`: Configuração de projeto Xcode, Entitlements e Runner macOS.

---

## Resolução de Binários do Helper PostgreSQL

O aplicativo busca o helper `kontabb-bkp` / `kontabb-bkp.exe` na seguinte ordem de prioridade:
1. Variável de ambiente `KONTABB_BKP_PATH` (se definida)
2. Diretório adjacente ao executável (`backup_drive.exe` no Windows ou `Contents/MacOS` no macOS)
3. Pasta `Contents/Resources` (no macOS App Bundle)
4. Pastas relativas de desenvolvimento (`../Kontabb-backup-restore/bin/` ou `../backup-restore/bin/`)
