#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este script deve ser executado no macOS." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "$script_dir/.." && pwd)"
helper_dir="$(cd "$app_dir/../backup-restore" && pwd)"
helper_path="$helper_dir/bin/kontabb-bkp"
app_path="$app_dir/build/macos/Build/Products/Release/backup_drive.app"
embedded_helper="$app_path/Contents/MacOS/kontabb-bkp"
app_executable="$app_path/Contents/MacOS/backup_drive"
archive_path="$app_dir/build/release/backup-drive-macos-helper-v1.2.zip"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

for tool in go lipo flutter codesign ditto unzip shasum; do
  command -v "$tool" >/dev/null || { echo "Ferramenta ausente: $tool" >&2; exit 1; }
done

mkdir -p "$(dirname "$helper_path")"
for arch in arm64 amd64; do
  GOOS=darwin GOARCH="$arch" CGO_ENABLED=0 go build -C "$helper_dir" \
    -trimpath -ldflags='-s -w' -o "$tmp_dir/kontabb-bkp-$arch" .
done
lipo -create -output "$helper_path" \
  "$tmp_dir/kontabb-bkp-arm64" "$tmp_dir/kontabb-bkp-amd64"
chmod 755 "$helper_path"
for arch in arm64 x86_64; do
  lipo -verify_arch "$arch" "$helper_path"
done

# Um atributo de proveniência em artefatos gerados localmente pode impedir o
# CodeSign do Xcode. A remoção se limita ao helper e ao bundle local de build.
xattr -d com.apple.provenance "$helper_path" 2>/dev/null || true
codesign --force --sign - "$helper_path"
codesign --verify --strict "$helper_path"
if [[ -d "$app_path" ]]; then
  xattr -dr com.apple.provenance "$app_path" 2>/dev/null || true
fi

(cd "$app_dir" && flutter build macos)

test -x "$embedded_helper"
for arch in arm64 x86_64; do
  lipo -verify_arch "$arch" "$app_executable"
  lipo -verify_arch "$arch" "$embedded_helper"
done
helper_help="$("$embedded_helper" -h 2>&1)"
[[ "$helper_help" == *'KONTABB v1.2'* ]]
[[ "$helper_help" == *'skip-missing-empty-tables'* ]]
codesign --verify --deep --strict "$app_path"

mkdir -p "$(dirname "$archive_path")"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
unzip -tq "$archive_path"
echo "Pacote local: $archive_path"
shasum -a 256 "$archive_path"
echo "A assinatura/notarização para distribuição deve ser feita separadamente."
