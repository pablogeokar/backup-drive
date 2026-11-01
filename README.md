# Kontabb Backup Drive

Aplicativo desktop Flutter para gerenciamento de backups da Kontabb:
1. **Cloudflare R2**: Backup local completo e sincronização incremental de buckets (`teste` e `documents`).
2. **PostgreSQL**: Backup, restauração com validação de integridade e simulação (*dry-run*) utilizando o utilitário nativo embarcado `kontabb-bkp`.
3. **Configuração local**: Conexões, caminhos e preferências são mantidos em um banco SQLite interno; o `.env` é necessário apenas se o usuário optar por importá-lo uma vez.

Compatível com **Windows** e **macOS**.

### Sincronização inteligente do R2

- Arquivos locais com o mesmo tamanho e data remota continuam sendo ignorados.
- Durante o download, o aplicativo grava no SQLite um checkpoint a cada 25 objetos.
- Se o app for fechado, a rede cair ou a operação for interrompida, a próxima execução usa `ListObjectsV2` com `start-after` e continua do último objeto confirmado.
- Checkpoints são separados por bucket e pasta local, evitando retomar uma operação no destino errado.
- Depois que a retomada termina, o checkpoint é removido e o ciclo seguinte volta a verificar o bucket completo para não perder objetos antigos que tenham sido alterados.

Uma sincronização baseada exclusivamente em mudanças, sem nenhuma listagem periódica, exige notificações de eventos do R2 conectadas a uma Cloudflare Queue/Worker. O modo local mantém a verificação completa após ciclos concluídos para garantir consistência sem depender de infraestrutura adicional.

---

## Requisitos

- **Flutter SDK**: `>= 3.11.5`
- **Go**: `>= 1.25.6` (opcional, apenas para recompilar o helper PostgreSQL `kontabb-bkp`)
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

# Gerar e conferir o pacote local com o helper v1.2 (no Windows x64)
.\scripts\build-windows-release.ps1
```
*O executável `kontabb-bkp.exe` é automaticamente copiado para a pasta de saída do build pelo CMake.*

### No macOS
```bash
# Instalar dependências
flutter pub get

# Executar em modo Debug
flutter run -d macos

# Gerar e conferir o pacote local universal com o helper v1.2
bash scripts/build-macos-release.sh
```
*O binário `kontabb-bkp` é automaticamente embarcado no diretório `Contents/MacOS/` do App Bundle pelo Xcode.*

Os scripts de release recompilam o helper do projeto irmão `backup-restore/`,
conferem `KONTABB v1.2` e a opção `skip-missing-empty-tables` no binário
embarcado, e criam arquivos ZIP locais em `build/release/`. No macOS o helper
é universal (Apple Silicon e Intel), como o aplicativo; o script também compara
o helper embarcado byte a byte com o recém-compilado. O script Windows deve
ser executado em um host Windows com Visual Studio instalado; o binário Go
para Windows sozinho não constitui um pacote do aplicativo validado. Os ZIPs
locais **não têm assinatura de distribuição nem notarização**: assine, notarize quando
aplicável e homologue a instalação em máquinas de cada plataforma antes de
distribuir aos operadores. A opção de restauração para tabelas
antigas vazias ausentes depende dessa versão. O campo correspondente na tela
PostgreSQL é opcional e exige os nomes exatos separados por vírgula; qualquer
linha encontrada no backup para uma dessas tabelas faz o restore abortar e
reverter a transação. Teste primeiro com **Simular restauração** em um banco
isolado. Para o backup anterior à migration `0004` da API, ao restaurar no
schema novo de 54 tabelas, informe exatamente
`sped_contabilistas,fiscal_lancamentos,fiscal_perfis_vigencia` nesse campo.
Em backups novos de 54 tabelas, deixe o campo vazio. O procedimento completo
está em `../api/docs/database-rebuild.md`. A interface não altera bancos
automaticamente.

Durante backup e restauração, a cópia de trabalho fica em uma pasta temporária
exclusiva da operação. O aplicativo remove essa pasta ao terminar e também se
o helper não puder iniciar. O arquivo selecionado pelo usuário permanece no
caminho original.

### Pacote Windows em runner hospedado

O workflow manual `backup-restore/.github/workflows/build-windows.yml` oferece
um runner Windows 2022 quando não houver um computador Windows local. Ele fica
no repositório do helper, busca o app público pela branch, tag ou commit
informado ao iniciar a execução, roda testes Go e Flutter e arquiva o ZIP com
um manifesto de commits e SHA-256 por 14 dias. Depois de enviar as mudanças
dos dois repositórios ao GitHub, inicie o workflow no repositório do helper em
**Actions → Build Windows Backup Drive → Run workflow**. O artefato fica sob as
permissões desse repositório; nenhum token adicional é necessário. O pacote
não é publicado nem instalado automaticamente. O script Windows agora confere
também os arquivos extraídos do ZIP; assinatura do executável e teste de
instalação/restauração em uma máquina Windows continuam necessários antes da
distribuição aos operadores.

---

## Estrutura do Projeto

- `lib/main.dart`: Ponto de entrada, temas e fontes nativas (`Segoe UI` no Windows, `SF Pro` no macOS).
- `lib/pages/home_page.dart`: Interface de sincronização com o Cloudflare R2.
- `lib/pages/database_page.dart`: Interface para backup/restore PostgreSQL com conexão salva e importação opcional de `.env`.
- `lib/services/app_database.dart`: Banco SQLite interno, migração das preferências antigas e repositório de conexões/configurações.
- `lib/services/database_backup_service.dart`: Gerenciamento de processos e localização do binário auxiliar `kontabb-bkp` no Windows e macOS.
- `lib/services/r2_client.dart` & `sync_service.dart`: Cliente S3 MinIO e motor de sincronização incremental.
- `windows/`: Configuração de build CMake e Runner Windows.
- `macos/`: Configuração de projeto Xcode, Entitlements e Runner macOS.

## Configurações locais

Na primeira execução após a atualização, o aplicativo migra automaticamente:

- a conexão PostgreSQL do `.env` anteriormente selecionado, quando o arquivo ainda estiver acessível;
- pasta de backup, ambiente R2, último sync e preferências de backup/restauração;
- caminhos de entrada e saída usados recentemente.

Depois da migração, a operação não depende mais do `.env`. O arquivo SQLite fica na pasta de suporte da aplicação do usuário, fora das pastas de backup. No macOS e em outros sistemas Unix, o diretório recebe permissão `0700` e o arquivo principal `0600`. As credenciais são locais e não são enviadas a serviços externos pelo aplicativo.

No macOS, a autorização de pastas externas também é persistida no SQLite por meio de um *security-scoped bookmark*. Instalações atualizadas precisam autorizar novamente a pasta de backup uma única vez; nas execuções seguintes, o acesso é restaurado automaticamente.

---

## Resolução de Binários do Helper PostgreSQL

O aplicativo busca o helper `kontabb-bkp` / `kontabb-bkp.exe` na seguinte ordem de prioridade:
1. Variável de ambiente `KONTABB_BKP_PATH` (se definida)
2. Diretório adjacente ao executável (`backup_drive.exe` no Windows ou `Contents/MacOS` no macOS)
3. Pasta `Contents/Resources` (no macOS App Bundle)
4. Pastas relativas de desenvolvimento (`../Kontabb-backup-restore/bin/` ou `../backup-restore/bin/`)
