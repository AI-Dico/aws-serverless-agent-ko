# 함정 및 해결 (Troubleshooting)

배포하면서 만난 함정과 해결법을 시간 순으로 정리.

## T1. KMS ≠ IAM Access Key

**증상**: AWS 콘솔에서 "키 생성" 검색 → KMS 키 생성 페이지가 뜸.

**원인**: KMS = 데이터 암호화용. CDK 배포는 **IAM Access Key** 가 필요.

**해결**:
1. IAM (Identity and Access Management) 검색
2. Users → 사용자 클릭 → **Security credentials** 탭
3. **Access keys** 섹션 → Create access key → "Command Line Interface (CLI)"
4. AKIA로 시작하는 ID + 40자 Secret → **CSV 다운로드 (한 번만 보임)**

## T2. Bedrock "model access" 페이지가 deprecated

**증상**: `https://.../bedrock/.../modelaccess` 들어가면 "이 페이지는 더 이상 사용되지 않습니다" 안내.

**원인**: 2025년 후반부터 AWS가 정책 변경 — serverless foundation 모델은 **첫 호출 시 자동 활성화**.

**해결**:
- 그냥 `aws bedrock-runtime invoke-model` 한 번 호출하면 활성화됨
- Anthropic 모델은 처음 호출 시 use case 폼이 뜰 수 있음 (콘솔 모달)
- `./scripts/03-bedrock-check.sh` 가 자동으로 호출해서 검증

## T3. "on-demand throughput isn't supported"

**증상**:
```
ValidationException: Invocation of model ID
anthropic.claude-sonnet-4-5-... with on-demand throughput isn't supported.
Retry your request with the ID or ARN of an inference profile.
```

**원인**: 신규 모델 (Sonnet 4.5, Haiku 4.5 등) 은 cross-region inference profile 만 지원.

**해결**: 모델 ID 에 prefix 추가:

| 잘못된 ID | 올바른 ID |
|---|---|
| `anthropic.claude-sonnet-4-5-20250929-v1:0` | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| `anthropic.claude-haiku-4-5-20251001-v1:0` | `global.anthropic.claude-haiku-4-5-20251001-v1:0` |

리전별 prefix:
- `global.` — 전세계 자동 라우팅 (권장)
- `apac.` — 아태평양
- `us.` — 미국
- `eu.` — 유럽

가용 프로필 조회:
```bash
aws bedrock list-inference-profiles --region ap-northeast-2
```

## T4. CDK deploy: "Parameters missing a value"

**증상**:
```
The following CloudFormation Parameters are missing a value:
BridgeAuthToken, OpenclawGatewayToken, TelegramBotToken, TelegramWebhookSecret
```

**원인**: SecretsStack 은 CFN parameter 로 토큰을 받음. `cdk deploy --all` 한 번에는 파라미터 못 넣음.

**해결**: SecretsStack 만 먼저 parameter 와 함께 배포 → 이후 `cdk deploy --all` 은 CloudFormation 이 자동 재사용.

```bash
./scripts/06-deploy-secrets.sh
```

스크립트가 하는 일:
```bash
npx cdk deploy SecretsStack \
  --parameters "BridgeAuthToken=$(openssl rand -hex 32)" \
  --parameters "OpenclawGatewayToken=$(openssl rand -hex 32)" \
  --parameters "TelegramBotToken=$TELEGRAM_BOT_TOKEN" \
  --parameters "TelegramWebhookSecret=$(openssl rand -hex 32)" \
  --require-approval never
```

## T5. Lambda: "Source image does not exist"

**증상**:
```
Resource handler returned message: "Source image
{ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/serverless-openclaw-lambda-agent:latest
does not exist."
```

**원인**: `serverless-openclaw-lambda-agent` ECR repo 는 CDK 외부 자원 (`fromRepositoryName`). 직접 만들고 이미지 푸시 필요. (Chicken-and-egg: Lambda 는 이미지 있어야 만들어지는데, CDK 가 동시에 ECR+Lambda 만들려고 함)

**해결**:
```bash
./scripts/07-build-lambda-image.sh
```

스크립트가 하는 일:
1. `serverless-openclaw-lambda-agent` ECR repo 생성 (멱등)
2. Docker login
3. arm64 이미지 빌드 (`packages/lambda-agent/Dockerfile`)
4. ECR 푸시
5. 이후 `cdk deploy --all` 가 이미지 참조 OK

## T6. Bedrock 모델은 있는데 호출 실패 (Anthropic 약관)

**증상**: 모델 호출 시 "AccessDeniedException" 또는 use case 폼 요구.

**해결**:
1. 브라우저로: `https://${REGION}.console.aws.amazon.com/bedrock/home?region=${REGION}#/modelaccess`
2. Anthropic 모델 옆 "Use case 제출" 폼 작성
3. "Personal AI agent for serverless cloud agent experiment" 정도 짧게
4. Submit → 보통 즉시 승인
5. 다시 호출

## T7. Docker 데몬 미실행

**증상**: `docker: command not found` 또는 `Cannot connect to the Docker daemon`.

**해결**:
- Docker Desktop 설치 + 실행
- 또는 colima: `brew install colima && colima start`

확인:
```bash
docker info  # 에러 안 나면 OK
```

## T8. 비용이 늘고 있는데?

**증상**: Billing 대시보드에서 예상치 못한 항목.

**즉시 조치**:
1. AWS 콘솔 → Cost Explorer → 어떤 서비스/리전에 청구됐는지 확인
2. 의심되는 stack 발견 시 `./scripts/99-teardown.sh`
3. Budget 알람 임계값 낮추기 ($1)

**원인 추적 체크리스트**:
- [ ] Fargate task 가 stop 안 됐나? `make task-status` / `make task-stop`
- [ ] CloudWatch Logs 가 너무 많이 쌓였나? Log group 의 retention 확인 (1주일 권장)
- [ ] NAT Gateway 가 실수로 만들어졌나? 시간당 $0.045 → 한 달이면 $32
- [ ] EC2 instance 떠 있나? (이 프로젝트는 절대 안 만듦)

## T9. Telegram 봇이 응답 안 함

**증상**: 봇한테 메시지 보내도 무반응.

**점검 순서**:
1. webhook 등록됐나? `make telegram-status`
2. webhook URL 이 올바른가? — API Gateway URL 인지 확인
3. Lambda 호출 로그: `aws logs tail /aws/lambda/serverless-openclaw-agent --follow`
4. CloudWatch Logs 에서 에러 확인
5. Bedrock 모델 권한 — Lambda execution role 에 `bedrock:InvokeModel` 있나?

수동 webhook 등록:
```bash
TOKEN=<your-token>
URL=<api-gw-url>/telegram
curl -X POST "https://api.telegram.org/bot${TOKEN}/setWebhook" \
  -d "url=${URL}&secret_token=$(cat ~/.secret/webhook)"
```

## T10. 이미지가 너무 큰데?

**증상**: Docker 이미지가 1GB+ → Lambda 한도 (10GB) 는 OK 지만 콜드스타트 느림.

**최적화**:
- Dockerfile `FROM` 을 `public.ecr.aws/lambda/nodejs:22` 사용 (이미 적용됨)
- 멀티스테이지 빌드로 dev deps 제외 (이미 적용됨)
- `--platform=linux/arm64` 강제 (Graviton, 20% 저렴 + 빠름)

## 참고

- 발표 원본: [AWSKRUG Serverless 이상현 - 맥미니 없이도 서버리스로 만드는 AI Cloud Agent](https://github.com/serithemage/serverless-openclaw)
- 모든 함정은 실제 클론 → 배포 과정에서 만남 (2026-05-21).
