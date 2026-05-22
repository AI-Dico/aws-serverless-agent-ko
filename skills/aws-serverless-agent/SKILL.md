---
name: aws-serverless-agent
description: AWS 서버리스로 OpenClaw 류 LLM agent 를 배포하는 자동화 — 사전요구사항 점검부터 IAM/Bedrock/CDK/Lambda Container 빌드/전체 stack 배포/Telegram webhook 등록까지 9단계 풀파이프라인. Use when 사용자가 "맥미니 없는 cloud agent 배포", "serverless openclaw 띄워줘", "AWS Bedrock + Telegram 봇 만들어", "Lambda Container agent 배포" 같은 요청을 할 때. 또는 발표 미러 실습 / Free Tier $200 크레딧 활용 맥락.
---

# AWS Serverless Cloud Agent Skill

## When to use

사용자가 다음을 요청할 때:
- "AWS 서버리스로 LLM agent 띄워줘"
- "맥미니 없이 cloud agent 만들어"
- "AWSKRUG 이상현 발표 실습"
- "serverless-openclaw 배포"
- "Bedrock + Telegram 봇"
- AWS Free Tier 활용 학습 프로젝트

## When NOT to use

- 이미 Anthropic API key 만으로 충분한 경우 (이건 AWS 인프라용)
- production 다중 사용자 서비스 (개인/POC 용도)
- AWS 계정 없고 만들 의향 없는 경우

## 사전 확인

```bash
# 1. 작업 디렉토리에 두 레포 같이 있는지
ls ../serverless-openclaw 2>/dev/null && echo "원본 OK" || echo "원본 클론 필요"
ls ../aws-serverless-agent-ko 2>/dev/null && echo "가이드 OK"

# 2. AWS CLI + Docker + Node 22+
./scripts/00-prereqs.sh
```

## 9단계 자동 실행

각 스크립트는 멱등 (재실행 안전). 실패 시 그 단계만 재시도.

```bash
cd ~/your-workspace/aws-serverless-agent-ko

./scripts/00-prereqs.sh              # 사전요구사항 점검
./scripts/01-aws-configure.sh        # AWS profile 검증
BUDGET_EMAIL=you@example.com \
  ./scripts/02-budget-alarm.sh       # 🔴 $5 알람 필수
./scripts/03-bedrock-check.sh        # Bedrock + Haiku 호출 테스트
./scripts/04-bootstrap-cdk.sh        # CDK bootstrap (1회)
./scripts/05-telegram-bot.sh         # BotFather 안내 + 토큰 검증
./scripts/06-deploy-secrets.sh       # SecretsStack (CFN params 주입)
./scripts/07-build-lambda-image.sh   # ECR repo + Docker arm64 + 푸시
./scripts/08-deploy-all.sh           # 6 stacks 배포 (10-20분)
./scripts/09-telegram-webhook.sh     # webhook 등록 → 봇 활성화
```

## 핵심 함정 (반드시 사용자에게 안내)

전체 14가지 — `docs/troubleshooting.md` T1~T14.

### 사용자가 직접 해야 (스크립트로 자동화 불가)
1. **T1 — KMS ≠ IAM**: 콘솔에서 IAM Access Key 발급 (KMS 키 만들지 말 것)
2. **T14 — Anthropic use case 폼**: Bedrock 콘솔에서 1회 폼 제출 (5분, 즉시 활성화)

### 스크립트가 자동 처리
3. **T3 — `global.` prefix**: `.env.example` 의 AI_MODEL 에 이미 적용
4. **T4 — SecretsStack params**: `06-deploy-secrets.sh` 가 4개 토큰 자동 생성+주입
5. **T5 — ECR repo 외부 생성**: `07-build-lambda-image.sh` 가 만들고 빌드+푸시
6. **T11 — Docker Desktop 28 OCI manifest**: docker push 직접 사용 + regctl fallback
7. **T12/T13 — @smithy deps 충돌**: Dockerfile 패치 (lib-dynamodb 와 openclaw 같이 npm install)

## 모델 선택 가이드

| 모드 | 모델 | 메시지당 비용 |
|---|---|---|
| 검증/POC | `global.anthropic.claude-haiku-4-5-20251001-v1:0` | ~$0.003 |
| 운영 | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` | ~$0.01 |

`.env` 의 `AI_MODEL` 수정 후 `08-deploy-all.sh` 재실행하면 적용.

## 비용 통제

- Budget 알람 ($5 권장, 50%/100%/예측)
- Free 6개월 플랜이면 한도 초과 시 자동 중단
- 안 쓸 때 `./scripts/99-teardown.sh` (모든 자원 삭제)

## 트러블슈팅

- 상세: `docs/troubleshooting.md` (T1~T10)
- 비용 분석: `docs/cost.md`
- 아키텍처: `docs/architecture.md`

## 메모리 저장

작업 시작 시 다음 정보 메모리에 저장:
- AWS 계정 ID + profile 명 → `aws-{account-name}-account.md`
- Telegram bot username + token Keychain 위치 → `{project}-telegram.md`
- 사용한 모델 + region

## 후속 작업

배포 성공 후:
1. Telegram 앱에서 봇과 대화 → 동작 확인
2. CloudWatch Logs 모니터링 (`/aws/lambda/serverless-openclaw-agent`)
3. 며칠 운영 후 Cost Explorer 에서 실제 비용 확인
4. 필요 시 Sonnet 으로 업그레이드 또는 prewarming 활성화

## 참고

- 원본: https://github.com/serithemage/serverless-openclaw
- 한국어 가이드: https://github.com/AI-Dico/aws-serverless-agent-ko
- 발표 영상: AWSKRUG Serverless 이상현 (검색)
