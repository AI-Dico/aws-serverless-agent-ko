#!/usr/bin/env bash
# 나머지 stacks 전체 배포 (Storage, Auth, LambdaAgent, Api, Monitoring)
# SecretsStack 은 06 에서 이미 배포됨, parameters 는 CloudFormation 이 자동 재사용
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
UPSTREAM="${UPSTREAM_DIR:-../serverless-openclaw}"

cd "$UPSTREAM" && set -a && source .env && set +a && cd packages/cdk
export AWS_PROFILE

mkdir -p ../../.deploy-logs
LOG="../../.deploy-logs/deploy-all-$(date +%Y%m%d-%H%M%S).log"

echo "cdk deploy --all 시작 → 로그: $LOG"
echo "(Lambda Container 빌드 포함, 10~20분 예상)"

npx cdk deploy --all --require-approval never --concurrency 2 2>&1 | tee "$LOG"
EXIT=${PIPESTATUS[0]}

if [ $EXIT -eq 0 ]; then
  printf '\n\033[32m✓ 전체 배포 성공\033[0m\n'
  echo ""
  AWS_PROFILE=$PROFILE aws cloudformation list-stacks \
    --region "${AWS_REGION:-ap-northeast-2}" \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `Stack`)].[StackName,StackStatus]' \
    --output table
  echo ""
  echo "다음 단계: ./scripts/09-telegram-webhook.sh (Telegram 봇 활성화)"
else
  printf '\n\033[31m✗ 배포 실패 (exit=%d)\033[0m\n' "$EXIT"
  echo "로그 확인: tail -100 $LOG"
  exit $EXIT
fi
