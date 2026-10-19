# Winbox bastion images (opt-in)

Imagens Docker que rodam o **Winbox v3/v4 (Windows)** em container Linux via Wine
+ Xvnc (TigerVNC). O NDE usa elas para abrir uma sessão Winbox no navegador,
tunelando VNC↔WebSocket pelo IP da bridge do container.

**Você monta estas imagens** — o build baixa o Winbox direto do site da MikroTik,
sob os termos da MikroTik. O binário do Winbox **não** é redistribuído aqui. Veja
o contexto e os avisos de segurança em [../docs/winbox.md](../docs/winbox.md).

## Construir

```bash
# a partir da raiz do repositório (o contexto de build é ".")
docker build -f docker/Dockerfile.winbox-v3 -t nde-winbox-v3:latest .
docker build -f docker/Dockerfile.winbox-v4 -t nde-winbox-v4:latest .

docker images | grep nde-winbox
```

Depois ligue o Winbox no painel do NDE (Configurações → Winbox). O servidor do
NDE precisa de acesso ao socket do Docker para subir um container por sessão —
entenda o trade-off (equivale a privilégio de root no host) antes de habilitar.

## Teste manual (sem o NDE)

```bash
docker network create nde-winbox-network

docker run -d --name test-winbox-v4 \
  --network nde-winbox-network \
  --memory 2g --cpus 2 \
  -e WINBOX_TARGET=10.0.1.5:22 \
  -e WINBOX_USER=admin \
  -e WINBOX_PASS=changeme \
  nde-winbox-v4:latest

docker ps | grep test-winbox
docker exec test-winbox-v4 pgrep -f Xvnc      # healthcheck
docker logs test-winbox-v4

docker rm -f test-winbox-v4
docker network rm nde-winbox-network
```

## Componentes do container

- **debian:bookworm-slim** — base.
- **Wine** — v3 usa o pacote do Debian; v4 usa o repositório oficial da WineHQ
  (vkd3d-shader mais novo, exigido pela interface Direct3D do Winbox v4).
- **Xvnc (TigerVNC)** — servidor X com VNC nativo e resize remoto de verdade
  (substitui Xvfb+x11vnc, que no Debian nunca implementou o resize pedido pelo
  cliente).
- **matchbox-window-manager** — WM mínimo (kiosk) pra janela abrir maximizada.
- **ffmpeg** — grava a sessão em MP4 para auditoria do acesso.
- **entrypoint-winbox.sh** — orquestra: Xvnc → matchbox → Wine+Winbox.

O Winbox recebe alvo/usuário/senha por variáveis de ambiente injetadas em runtime
(`WINBOX_TARGET`, `WINBOX_USER`, `WINBOX_PASS`) — a senha nunca chega ao navegador.

## Créditos

- Winbox: MikroTik — https://download.mikrotik.com/
- Wine: https://www.winehq.org/
- TigerVNC (Xvnc): https://github.com/TigerVNC/tigervnc
