# AWS Serverless Cloud Agent — 한국어 빠른시작 가이드

> 맥미니 없이 **사용한 만큼만 과금되는** AI Cloud Agent를 AWS 서버리스로 띄우는 풀 튜토리얼.
> 원본: [serithemage/serverless-openclaw](https://github.com/serithemage/serverless-openclaw) (AWSKRUG 이상현님 발표)
> 이 레포: 한국어 안내 + **실배포로 검증된** 함정 회피 + 자동화 스크립트.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AWS](https://img.shields.io/badge/AWS-Serverless-orange)](https://aws.amazon.com/serverless/)
[![CDK](https://img.shields.io/badge/CDK-v2-blue)](https://aws.amazon.com/cdk/)
[![Verified](https://img.shields.io/badge/Verified-2026--05--22-green)](#-검증-완료)

## ✅ 검증 완료

**2026-05-21 ~ 22 실제 AWS 계정에서 처음부터 끝까지 따라하며 검증.** Telegram 봇이 실제 Claude Haiku 4.5 응답을 받아왔습니다.

| 항목 | 결과 |
|---|---|
| 6 CloudFormation stacks | 전부 CREATE_COMPLETE |
| Lambda Container | arm64, 2GB, 콜드 ~600ms, 웜 ~10ms |
| Bedrock 호출 | Claude Haiku 4.5 (`global.` inference profile) |
| Telegram webhook | 메시지 → API GW → Lambda → Bedrock → 응답 |
| 발견한 함정 | **14가지** (docs/troubleshooting.md) |
| 최종 비용 | 검증 전체 진행 + 며칠 운영 ~$0.30 |

## 0. 이게 뭐예요?

OpenClaw 같은 LLM agent를 **상시 켜놓는 맥미니 없이** AWS 서버리스로 굴립니다.
유휴 시간엔 **$0**, 호출당 약 1.35초 콜드스타트, **월 ~$1**로 운영.

```mermaid
graph LR
    User[👤 사용자]
    User -->|Telegram| BF[BotFather 봇]
    User -->|Web| Browser[CloudFront + React]

    BF -->|webhook| APIGW[API Gateway]
    Browser -->|WebSocket| APIGW

    APIGW --> Gateway[Gateway Lambda<br/>라우터/인증]

    Gateway -->|기본| LambdaAgent[Lambda Container<br/>1.35s cold, $0 idle]
    Gateway -->|장시간| Fargate[ECS Fargate Spot<br/>15분+ 작업]

    LambdaAgent -->|Bedrock| Claude[Claude Sonnet/Haiku]
    Fargate -->|Bedrock| Claude

    LambdaAgent <--> S3[(S3 — 세션 지속)]
    Fargate <--> S3
    Gateway <--> DDB[(DynamoDB —<br/>대화 이력)]

    style LambdaAgent fill:#90EE90
    style Claude fill:#FFD700
    style User fill:#87CEEB
```

## 1. 왜 서버리스?

```mermaid
graph TB
    subgraph 기존[기존: 맥미니 또는 EC2]
        M1[24시간 켜놓음]
        M2["월 $30~150 고정"]
        M3[유휴 시간에도 과금]
        M1 --> M2
        M2 --> M3
    end

    subgraph 서버리스[이 프로젝트]
        S1[호출 시에만 동작]
        S2["월 $1~2 (Free Tier 내)"]
        S3[유휴 시 $0]
        S1 --> S2
        S2 --> S3
    end

    style 기존 fill:#FFB6C1
    style 서버리스 fill:#90EE90
```

| | 기존 (맥미니/EC2) | 이 프로젝트 |
|---|---|---|
| 고정비 | $30~150/월 | **$0** |
| 유휴 비용 | 매시간 과금 | **$0** |
| 응답성 | 즉시 | 콜드 1.35s / 웜 0.12s |
| 확장 | 수동 | 자동 |
| 6개월 무료 크레딧 | 안 됨 | **$200 크레딧** |

## 2. 전체 흐름 (한 눈에)

```mermaid
flowchart LR
    A[0. 준비물<br/>5분] --> B[1. AWS 자격증명<br/>10분]
    B --> C[2. Budget 알람<br/>2분]
    C --> D[3. Bedrock 검증<br/>1분]
    D --> E[4. CDK bootstrap<br/>3분]
    E --> F[5. Telegram bot<br/>3분]
    F --> G[6. Secrets 배포<br/>2분]
    G --> H[7. Lambda 이미지<br/>10분]
    H --> I[8. 전체 배포<br/>15분]
    I --> J[9. Webhook<br/>1분]
    J --> J2[10. Anthropic 폼<br/>5분]
    J2 --> K[✅ 봇과 대화]

    style C fill:#FFE4B5
    style I fill:#90EE90
    style K fill:#FFD700
```

각 단계는 `scripts/0X-*.sh` 1개에 1:1 대응. 순서대로 실행하면 됩니다.

### 총 소요 시간

| 단계 | 시간 | 비고 |
|---|---|---|
| Phase 1 (사전 + AWS 세팅) | **~25분** | Node/Docker 설치 빠르면 단축 |
| Phase 2 (배포) | **~30분** | Docker 빌드가 대부분 |
| Phase 3 (검증 + 폼 제출) | **~10분** | Anthropic 폼 활성화 5분 대기 |
| **합계 (Lambda only)** | **~1시간 5분** | 처음 따라하는 경우 |
| Phase 4 (옵션: Fargate + MCP) | **+40분** | §6 참조 |

**Tip**: 함정에 안 걸리면 더 빠름. 우리 첫 시도엔 함정 14개 만나서 약 6시간 걸림. 이 가이드 따라하면 1시간.

## 3. 빠른 시작

### 사전 요구사항

```bash
# 자동 점검
./scripts/00-prereqs.sh
```

수동 설치 (macOS):
```bash
brew install node@22 awscli git
brew install --cask docker
npm install -g aws-cdk
```

### Step 1: 원본 클론 ⏱️ 2분

```bash
# 이 레포 옆에 원본도 같이 클론 (스크립트가 ../serverless-openclaw 를 참조)
cd ~/your-workspace/
git clone https://github.com/AI-Dico/aws-serverless-agent-ko.git
git clone https://github.com/serithemage/serverless-openclaw.git
cd aws-serverless-agent-ko
```

### Step 2: AWS 계정 + 자격증명 ⏱️ 10분

```mermaid
sequenceDiagram
    participant U as 사용자
    participant AWS as AWS 콘솔
    participant CLI as AWS CLI

    U->>AWS: 계정 생성 (Free 6개월 플랜)
    AWS-->>U: $100 크레딧 + Account ID
    U->>AWS: IAM 사용자 생성 (cdk-deployer)
    Note over U,AWS: AdministratorAccess 정책 첨부
    U->>AWS: Access Key 발급 (CLI 용도)
    AWS-->>U: AKIA... + Secret (CSV 다운로드)
    U->>CLI: aws configure --profile dcode
    Note over U,CLI: Key/Secret/Region(ap-northeast-2) 입력
    CLI-->>U: ~/.aws/credentials 저장
```

```bash
./scripts/01-aws-configure.sh
```

### Step 3: 비용 폭탄 방지 (필수!) ⏱️ 2분

```bash
BUDGET_EMAIL=your@email.com ./scripts/02-budget-alarm.sh
```
$5/월 알람 자동 생성 (50% / 100% 실제 / 100% 예측).

### Step 4: Bedrock 검증 ⏱️ 1분

```bash
./scripts/03-bedrock-check.sh
```

서울에서 사용 가능한 Claude 모델 + Haiku 4.5 호출 테스트.

**함정**: Sonnet 4.5/Haiku 4.5 는 on-demand 미지원 → **inference profile** 필요:
- ❌ `anthropic.claude-haiku-4-5-20251001-v1:0`
- ✅ `global.anthropic.claude-haiku-4-5-20251001-v1:0` (`global.` prefix)

### Step 5: CDK bootstrap ⏱️ 3분

```bash
./scripts/04-bootstrap-cdk.sh
```

해당 리전에 staging S3 + ECR + IAM roles 생성 (1회).

### Step 6: Telegram bot ⏱️ 3분

```bash
./scripts/05-telegram-bot.sh
```

@BotFather 안내 + 토큰 검증 + Keychain 백업.

### Step 7: `.env` 작성 ⏱️ 1분

```bash
cd ../serverless-openclaw  # 원본 레포로
cp ../aws-serverless-agent-ko/.env.example .env
# 편집기로 .env 열어서 TELEGRAM_BOT_TOKEN 채우기
```

### Step 8: 배포 (3단계) ⏱️ 25분

```mermaid
flowchart TD
    A[06: Secrets 배포] -->|CFN params 4개 주입| A2[SecretsStack ✓]
    A2 --> B[07: Lambda 이미지 빌드+푸시]
    B -->|ECR repo 외부 생성| B2[Docker 이미지 푸시됨]
    B2 --> C[08: 전체 배포]
    C --> C2[Storage + Auth + LambdaAgent + Api + Monitoring]
    C2 --> D[09: Telegram webhook]
    D --> E[봇 활성화 ✓]

    style A fill:#FFE4B5
    style B fill:#FFE4B5
    style E fill:#90EE90
```

```bash
cd ~/your-workspace/aws-serverless-agent-ko
./scripts/06-deploy-secrets.sh       # ⏱️ 2분
./scripts/07-build-lambda-image.sh   # ⏱️ 10분 (첫 빌드)
./scripts/08-deploy-all.sh           # ⏱️ 15분 (CloudFormation)
./scripts/09-telegram-webhook.sh     # ⏱️ 즉시
```

### Step 9: Anthropic Use case 폼 ⏱️ 5분 (콘솔)

🔴 **이걸 빼먹으면 봇이 "use case not submitted" 응답만 함**.

1. https://ap-northeast-2.console.aws.amazon.com/bedrock/home?region=ap-northeast-2#/model-catalog
2. **Anthropic → Claude Haiku 4.5** 클릭 → "Request model access"
3. 폼 작성 (Company name / Industry / Use case) → Submit
4. 즉시 ~ 15분 내 활성화

### Step 10: 동작 확인 ⏱️ 즉시

Telegram 앱에서 만든 봇과 대화 → 응답 옴 (콜드스타트 시 1~2초).

```mermaid
sequenceDiagram
    autonumber
    participant T as Telegram
    participant API as API Gateway
    participant L as Lambda Agent
    participant B as Bedrock Claude
    participant S as S3 (세션)

    T->>API: 메시지 webhook
    API->>L: invoke
    L->>S: 세션 로드 (있으면)
    L->>B: Claude API 호출
    B-->>L: 응답
    L->>S: 세션 저장
    L-->>API: 응답
    API-->>T: 메시지 전송
```

## 4. 예외 케이스 / 함정 (실배포로 검증한 14가지)

### 4.1 에러 메시지 → 어디로 가야 하나

| 본 에러 | 원인 | 해결 |
|---|---|---|
| 콘솔에서 "KMS 키 만드시오" 안내 | IAM ≠ KMS 헷갈림 | IAM → Users → Security credentials → Access keys ([T1](docs/troubleshooting.md#t1-kms--iam-access-key)) |
| `Model access page is deprecated` | 2025+ 부터 자동 활성화 | 그냥 모델 호출 → 자동 활성화 ([T2](docs/troubleshooting.md#t2-bedrock-model-access-페이지가-deprecated)) |
| `on-demand throughput isn't supported` | 신규 모델은 inference profile 필수 | 모델 ID 에 `global.` prefix ([T3](docs/troubleshooting.md#t3-on-demand-throughput-isnt-supported)) |
| `Parameters missing a value: BridgeAuthToken, ...` | SecretsStack 파라미터 미주입 | `./scripts/06-deploy-secrets.sh` 먼저 ([T4](docs/troubleshooting.md#t4-cdk-deploy-parameters-missing-a-value)) |
| `Source image ... does not exist` | ECR repo 외부 생성 필요 | `./scripts/07-build-lambda-image.sh` ([T5](docs/troubleshooting.md#t5-lambda-source-image-does-not-exist)) |
| `AccessDeniedException` (모델 호출) | Anthropic 약관 폼 미제출 | 콘솔 use case form 제출 ([T6](docs/troubleshooting.md#t6-bedrock-모델은-있는데-호출-실패-anthropic-약관)) / ([T14](docs/troubleshooting.md#t14-bedrock-model-use-case-details-have-not-been-submitted-🔴-가장-마지막-함정)) |
| `Cannot connect to Docker daemon` | Docker Desktop 미실행 | Docker Desktop 시작 또는 `colima start` ([T7](docs/troubleshooting.md#t7-docker-데몬-미실행)) |
| 청구서에 NAT Gateway/EC2 비용 | 실수로 만든 자원 | `./scripts/99-teardown.sh` ([T8](docs/troubleshooting.md#t8-비용이-늘고-있는데)) |
| 봇 무응답 | Webhook 미등록 | `./scripts/09-telegram-webhook.sh` ([T9](docs/troubleshooting.md#t9-telegram-봇이-응답-안-함)) |
| `image manifest ... is not supported` | Docker Desktop 28+ OCI manifest | `regctl image mod --to-docker` ([T11](docs/troubleshooting.md#t11-lambda-image-manifest--is-not-supported-🔴-큰-함정)) |
| `Cannot find module '@smithy/smithy-client'` | Dockerfile 의존성 누락 | Dockerfile 패치 ([T12](docs/troubleshooting.md#t12-lambda-container-cannot-find-module-smithysmithy-client)) |
| `Package subpath './retry' not exported` | OpenClaw + lib-dynamodb @smithy 버전 충돌 | 둘을 같이 `npm install` ([T13](docs/troubleshooting.md#t13-lambda-container-smithycoreretry-not-exported)) |
| `Model use case details have not been submitted` | 🔴 **가장 흔히 만나는 마지막 함정** | 콘솔 use case form 5분 ([T14](docs/troubleshooting.md#t14-bedrock-model-use-case-details-have-not-been-submitted-🔴-가장-마지막-함정)) |

### 4.2 단계별 진단 흐름

```mermaid
flowchart TD
    Start[배포 진행 중<br/>에러 발생] --> Q1{어느 단계?}

    Q1 -->|콘솔 IAM 설정| F1[T1: KMS 아님, Access Key]
    Q1 -->|cdk bootstrap| F2[T2/T3: 콘솔 region<br/>+ inference profile prefix]
    Q1 -->|cdk deploy| Q2{어떤 에러?}
    Q1 -->|Lambda 실행| Q3{어떤 import?}
    Q1 -->|Telegram 봇| Q4{응답 내용?}

    Q2 -->|Parameters missing| F4[T4: scripts/06 먼저]
    Q2 -->|Source image| F5[T5: scripts/07 먼저]
    Q2 -->|manifest not supported| F11[T11: regctl 변환]

    Q3 -->|@smithy/smithy-client| F12[T12: Dockerfile 의존성]
    Q3 -->|@smithy/core/retry| F13[T13: lib-dynamodb 같이 install]

    Q4 -->|무응답| F9[T9: webhook 등록]
    Q4 -->|use case not submitted| F14[T14: Anthropic 폼]
    Q4 -->|정상 응답| OK[✅ 끝]

    style F1 fill:#FFB6C1
    style F11 fill:#FFB6C1
    style F14 fill:#FFB6C1
    style OK fill:#90EE90
```

### 4.3 사용자가 직접 해야 하는 2가지 (스크립트 자동화 불가)

스크립트로 자동화한 12개와 별개로 **콘솔에서 직접** 해야 하는 작업 2가지:

1. **[T1] IAM Access Key 발급** — `aws configure` 입력값. AWS 콘솔에서 IAM 사용자 + Access Key (CSV 다운로드 1회만 가능)
2. **[T14] Anthropic Use case form** — Bedrock 콘솔에서 한 번만. 5분, 즉시 활성화

스크립트가 `./scripts/01-aws-configure.sh` / `./scripts/03-bedrock-check.sh` 실행 시점에 자동 안내합니다.

### 4.4 절대 만들면 안 되는 자원 (비용 폭탄)

| 자원 | 시간당 비용 | 한 달 |
|---|---|---|
| NAT Gateway | $0.045 | **$32** |
| Application Load Balancer | $0.022 + LCU | **$16+** |
| EC2 t3.small | $0.021 | **$15** |
| RDS db.t3.micro | $0.018 | **$13** |
| Interface VPC Endpoint | $0.01 | **$7** |

이 프로젝트는 **위 자원을 절대 만들지 않습니다** (CDK 가 `natGateways: 0` 강제). `cdk diff` 로 확인 후 배포하세요.

자세한 설명: [`docs/troubleshooting.md`](./docs/troubleshooting.md) (T1~T14 전체)

## 5. 비용 구조

```mermaid
pie title 월 예상 비용 (개인 사용 ~ $1)
    "Lambda (호출당)" : 30
    "DynamoDB (PAY_PER_REQUEST)" : 20
    "S3 + CloudFront" : 15
    "API Gateway" : 25
    "Bedrock 호출 (분당 몇 메시지)" : 10
```

- **유휴 시 0원** (Lambda + DynamoDB on-demand + S3)
- **호출당 ms 단위 과금**
- **Free Tier** 안에선 거의 무료 (Lambda 1M 호출/월, DynamoDB 25GB, S3 5GB)
- **AWS Free 6개월 플랜의 $200 크레딧** = 약 200개월 사용 가능

상세: [`docs/cost.md`](./docs/cost.md)

## 6. 후속: MCP 도구 통합 (실패 사례 + 미해결)

> 🚧 **Status (2026-05-22 검증 시점)**: **Lambda 채팅까지만 검증 완료**.
> MCP 통합은 OpenClaw 2026.2.13 의 schema/CLI 와 우리 가정이 어긋나서 보류.
> 이 섹션은 **시도한 경로와 발견한 함정** 의 기록 (다음 도전자 참고용).

기본 9단계는 **Lambda 만으로 LLM 채팅 봇** 까지. 봇이 ainote / Linear / GitHub 같은 MCP 도구를 호출하려면 **OpenClaw Gateway** 가 필요한데, Gateway 는 WebSocket 상시 프로세스라 Lambda 로는 못 띄움. 그래서 **Fargate Spot** 을 시도했습니다.

### 시도한 함정 4가지 (모두 막힘)

| # | 가정 | 실제 |
|---|---|---|
| T18 | `openclaw.json` root 의 `mcp.servers` 키로 MCP 등록 | OpenClaw 가 root 의 `mcp` 키 **거부** (Unrecognized key) |
| T19 | Bridge 가 ComputeStack env 만으로 부팅 | `CALLBACK_URL` env var 누락 → Bridge 즉시 죽음 |
| T20 | `openclaw mcp set` CLI 명령 사용 가능 | OpenClaw 2026.2.13 에는 **`mcp` subcommand 없음** (`Did you mean acp?`) |
| T21 | Telegram 은 API GW webhook 만 받음 | OpenClaw 가 env 의 `TELEGRAM_BOT_TOKEN` 감지해서 **자기 채널로 attach** → 충돌 |

→ Perplexity 검색 결과의 "MCP 통합 가이드" 가 **현재 OpenClaw 2026.2.13 과 일치하지 않음**. 시간 더 들여 deep dive 필요.

### 그래도 시도하려면 (미완성)

### 왜 Fargate Spot?

| | Lambda | EC2 | **Fargate Spot** |
|---|---|---|---|
| 상시 프로세스 가능 | ❌ 15분 한계 | ✅ | ✅ 무제한 |
| 유휴 비용 | $0 | $15+/월 | **$0** (watchdog auto-stop) |
| 콜드스타트 | 1.35s | 즉시 | ~68s |
| 가격 | $0.20/M req | $15/월 고정 | **$0.04/vCPU-시간** (70% 할인) |

Fargate Spot + **5분 무사용 시 자동 종료 (watchdog Lambda)** 조합으로 거의 $0 유휴 유지.

### 추가 비용

| 사용 패턴 | Fargate 비용/월 |
|---|---|
| 가끔 채팅 + 도구 호출 | ~$0.05 |
| 매일 5~10분 도구 사용 | ~$0.50 |
| 매일 1시간 활성 사용 | ~$2 |

### 활성화 절차 (총 ~40분)

```bash
# 1. MCP key SSM 저장 ⏱️ 1분
AWS_PROFILE=dcode aws ssm put-parameter \
  --name "/serverless-openclaw/secrets/ainote-mcp-auth" \
  --type SecureString --value "McpKey YOUR_TOKEN" \
  --region ap-northeast-2 --overwrite

# 2. .env 에서 AGENT_RUNTIME 변경 ⏱️ 즉시
# AGENT_RUNTIME=lambda  →  AGENT_RUNTIME=both

# 3. 원본 레포 코드 패치 ⏱️ 5분
#    patch-config.ts + compute-stack.ts (docs/mcp-integration.md 참조)

# 4. Fargate container 이미지 빌드 + push ⏱️ 15분
docker buildx build --platform linux/arm64 --provenance=false --sbom=false \
  -f packages/container/Dockerfile \
  -t $ECR_HOST/serverless-openclaw:latest --load .
docker push $ECR_HOST/serverless-openclaw:latest

# 5. cdk deploy ⏱️ 15분
#    NetworkStack + ComputeStack 신규 생성 (VPC + Fargate Cluster)
./scripts/08-deploy-all.sh
```

### 사용 방법 (Telegram)

```
사용자: /heavy 내 ainote 메모리에서 'serverless' 검색해줘
봇: (Lambda → Fargate Gateway 라우팅 → ainote MCP 호출 → 결과)
```

`/heavy` 또는 `/fargate` 힌트가 메시지에 있으면 라우터가 Fargate 로 보냄. 평소 짧은 채팅은 Lambda 로.

### 다음 도전자에게 (TODO)

1. OpenClaw 2026.2.13 의 실제 config schema 확인 — `~/.openclaw/openclaw.json` 의 정확한 키 트리
2. `openclaw acp` 가 MCP 대체인지, 별도인지 확인
3. `TELEGRAM_BOT_TOKEN` 환경변수 없이 Gateway 부팅하는 방법 (또는 OpenClaw 의 telegram plugin 비활성)
4. `CALLBACK_URL` 을 ComputeStack 에서 ApiStack 의 WebSocket URL 로 동적 inject

또는 우회 전략:
- **MCP 표준 포기**: Lambda agent 안에서 직접 ainote HTTP API 호출 (OpenClaw 의 tool system 우회)
- **Bedrock Agent Core**: AWS 의 Bedrock AgentCore Runtime + MCP 사용 ([AWS docs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html))

## 7. 정리 (사용 끝났을 때) ⏱️ ~10분

```bash
./scripts/99-teardown.sh
```

모든 stack + ECR repo 삭제. Budget 알람은 콘솔에서 따로.

## 8. 더 깊이 들어가기

- [`docs/architecture.md`](./docs/architecture.md) — 듀얼 컴퓨트 (Lambda + Fargate) 설계
- [`docs/troubleshooting.md`](./docs/troubleshooting.md) — 모든 함정 + 해결법
- [`docs/cost.md`](./docs/cost.md) — 비용 분석 + Free Tier 활용
- [`skills/aws-serverless-agent/`](./skills/aws-serverless-agent/) — Claude Code skill (다음 번엔 자동화)

## 라이센스

MIT — 원본 [serverless-openclaw](https://github.com/serithemage/serverless-openclaw) 의 라이센스 따름.

## 크레딧

- 발표: 이상현 (AWSKRUG, AWS Serverless Hero) — [serithemage/serverless-openclaw](https://github.com/serithemage/serverless-openclaw)
- 한국어 가이드: [AI-Dico](https://github.com/AI-Dico)
