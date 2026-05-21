#!/usr/bin/env bash
# 비용 폭탄 방지: $5/월 Budget 알람 설정 (50% / 100% 실제 / 100% 예측)
# 모든 단계 진행 전 반드시 실행할 것
set -euo pipefail

PROFILE="${AWS_PROFILE:-dcode}"
EMAIL="${BUDGET_EMAIL:-}"
LIMIT="${BUDGET_LIMIT:-5}"

if [ -z "$EMAIL" ]; then
  read -p "알람 받을 이메일: " EMAIL
fi

if [ -z "$EMAIL" ]; then
  echo "이메일 필수"
  exit 1
fi

ACCOUNT_ID=$(AWS_PROFILE=$PROFILE aws sts get-caller-identity --query Account --output text)

echo "Budget '$LIMIT USD/월' 생성 → $EMAIL"

TMP=$(mktemp -d)

cat > "$TMP/budget.json" <<EOF
{
  "BudgetName": "monthly-${LIMIT}usd-cap",
  "BudgetLimit": {"Amount": "$LIMIT", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
EOF

cat > "$TMP/notifications.json" <<EOF
[
  {
    "Notification": {"NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 50, "ThresholdType": "PERCENTAGE", "NotificationState": "ALARM"},
    "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "$EMAIL"}]
  },
  {
    "Notification": {"NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 100, "ThresholdType": "PERCENTAGE", "NotificationState": "ALARM"},
    "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "$EMAIL"}]
  },
  {
    "Notification": {"NotificationType": "FORECASTED", "ComparisonOperator": "GREATER_THAN", "Threshold": 100, "ThresholdType": "PERCENTAGE", "NotificationState": "ALARM"},
    "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "$EMAIL"}]
  }
]
EOF

AWS_PROFILE=$PROFILE aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget "file://$TMP/budget.json" \
  --notifications-with-subscribers "file://$TMP/notifications.json" 2>&1 || {
    echo "이미 존재하거나 오류 발생. 기존 Budget 확인:"
    AWS_PROFILE=$PROFILE aws budgets describe-budgets --account-id "$ACCOUNT_ID" --query 'Budgets[].[BudgetName,BudgetLimit.Amount]' --output table
  }

rm -rf "$TMP"

echo ""
echo "✓ Budget 알람 설정 완료"
echo "  - 50% 실제 사용 시 이메일"
echo "  - 100% 실제 사용 시 이메일"
echo "  - 100% 예측 시 이메일"
echo ""
echo "다음 단계: ./scripts/03-bedrock-check.sh"
