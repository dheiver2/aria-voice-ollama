#!/bin/bash
set -e

APP_NAME="ÁRIA"
BUNDLE_NAME="AriaVoice.app"
BINARY_NAME="AriaVoice"
BUILD_DIR=".build/release"

echo "🔨 Compilando ÁRIA Voice..."
swift build -c release 2>&1

echo "📦 Criando bundle .app..."
rm -rf "$BUNDLE_NAME"
mkdir -p "$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$BUNDLE_NAME/Contents/Resources"

cp "$BUILD_DIR/$BINARY_NAME" "$BUNDLE_NAME/Contents/MacOS/"
cp Info.plist "$BUNDLE_NAME/Contents/"

# Ícone do app
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
    echo "🎨 Ícone AppIcon.icns aplicado."
else
    echo "⚠️  AppIcon.icns não encontrado — bundle sem ícone."
fi

echo "🔐 Assinando (identidade Apple Development, sem sandbox)..."
# Assinatura ad-hoc ("-") gera um hash novo a cada rebuild; o TCC associa as
# permissões de Microfone/Reconhecimento de Voz à identidade de código, e uma
# identidade instável faz o pedido de permissão abortar com SIGABRT
# (__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__) em vez de mostrar o prompt.
# Usar a identidade de desenvolvedor local (estável entre rebuilds) resolve.
DEV_ID="$(security find-identity -v -p codesigning | grep -m1 'Apple Development' | awk -F'"' '{print $2}')"
if [ -n "$DEV_ID" ]; then
    codesign --force --deep --sign "$DEV_ID" "$BUNDLE_NAME"
else
    echo "⚠️  Nenhuma identidade 'Apple Development' encontrada — caindo para ad-hoc."
    codesign --force --sign - "$BUNDLE_NAME"
fi

echo "✅ Build concluído: $BUNDLE_NAME"

# Copia ao Desktop para evitar restrições de launchd em ~/Downloads
echo "📋 Copiando para o Desktop..."
rm -rf ~/Desktop/"$BUNDLE_NAME"
cp -r "$BUNDLE_NAME" ~/Desktop/
xattr -cr ~/Desktop/"$BUNDLE_NAME"

echo ""
echo "▶️  Para executar:"
echo "   open ~/Desktop/$BUNDLE_NAME"
echo ""
echo "📌 Certifique-se que o Ollama está rodando:"
echo "   ollama serve"
