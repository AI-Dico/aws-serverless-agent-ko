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

## T14. Bedrock: "Model use case details have not been submitted" (🔴 가장 마지막 함정)

**증상**: 봇한테 메시지 보내면 답장은 오는데 내용이:
```
Model use case details have not been submitted for this account.
Fill out the Anthropic use case details form before using the model.
If you have already filled out the form, try again in 15 minutes.
```

**원인**: Bedrock 모델 access 페이지가 deprecated 됐어도 (T2 참고), **Anthropic 모델은 처음 사용 시 별도 use case 폼 제출 필수**. AWS 가 그 정보를 Anthropic 에 전달하는 정책.

**해결** — 콘솔에서 1회 (5분):
1. https://${REGION}.console.aws.amazon.com/bedrock/home?region=${REGION}#/model-catalog
2. **Anthropic / Claude Haiku 4.5** 카드 클릭
3. 우상단 **"Available to request"** 또는 **"Request model access"** 버튼
4. 폼 작성:

| 필드 | 입력 예시 |
|---|---|
| Company name | `Dcode` 같이 짧은 회사명 |
| Company website URL | 본인 사이트 또는 `https://example.com` |
| Industry | `Software / Technology` |
| Intended users | `Internal users` |
| Use case description | `Personal serverless AI assistant for development experiments via Telegram bot.` (500자 이내) |
| External user access | `No` |

5. **Submit** → 즉시 활성화 (대부분) 또는 5~15분
6. **Sonnet 4.5 도 같이 enable** (나중에 모델 업그레이드용)

폼 한 번 제출하면 계정 전체에서 모든 Anthropic 모델 사용 가능.

## T13. Lambda Container: "@smithy/core/retry not exported"

**증상**:
```
Error [ERR_PACKAGE_PATH_NOT_EXPORTED]:
Package subpath './retry' is not defined by "exports"
in /var/task/node_modules/@smithy/core/package.json
```

**원인**: OpenClaw 의 `@smithy/core` 와 `@aws-sdk/lib-dynamodb` 의 `@smithy/core` 가 버전 충돌. Dockerfile 에서 두 패키지를 따로 설치하면 의존성 tree 가 어긋남.

**해결**: 둘을 **함께 npm install** — npm 이 dependency tree 정리.

`packages/lambda-agent/Dockerfile`:
```dockerfile
# 💀 잘못된 방법 (separate install)
RUN npm install openclaw@${OPENCLAW_VERSION}
COPY --from=builder /build/node_modules/@aws-sdk/lib-dynamodb/ ...
COPY --from=builder /build/node_modules/@smithy/ ...

# ✅ 올바른 방법
RUN npm install openclaw@${OPENCLAW_VERSION} @aws-sdk/lib-dynamodb
```

## T12. Lambda Container: "Cannot find module '@smithy/smithy-client'"

**증상**: Lambda init 단계에서 module 못 찾음 — `@aws-sdk/lib-dynamodb` 의 transitive deps 누락.

**원인**: Lambda runtime 은 `@aws-sdk/*` 만 제공, `@smithy/*` 는 제공하지 않음. Dockerfile 이 `lib-dynamodb` 만 복사하고 의존성 누락.

**해결**: T13 과 통합 — `npm install` 로 함께 설치하면 npm 이 모든 transitive deps 자동 해결.

## T11. Lambda: "image manifest ... is not supported" (🔴 큰 함정)

**증상**:
```
Resource handler returned message: "The image manifest, config or layer media type
for the source image ... is not supported.
(Service: Lambda, Status Code: 400)"
```

**원인** (2025~2026 신규):
- Docker Desktop 28+ 의 **containerd 백엔드** 가 모든 image 를 **OCI manifest** 로 push
- Lambda Container 는 **Docker manifest v2 schema 2** 만 수용
- AWS 공식 문서가 권장하는 `--provenance=false` 만으로 **부족**

**시도해본 것들 (실패)**:
| 시도 | 결과 |
|---|---|
| `--provenance=false --sbom=false` | ❌ containerd 가 OCI 로 변환 |
| `--output type=image,oci-mediatypes=false` | ❌ buildx 가 무시 |
| `default` driver + `--load` + `docker push` | ❌ 여전히 OCI |
| `DOCKER_BUILDKIT=0` (legacy 빌더) | ❌ Docker 28 에서 무시 |
| `skopeo copy --format v2s2` | ❌ mediatype 충돌 |
| `crane pull/push` | ⚠️ 타임아웃 |

**진짜 해결책** — 두 가지 중 하나:

### 해결 A: `regctl` 로 manifest 변환 (가장 빠름)

```bash
brew install regclient

REGISTRY=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
TOKEN=$(aws ecr get-login-password --region $REGION)
echo "$TOKEN" | regctl registry login $REGISTRY --user AWS --pass-stdin

regctl image mod --to-docker --replace \
  $REGISTRY/serverless-openclaw-lambda-agent:latest
```

→ ECR 의 manifest 만 OCI → Docker v2 schema 2 로 in-place 교체. 모든 layer 그대로 (이미 docker mediatype 이라 변환 불필요).

### 해결 B: Docker Desktop containerd 스토리지 OFF (근본 해결)

1. Docker Desktop → ⚙️ Settings → **General**
2. **"Use containerd for pulling and storing images"** **체크 해제**
3. **"Apply & restart"**
4. 다시 빌드하면 `docker buildx` 가 처음부터 Docker v2 manifest 로 push

→ 빌드 자체가 정상화. 하지만 Docker Desktop 의 일부 새 기능 (multi-platform 캐시 등) 못 씀.

**우리 스크립트** (`07-build-lambda-image.sh`) 는 **A** 방식으로 자동 처리:
- 빌드 후 manifest 검증
- OCI 면 regctl 자동 설치 + 변환
- Docker v2 로 끝나야 통과

기존 OCI 이미지 ECR 에 있으면 먼저 삭제:
```bash
aws ecr batch-delete-image --region $REGION \
  --repository-name $REPO --image-ids imageTag=latest
```

**참고**:
- [AWS Lambda Node.js 컨테이너 문서](https://docs.aws.amazon.com/lambda/latest/dg/nodejs-image.html) (`--provenance=false` 권장 — 하지만 충분치 않음)
- [aws/aws-cdk#28178](https://github.com/aws/aws-cdk/issues/28178) — CDK + Docker Desktop containerd 호환성 이슈

## T10. 이미지가 너무 큰데?

**증상**: Docker 이미지가 1GB+ → Lambda 한도 (10GB) 는 OK 지만 콜드스타트 느림.

**최적화**:
- Dockerfile `FROM` 을 `public.ecr.aws/lambda/nodejs:22` 사용 (이미 적용됨)
- 멀티스테이지 빌드로 dev deps 제외 (이미 적용됨)
- `--platform=linux/arm64` 강제 (Graviton, 20% 저렴 + 빠름)

## 참고

- 발표 원본: [AWSKRUG Serverless 이상현 - 맥미니 없이도 서버리스로 만드는 AI Cloud Agent](https://github.com/serithemage/serverless-openclaw)
- 모든 함정은 실제 클론 → 배포 과정에서 만남 (2026-05-21).
