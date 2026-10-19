#!/bin/bash
set -e

# Entrypoint do container Winbox (v3 ou v4 Windows via Wine).
# Inicia Xvnc (servidor X com VNC nativo — ver nota abaixo), o gerenciador
# de janelas, e Wine+Winbox conectando ao RouterOS.
#
# Env vars injetadas pelo NDE (docker run -e):
#   WINBOX_TARGET: IP:porta do RouterOS (ex: "10.0.1.5:22")
#   WINBOX_USER: usuário no RouterOS (ex: "admin")
#   WINBOX_PASS: senha (injetada aqui, nunca vista pelo navegador)
#   WINBOX_VERSION: "v3" ou "v4" (opcional, para debug)

set -a
source /etc/environment 2>/dev/null || true
set +a

# Defaults
WINBOX_TARGET="${WINBOX_TARGET:-localhost:22}"
WINBOX_USER="${WINBOX_USER:-admin}"
WINBOX_PASS="${WINBOX_PASS:-}"
DISPLAY=:1
WINEARCH=win64

echo "[winbox] Starting entrypoint"
echo "[winbox] Target: $WINBOX_TARGET"
echo "[winbox] User: $WINBOX_USER"
echo "[winbox] Display: $DISPLAY"

# 1. Inicia Xvnc (TigerVNC) — SUBSTITUI Xvfb + x11vnc.
#    Motivo da troca: x11vnc é um "capturador de tela" que se gruda num X
#    já existente (Xvfb) — e a versão do Debian (0.9.16, de 2019) NUNCA
#    implementou o pedido de redimensionamento vindo do cliente
#    (ExtendedDesktopSize/SetDesktopSize): há um PR aberto desde 2019
#    nunca mesclado (github.com/LibVNC/x11vnc/pull/107). Todo pedido de
#    resize batia "Resize is administratively prohibited" — não é uma
#    flag que falta, é uma feature que simplesmente não existe nessa
#    versão. Xvnc (TigerVNC) é um servidor X que já FALA VNC nativamente
#    (não uma captura de tela colada), com redimensionamento remoto
#    suportado de verdade, nativamente, sem flag nenhuma.
#    -SecurityTypes None: sem senha VNC (equivalente ao -nopw do x11vnc).
#    -localhost=0: escuta em todas as interfaces (não só loopback) — sem
#    isso, mesmo erro de alcançabilidade que já resolvemos antes pro
#    x11vnc (ver commit ea61ba9): o NDE conecta pelo IP da bridge do
#    Docker, não por localhost de dentro do container.
#    -AlwaysShared: múltiplos clientes (equivalente ao -shared).
echo "[winbox] Starting Xvnc..."
Xvnc $DISPLAY -geometry 1920x1080 -depth 24 -rfbport 5900 \
    -SecurityTypes None -localhost=0 -AlwaysShared \
    > /tmp/xvnc.log 2>&1 &
VNC_PID=$!
sleep 2

# 2. Aguarda X11 socket ficar pronto.
echo "[winbox] Waiting for X11 socket..."
for i in {1..30}; do
    if [ -S /tmp/.X11-unix/1 ]; then
        echo "[winbox] X11 ready"
        break
    fi
    sleep 0.5
done

# 2.5. Grava a sessão (vídeo, ffmpeg x11grab) — auditoria de acesso
#    privilegiado, mesmo motivo do bastion SSH. VNC é um
#    protocolo binário de framebuffer, não um stream de texto — gravar os
#    bytes brutos exigiria um player VNC customizado no replay; um vídeo é
#    reproduzível com uma tag <video> comum. "-framerate 8" é baixo de
#    propósito (auditoria, não streaming — reduz CPU e tamanho do arquivo).
#    SEM "-video_size": o frontend liga rfb.resizeSession=true, que manda o
#    Xvnc redimensionar a tela pro tamanho real da janela do navegador assim
#    que o cliente conecta — o tamanho passa a ser dinâmico, não o
#    "-geometry 1920x1080" do Xvnc.NewXvnc acima. Um "-video_size" fixo
#    batia de frente com o tamanho real ("Capture area 1920x1080 ... outside
#    the screen size 1551x774: Invalid argument", achado em produção —
#    ffmpeg morria na hora, sem gravar nada). Sem o parâmetro, o x11grab usa
#    o tamanho ATUAL da tela no momento em que começa a capturar.
#    Finalização é SEMPRE com SIGINT (nunca SIGKILL) antes de qualquer
#    cleanup — precisa escrever o trailer do MP4, senão o arquivo sai
#    corrompido (validado manualmente antes de integrar aqui). Se o
#    backend do NDE não copiar o arquivo antes de "docker rm -f", a gravação
#    simplesmente não existe — não trava nem falha a sessão.
#    "-vf scale=trunc(iw/2)*2:trunc(ih/2)*2": o libx264 exige largura/altura
#    PARES (subsampling de cor YUV420) — a tela redimensionada pelo
#    resizeSession do cliente pode sair ímpar (ex.: 1551x774, largura
#    ímpar), e sem esse filtro o ffmpeg morre com "width not divisible by 2"
#    / "Error initializing output stream" antes de escrever qualquer byte
#    (achado em produção: arquivo sempre saía com 0 bytes). O filtro
#    arredonda pra baixo pro par mais próximo — perde no máximo 1px, não dá
#    pra notar.
echo "[winbox] Starting ffmpeg recording..."
ffmpeg -y -f x11grab -framerate 8 -i "$DISPLAY" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -codec:v libx264 -preset ultrafast -pix_fmt yuv420p \
    /tmp/session.mp4 > /tmp/ffmpeg.log 2>&1 &
