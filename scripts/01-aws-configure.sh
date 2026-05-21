#!/usr/bin/env bash
# AWS 프로필 설정 안내 + 검증
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
REGION="${AWS_REGION:-ap-northeast-2}"

cat <<EOF
═══════════════════════════════════════════════
AWS 프로필 설정 — $PROFILE / $REGION
═══════════════════════════════════════════════

이 스크립트는 다음을 검증합니다:
  1. AWS 자격 증명 (Access Key ID / Secret)
  2. 리전 설정 (서울 권장)
  3. IAM 사용자 권한 (CDK 배포 가능 여부)

준비사항 (콘솔에서):
  - https://console.aws.amazon.com → IAM → Users
  - "Create user" → 이름: $PROFILE (또는 cdk-deployer)
  - Permissions: AdministratorAccess 정책 첨부
  - Security credentials 탭 → Create access key → CLI
  - Access Key ID + Secret 복사 (.csv 다운로드 권장)

EOF

if [ ! -f ~/.aws/credentials ] || ! grep -q "\[$PROFILE\]" ~/.aws/credentials 2>/dev/null; then
  echo "프로필 '$PROFILE' 가 ~/.aws/credentials 에 없습니다."
  echo ""
  echo "다음 명령으로 추가하세요:"
  echo "  aws configure --profile $PROFILE"
  echo ""
  echo "  AWS Access Key ID    : (콘솔에서 받은 값)"
  echo "  AWS Secret Access Key: (콘솔에서 받은 값)"
  echo "  Default region name  : $REGION"
  echo "  Default output format: json"
  exit 1
fi

echo "프로필 발견. 검증 중..."
IDENTITY=$(AWS_PROFILE=$PROFILE aws sts get-caller-identity 2>&1)
if [ $? -eq 0 ]; then
  echo "$IDENTITY"
  ACCOUNT_ID=$(echo "$IDENTITY" | grep -o '"Account":[[:space:]]*"[0-9]*"' | grep -o '[0-9]*')
  printf '\n\033[32m✓ AWS 인증 성공\033[0m\n'
  printf '  Account ID: %s\n' "$ACCOUNT_ID"
  printf '  Profile   : %s\n' "$PROFILE"
  printf '  Region    : %s\n\n' "$REGION"

  # Keychain 백업 권장 (macOS)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macOS Keychain 에 백업 (선택, 새 맥에서 복원용):"
    echo "  security add-generic-password -U -a \"$PROFILE\" -s \"aws/$PROFILE/access-key-id\" -w \"<AKIA...>\""
    echo "  security add-generic-password -U -a \"$PROFILE\" -s \"aws/$PROFILE/secret-access-key\" -w \"<...>\""
  fi

  echo ""
  echo "다음 단계: ./scripts/02-budget-alarm.sh"
else
  printf '\033[31m✗ AWS 인증 실패\033[0m\n'
  echo "$IDENTITY"
  exit 1
fi
