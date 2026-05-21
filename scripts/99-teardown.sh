#!/usr/bin/env bash
# 모든 자원 삭제 — 더 이상 비용 발생 안 하도록
# 실행 전 확실히 백업 받고 진행할 것
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
REGION="${AWS_REGION:-ap-northeast-2}"
UPSTREAM="${UPSTREAM_DIR:-../serverless-openclaw}"

cat <<EOF
⚠️  모든 AWS 자원이 삭제됩니다:
  - 6 CloudFormation stacks
  - ECR repo (serverless-openclaw-lambda-agent)
  - S3 buckets (DynamoDB 데이터 포함)

EOF

read -p "정말 삭제? (yes 입력): " conf
[ "$conf" = "yes" ] || { echo "취소"; exit 1; }

cd "$UPSTREAM/packages/cdk"
export AWS_PROFILE
npx cdk destroy --all --force

# 외부 자원 정리
AWS_PROFILE=$PROFILE aws ecr delete-repository \
  --region "$REGION" \
  --repository-name serverless-openclaw-lambda-agent \
  --force 2>&1 | head -3 || true

echo ""
echo "✓ 삭제 완료. Budget 알람은 콘솔에서 따로 제거 (선택)"