FFMPEG_PID=$!

# 3. Inicia o gerenciador de janelas (matchbox — kiosk: 1 app, tela cheia,
#    sem decoração). Sem isto a janela do Winbox abre no tamanho padrão
#    dela mesma, pequena, flutuando num desktop enorme. Precisa estar
#    rodando ANTES do Winbox abrir a janela principal, pra já nascer
#    maximizada.
echo "[winbox] Starting matchbox-window-manager..."
DISPLAY=$DISPLAY matchbox-window-manager -use_titlebar no > /tmp/matchbox.log 2>&1 &
MATCHBOX_PID=$!
sleep 1

# 4. Opcionalmente, descifera credencial de arquivo (se injetada cifrada).
#    Por enquanto, reutiliza env var WINBOX_PASS (recomenda-se usar arquivo cifrado em produção).
#    TODO: openssl enc -aes-256-cbc -d -in /run/secrets/winbox_pass -K ... -iv ...
if [ -f /run/secrets/winbox_pass ]; then
    echo "[winbox] Found encrypted credentials, decrypting..."
    # Placeholder: substituir por decrypt real
    WINBOX_PASS=$(cat /run/secrets/winbox_pass)
fi

# 5. Prepara os diretórios do prefixo Wine.
mkdir -p /root/.wine/prefix/drive_c/users/root/Desktop
mkdir -p /root/.wine/prefix/drive_c/windows/Temp

# 6. Inicia Wine + Winbox (modo interativo, foreground).
#    Auto-login via ARGUMENTOS DE LINHA DE COMANDO (documentado pela
#    MikroTik: `winbox.exe <connect-to> <login> <password>` — o
#    connect-to já aceita "host:porta"). Testamos antes um arquivo
#    ~/.winbox pra isso, mas não é um mecanismo real do Winbox — nenhuma
#    tentativa de conexão aparecia no log, só a descoberta padrão de
#    vizinhos. https://manual.mikrotik.com/docs/management-tools/winbox/
echo "[winbox] Starting Wine + Winbox..."
export DISPLAY=$DISPLAY
export WINEARCH=$WINEARCH
export WINEPREFIX=/root/.wine
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

cd /opt/winbox

# Detecta qual binário rodar (v3 vs v4).
if [ -f "winbox.exe" ]; then
    WINBOX_BIN="winbox.exe"
elif [ -f "WinBox.exe" ]; then
    WINBOX_BIN="WinBox.exe"
else
    echo "[winbox] ERROR: Winbox executable not found"
    kill -INT $FFMPEG_PID 2>/dev/null || true
    wait $FFMPEG_PID 2>/dev/null || true
    exit 1
fi

# Falha rápido e visível se o Wine não estiver disponível — sem isto, o
# "command not found" só aparecia no meio do log, e o script seguia até o
# "wait" (que retorna quase na hora) e ENTRAVA NA LIMPEZA, matando o
# Xvnc segundos depois de ter subido — exatamente o que causava "conexão
# perdida" no navegador pouco depois do WebSocket conectar.
#
# O comando é "wine" (universal), não "wine64": no Debian bookworm o
# pacote wine64 (8.0~repack-4) só traz BIBLIOTECAS de suporte — não expõe
# um /usr/bin/wine64 próprio. "wine" já respeita WINEARCH=win64 (exportado
# acima) pra criar/usar um prefixo 64-bit, que é o que precisamos pros
# .exe do Winbox baixados aqui (winbox64.exe / WinBox.exe, ambos 64-bit).
if ! command -v wine >/dev/null 2>&1; then
    echo "[winbox] FATAL: comando 'wine' não encontrado no PATH"
    dpkg -l | grep -i wine || echo "[winbox] nenhum pacote wine instalado"
    kill -INT $FFMPEG_PID 2>/dev/null || true
    wait $FFMPEG_PID 2>/dev/null || true
    kill $VNC_PID $MATCHBOX_PID 2>/dev/null || true
    exit 1
fi

echo "[winbox] Running: wine $WINBOX_BIN $WINBOX_TARGET $WINBOX_USER **** (WINEARCH=$WINEARCH)"
wine "$WINBOX_BIN" "$WINBOX_TARGET" "$WINBOX_USER" "$WINBOX_PASS" &
WINBOX_PID=$!

# 7. Aguarda Winbox ou X11 (qualquer processo principal fechar).
#    Quando usuário fecha a janela, Wine fecha, container encerra (cleanup automático).
echo "[winbox] Waiting for Winbox (PID $WINBOX_PID)..."
wait $WINBOX_PID
WINBOX_EXIT=$?
echo "[winbox] Winbox exited with code $WINBOX_EXIT"

# 8. Limpeza: finaliza o ffmpeg PRIMEIRO (SIGINT — escreve o trailer do MP4
#    corretamente) e espera ele terminar antes de matar o resto. Normalmente
#    o backend do NDE já fez isso e já copiou o arquivo antes de chegar aqui;
#    isto é só um fallback pro caso do
#    processo do Winbox encerrar sozinho (ex.: usuário fechou a janela) antes
#    do backend agir.
echo "[winbox] Stopping ffmpeg gracefully..."
kill -INT $FFMPEG_PID 2>/dev/null || true
wait $FFMPEG_PID 2>/dev/null || true

echo "[winbox] Cleaning up..."
kill $VNC_PID 2>/dev/null || true
kill $MATCHBOX_PID 2>/dev/null || true

echo "[winbox] Container shutdown"
exit 0
