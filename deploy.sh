#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# moa 배포 → Dev Tools EC2 (172.22.2.109)
# 패턴 B (Swift/Vapor + Docker + nginx 프록시). 사용법: ./deploy.sh
# 사전: VPN 연결 + ~/.ssh/DevToolsKey.pem
#
# crash-dashboard(Node+pm2)와 달리 moa는 Swift라 Docker로 돌린다.
# nginx location /moa/ → 127.0.0.1:3110/moa/  →  http://172.22.2.109/moa/
# ============================================================
EC2_HOST="ec2-user@172.22.2.109"
KEY="$HOME/.ssh/DevToolsKey.pem"
REMOTE_DIR="/opt/moa"
PORT="3110"
CONTAINER="moa"
IMAGE="moa:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH="ssh -i $KEY -o StrictHostKeyChecking=no $EC2_HOST"

echo "==> [1/5] docker 확인 (최초 1회 설치)"
$SSH 'command -v docker >/dev/null 2>&1 || { sudo dnf install -y docker && sudo systemctl enable --now docker && sudo usermod -aG docker ec2-user; }; sudo docker --version'

echo "==> [2/5] 소스 동기화 (rsync) — .build/.git/로컬상태 제외"
rsync -az --delete \
  --exclude '.build' --exclude '.build_backup*' \
  --exclude '.git' --exclude '.DS_Store' \
  --exclude '.claude' --exclude '.env' --exclude '.swiftpm' \
  --exclude 'exports' --exclude 'docs' --exclude 'specs' --exclude '.specify' \
  --exclude 'tickets_*.md' \
  -e "ssh -i $KEY -o StrictHostKeyChecking=no" \
  "$SCRIPT_DIR/" "$EC2_HOST:$REMOTE_DIR/"

echo "==> [3/5] EC2에서 docker build (Vapor 릴리즈 빌드 — 최초 수 분)"
$SSH "cd $REMOTE_DIR && sudo docker build -t $IMAGE ."

echo "==> [4/5] 컨테이너 재기동 (127.0.0.1:$PORT → 8080)"
$SSH "sudo docker rm -f $CONTAINER 2>/dev/null || true; \
      sudo docker run -d --name $CONTAINER --restart unless-stopped \
        -p 127.0.0.1:$PORT:8080 $IMAGE; \
      sleep 3; sudo docker ps --filter name=$CONTAINER"

echo "==> [5/5] 헬스체크"
$SSH "curl -s -o /dev/null -w 'app /moa/ → HTTP %{http_code}\n' http://127.0.0.1:$PORT/moa/ || true"

echo ""
echo "✓ 컨테이너 기동 완료. 최초 1회 nginx 설정 필요:"
echo "  1) nginx-moa.conf 의 location 블록을 EC2의 /etc/nginx/conf.d/dev-tools.conf server{} 안에 추가"
echo "  2) $SSH 'sudo nginx -t && sudo systemctl reload nginx'"
echo "  3) Dev Tools 인덱스(/)에 moa 링크 추가 (선택)"
echo "  → 완료 후: http://172.22.2.109/moa/"
