#!/usr/bin/env bash
# Lambda Container 이미지 빌드 + ECR 푸시
# 함정: ECR repo 'serverless-openclaw-lambda-agent' 가 CDK 외부 자원이라
#       먼저 만들고 이미지 푸시한 다음에야 LambdaAgentStack 배포 가능 (chicken-and-egg)
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
REGION="${AWS_REGION:-ap-northeast-2}"
UPSTREAM="${UPSTREAM_DIR:-../serverless-openclaw}"

ACCOUNT_ID=$(AWS_PROFILE=$PROFILE aws sts get-caller-identity --query Account --output text)
ECR_HOST="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO="serverless-openclaw-lambda-agent"

# 1) ECR repo 생성 (멱등)
if AWS_PROFILE=$PROFILE aws ecr describe-repositories --region "$REGION" --repository-names "$REPO" >/dev/null 2>&1; then
  echo "✓ ECR repo '$REPO' 이미 존재"
else
  AWS_PROFILE=$PROFILE aws ecr create-repository \
    --region "$REGION" \
    --repository-name "$REPO" \
    --image-scanning-configuration scanOnPush=true \
    --query 'repository.repositoryUri' --output text
fi

# 2) Docker login
AWS_PROFILE=$PROFILE aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_HOST"

# 3) Build (arm64 — Lambda 비용 효율적)
cd "$UPSTREAM"
docker buildx build --platform linux/arm64 \
  -f packages/lambda-agent/Dockerfile \
  -t "$REPO:latest" \
  --load .

# 4) Tag + Push
docker tag "$REPO:latest" "$ECR_HOST/$REPO:latest"
docker push "$ECR_HOST/$REPO:latest"

echo ""
echo "✓ 이미지 푸시 완료: $ECR_HOST/$REPO:latest"
echo ""
echo "다음 단계: ./scripts/08-deploy-all.sh"
