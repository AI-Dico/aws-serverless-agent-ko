#!/usr/bin/env bash
# SecretsStack 만 먼저 배포 — CloudFormation parameter 로 토큰 4개 주입
# 함정: cdk deploy --all 에서 secrets 가 parameter 라 처음엔 항상 실패. 이걸 먼저 한 번 실행해야 함.
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
UPSTREAM="${UPSTREAM_DIR:-../serverless-openclaw}"

if [ ! -d "$UPSTREAM/packages/cdk" ]; then
  echo "✗ 원본 레포 ($UPSTREAM) 가 없습니다."
  echo "  먼저 클론하세요: git clone https://github.com/serithemage/serverless-openclaw.git $UPSTREAM"
  exit 1
fi

cd "$UPSTREAM" && set -a && source .env && set +a && cd packages/cdk
export AWS_PROFILE

# 토큰 3개는 자동 생성, TELEGRAM_BOT_TOKEN 은 .env 에서
BRIDGE_TOKEN=$(openssl rand -hex 32)
GATEWAY_TOKEN=$(openssl rand -hex 32)
WEBHOOK_SECRET=$(openssl rand -hex 32)

# Keychain 백업
if [[ "$OSTYPE" == "darwin"* ]]; then
  for kv in \
    "openclaw/bridge-auth-token:$BRIDGE_TOKEN" \
    "openclaw/gateway-token:$GATEWAY_TOKEN" \
    "openclaw/telegram-webhook-secret:$WEBHOOK_SECRET"; do
    s="${kv%:*}"; v="${kv#*:}"
    security add-generic-password -U -a "$(whoami)" -s "$s" -w "$v" -T "" >/dev/null 2>&1 || true
  done
  echo "✓ 3개 시크릿 Keychain 백업"
fi

echo "SecretsStack 배포 중..."
npx cdk deploy SecretsStack \
  --parameters "BridgeAuthToken=$BRIDGE_TOKEN" \
  --parameters "OpenclawGatewayToken=$GATEWAY_TOKEN" \
  --parameters "TelegramBotToken=$TELEGRAM_BOT_TOKEN" \
  --parameters "TelegramWebhookSecret=$WEBHOOK_SECRET" \
  --require-approval never

echo ""
echo "✓ SecretsStack 배포 완료"
echo "  이후 cdk deploy 에서는 parameters 자동 재사용 (--require-approval never 만 있으면 됨)"
echo ""
echo "다음 단계: ./scripts/07-build-lambda-image.sh"
