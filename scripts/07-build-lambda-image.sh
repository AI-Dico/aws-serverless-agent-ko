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

# 3) Build + Push (arm64)
# 🔴 함정 T11: Docker Desktop 28+ containerd 백엔드 → buildx 가 OCI manifest 강제
#              Lambda 는 Docker v2 schema 2 만 받아서 "image manifest not supported" 에러
# 해결 1단계: provenance/sbom/attestations 끄고 ECR 푸시
export BUILDX_NO_DEFAULT_ATTESTATIONS=1
cd "$UPSTREAM"
docker buildx build \
  --platform linux/arm64 \
  --provenance=false \
  --sbom=false \
  -f packages/lambda-agent/Dockerfile \
  -t "$ECR_HOST/$REPO:latest" \
  --push .

# 4) Manifest 검증 + 필요 시 변환 (containerd 백엔드면 위 옵션만으로 부족)
echo ""
echo "Manifest 형식 확인 중..."
MEDIA=$(aws ecr describe-images --region "$REGION" \
  --repository-name "$REPO" \
  --image-ids imageTag=latest \
  --query 'imageDetails[0].imageManifestMediaType' --output text)
echo "Current: $MEDIA"

if [[ "$MEDIA" == *"oci"* ]]; then
  echo "→ OCI manifest 감지 — Docker v2 로 변환 (regctl)"
  if ! command -v regctl >/dev/null 2>&1; then
    echo "  regctl 설치 중..."
    brew install regclient 2>&1 | tail -2
  fi
  TOKEN=$(aws ecr get-login-password --region "$REGION")
  echo "$TOKEN" | regctl registry login "$ECR_HOST" --user AWS --pass-stdin >/dev/null
  regctl image mod --to-docker --replace "$ECR_HOST/$REPO:latest"

  MEDIA2=$(aws ecr describe-images --region "$REGION" \
    --repository-name "$REPO" \
    --image-ids imageTag=latest \
    --query 'imageDetails[0].imageManifestMediaType' --output text)
  echo "변환 후: $MEDIA2"
  if [[ "$MEDIA2" == *"docker.distribution.manifest.v2"* ]]; then
    echo "✓ Docker v2 manifest 변환 완료"
  else
    echo "❌ 변환 실패. Docker Desktop 설정 확인 필요:"
    echo "  Settings → General → 'Use containerd for pulling and storing images' OFF + 재시작"
    exit 1
  fi
else
  echo "✓ 이미 Docker v2 manifest"
fi

echo ""
echo "✓ 이미지 푸시 완료: $ECR_HOST/$REPO:latest"
echo ""
echo "다음 단계: ./scripts/08-deploy-all.sh"
