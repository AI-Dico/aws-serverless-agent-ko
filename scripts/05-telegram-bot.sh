#!/usr/bin/env bash
# Telegram bot 토큰 검증 + Keychain 백업 안내
set -euo pipefail

cat <<'EOF'
═══════════════════════════════════════════════
Telegram bot 생성 안내
═══════════════════════════════════════════════

1. Telegram 앱에서 @BotFather 검색 → 채팅 시작
2. /newbot 입력
3. 봇 표시 이름 (예: My Cloud Agent)
4. 봇 username — '_bot' 으로 끝나야 함 (예: my_cloud_agent_bot)
5. BotFather 가 HTTP API token 줌 → 형태: 1234567890:ABCdef...

이 토큰을 .env 의 TELEGRAM_BOT_TOKEN 에 넣고 진행하세요.

EOF

if [ ! -f .env ]; then
  echo ".env 파일이 없습니다. 다음 명령 실행:"
  echo "  cp .env.example .env"
  echo "  편집기로 .env 열어서 TELEGRAM_BOT_TOKEN 채우기"
  exit 1
fi

source <(grep '^TELEGRAM_BOT_TOKEN=' .env | sed 's/^/export /')

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [[ "$TELEGRAM_BOT_TOKEN" == *XXXXX* ]]; then
  echo "✗ .env 의 TELEGRAM_BOT_TOKEN 이 비어있거나 placeholder 입니다."
  exit 1
fi

echo "토큰 검증 중..."
RESP=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")
if echo "$RESP" | grep -q '"ok":true'; then
  USERNAME=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['username'])")
  printf '\033[32m✓ Telegram bot 검증 성공: @%s\033[0m\n' "$USERNAME"
else
  echo "✗ 토큰이 유효하지 않습니다:"
  echo "$RESP"
  exit 1
fi

# Keychain 백업 (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo ""
  read -p "macOS Keychain 에 백업할까요? (y/N) " yn
  if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
    security add-generic-password -U \
      -a "$(whoami)" \
      -s "telegram/${USERNAME}/token" \
      -w "$TELEGRAM_BOT_TOKEN" -T "" 2>&1 | head -1
    echo "✓ Keychain 저장 (service: telegram/${USERNAME}/token)"
  fi
fi

echo ""
echo "다음 단계: ./scripts/06-deploy-secrets.sh"
