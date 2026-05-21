#!/usr/bin/env bash
# Bedrock Claude 모델 가용성 + inference profile 확인
# 함정: 신규 모델(Sonnet 4.5/Haiku 4.5)은 on-demand 미지원, inference profile 필수
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
REGION="${AWS_REGION:-ap-northeast-2}"

echo "═══════════════════════════════════════════════"
echo "Bedrock Claude 모델 확인 ($REGION)"
echo "═══════════════════════════════════════════════"
echo ""

echo "[1/3] 리전에서 ACTIVE 한 Claude 모델:"
AWS_PROFILE=$PROFILE aws bedrock list-foundation-models \
  --region "$REGION" \
  --query 'modelSummaries[?contains(modelId, `claude`) && modelLifecycle.status==`ACTIVE`].[modelId]' \
  --output table 2>&1 | head -25

echo ""
echo "[2/3] Inference profile (cross-region — Sonnet 4.5/Haiku 4.5 용):"
AWS_PROFILE=$PROFILE aws bedrock list-inference-profiles \
  --region "$REGION" \
  --query 'inferenceProfileSummaries[?contains(inferenceProfileName, `Sonnet 4`) || contains(inferenceProfileName, `Haiku 4`)].[inferenceProfileName,inferenceProfileId]' \
  --output table 2>&1

echo ""
echo "[3/3] Haiku 4.5 호출 테스트 (가장 저렴):"
TMP=$(mktemp)
cat > "$TMP" <<'EOF'
{"anthropic_version":"bedrock-2023-05-31","max_tokens":20,"messages":[{"role":"user","content":"Reply with just: OK"}]}
EOF

OUT=$(mktemp)
if AWS_PROFILE=$PROFILE aws bedrock-runtime invoke-model \
  --region "$REGION" \
  --model-id global.anthropic.claude-haiku-4-5-20251001-v1:0 \
  --content-type application/json \
  --accept application/json \
  --body "fileb://$TMP" \
  "$OUT" >/dev/null 2>&1; then
  TEXT=$(python3 -c "import json,sys;d=json.load(open('$OUT'));print(d['content'][0]['text'])" 2>/dev/null || cat "$OUT")
  echo "  ✓ 응답: $TEXT"
  echo ""
  printf '\033[32m✓ Bedrock Haiku 4.5 사용 가능\033[0m\n'
else
  printf '\033[33m! Bedrock 첫 호출 실패\033[0m — 콘솔에서 Anthropic 모델 약관 동의 필요할 수 있음:\n'
  echo "  https://${REGION}.console.aws.amazon.com/bedrock/home?region=${REGION}#/modelaccess"
  echo "  Anthropic → Claude Haiku 4.5 / Sonnet 4.5 → use case 폼 제출"
fi
rm -f "$TMP" "$OUT"

echo ""
echo "다음 단계: ./scripts/04-bootstrap-cdk.sh"
