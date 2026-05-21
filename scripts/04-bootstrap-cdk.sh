#!/usr/bin/env bash
# CDK bootstrap — 해당 리전에 staging S3 + ECR + IAM roles 1회 생성
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
REGION="${AWS_REGION:-ap-northeast-2}"

ACCOUNT_ID=$(AWS_PROFILE=$PROFILE aws sts get-caller-identity --query Account --output text)

# 이미 부트스트랩됐는지 확인
if AWS_PROFILE=$PROFILE aws cloudformation describe-stacks --region "$REGION" --stack-name CDKToolkit >/dev/null 2>&1; then
  echo "✓ CDKToolkit 스택 이미 존재 — bootstrap 스킵"
else
  echo "CDK bootstrap 시작 → aws://$ACCOUNT_ID/$REGION"
  AWS_PROFILE=$PROFILE npx cdk bootstrap "aws://$ACCOUNT_ID/$REGION"
fi

echo ""
echo "다음 단계: ./scripts/05-telegram-bot.sh"
