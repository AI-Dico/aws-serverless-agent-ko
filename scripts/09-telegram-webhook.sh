#!/usr/bin/env bash
# Telegram webhook 등록 — API Gateway 의 /telegram endpoint 를 BotFather 에 알려줌
# 등록되면 봇한테 메시지 보내면 Lambda 가 호출됨
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
REGION="${AWS_REGION:-ap-northeast-2}"
UPSTREAM="${UPSTREAM_DIR:-../serverless-openclaw}"

cd "$UPSTREAM"
make telegram-webhook
echo ""
echo "Webhook 상태 확인:"
make telegram-status
echo ""
echo "이제 Telegram 앱에서 봇한테 메시지 보내보세요 (예: 'Hello')"
echo "로그 확인: AWS_PROFILE=$PROFILE aws logs tail /aws/lambda/serverless-openclaw-agent --follow --region $REGION"
