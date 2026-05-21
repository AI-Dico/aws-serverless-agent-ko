# AWS Serverless Cloud Agent — 한국어 빠른시작 가이드

> 맥미니 없이 **사용한 만큼만 과금되는** AI Cloud Agent를 AWS 서버리스로 띄우는 풀 튜토리얼.
> 원본: [serithemage/serverless-openclaw](https://github.com/serithemage/serverless-openclaw) (AWSKRUG 이상현님 발표)
> 이 레포: 한국어 안내 + 함정 회피 + 자동화 스크립트.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AWS](https://img.shields.io/badge/AWS-Serverless-orange)](https://aws.amazon.com/serverless/)
[![CDK](https://img.shields.io/badge/CDK-v2-blue)](https://aws.amazon.com/cdk/)

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
    A[0. 준비물<br/>Node/Docker/AWS계정] --> B[1. AWS 자격증명]
    B --> C[2. Budget 알람<br/>$5/월]
    C --> D[3. Bedrock 검증]
    D --> E[4. CDK bootstrap]
    E --> F[5. Telegram bot]
    F --> G[6. Secrets 배포]
    G --> H[7. Lambda 이미지<br/>빌드+푸시]
    H --> I[8. 전체 배포]
    I --> J[9. Telegram webhook<br/>활성화]
    J --> K[✅ 봇과 대화]

    style C fill:#FFE4B5
    style I fill:#90EE90
    style K fill:#FFD700
```

각 단계는 `scripts/0X-*.sh` 1개에 1:1 대응. 순서대로 실행하면 됩니다.

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

### Step 1: 원본 클론

```bash
# 이 레포 옆에 원본도 같이 클론 (스크립트가 ../serverless-openclaw 를 참조)
cd ~/your-workspace/
git clone https://github.com/AI-Dico/aws-serverless-agent-ko.git
git clone https://github.com/serithemage/serverless-openclaw.git
cd aws-serverless-agent-ko
```

### Step 2: AWS 계정 + 자격증명

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

### Step 3: 비용 폭탄 방지 (필수!)

```bash
BUDGET_EMAIL=your@email.com ./scripts/02-budget-alarm.sh
```
$5/월 알람 자동 생성 (50% / 100% 실제 / 100% 예측).

### Step 4: Bedrock 검증

```bash
./scripts/03-bedrock-check.sh
```

서울에서 사용 가능한 Claude 모델 + Haiku 4.5 호출 테스트.

**함정**: Sonnet 4.5/Haiku 4.5 는 on-demand 미지원 → **inference profile** 필요:
- ❌ `anthropic.claude-haiku-4-5-20251001-v1:0`
- ✅ `global.anthropic.claude-haiku-4-5-20251001-v1:0` (`global.` prefix)

### Step 5: CDK bootstrap

```bash
./scripts/04-bootstrap-cdk.sh
```

해당 리전에 staging S3 + ECR + IAM roles 생성 (1회).

### Step 6: Telegram bot

```bash
./scripts/05-telegram-bot.sh
```

@BotFather 안내 + 토큰 검증 + Keychain 백업.

### Step 7: `.env` 작성

```bash
cd ../serverless-openclaw  # 원본 레포로
cp ../aws-serverless-agent-ko/.env.example .env
# 편집기로 .env 열어서 TELEGRAM_BOT_TOKEN 채우기
```

### Step 8: 배포 (3단계)

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
./scripts/06-deploy-secrets.sh       # ~2분
./scripts/07-build-lambda-image.sh   # 10~15분
./scripts/08-deploy-all.sh           # 10~15분
./scripts/09-telegram-webhook.sh     # 즉시
```

### Step 9: 동작 확인

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

## 4. 함정 정리 (당황하지 마세요)

```mermaid
flowchart TD
    Start[시작] --> Q1{KMS 키<br/>만들라고 했나?}
    Q1 -->|네| F1[❌ KMS 아님!<br/>IAM Access Key 입니다]
    Q1 -->|아니| Q2{Bedrock 모델<br/>access 페이지가<br/>비활성?}

    Q2 -->|네| F2[2025년 후반부터 자동 활성화<br/>그냥 모델 호출하면 됨]
    Q2 -->|아니| Q3{CDK deploy 가<br/>parameters 없다고<br/>실패?}

    Q3 -->|네| F3[scripts/06-deploy-secrets.sh<br/>먼저 실행]
    Q3 -->|아니| Q4{Lambda 가<br/>이미지 없다고<br/>실패?}

    Q4 -->|네| F4[scripts/07-build-lambda-image.sh<br/>실행 - ECR repo 외부 생성 필요]
    Q4 -->|아니| Q5{Bedrock 모델 호출 시<br/>"on-demand not supported"?}

    Q5 -->|네| F5[모델 ID 에 global./apac./us.<br/>prefix 붙이기]
    Q5 -->|아니| OK[정상]

    style F1 fill:#FFB6C1
    style F2 fill:#FFE4B5
    style F3 fill:#FFE4B5
    style F4 fill:#FFE4B5
    style F5 fill:#FFE4B5
    style OK fill:#90EE90
```

자세한 설명: [`docs/troubleshooting.md`](./docs/troubleshooting.md)

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

## 6. 정리 (사용 끝났을 때)

```bash
./scripts/99-teardown.sh
```

모든 stack + ECR repo 삭제. Budget 알람은 콘솔에서 따로.

## 7. 더 깊이 들어가기

- [`docs/architecture.md`](./docs/architecture.md) — 듀얼 컴퓨트 (Lambda + Fargate) 설계
- [`docs/troubleshooting.md`](./docs/troubleshooting.md) — 모든 함정 + 해결법
- [`docs/cost.md`](./docs/cost.md) — 비용 분석 + Free Tier 활용
- [`skills/aws-serverless-agent/`](./skills/aws-serverless-agent/) — Claude Code skill (다음 번엔 자동화)

## 라이센스

MIT — 원본 [serverless-openclaw](https://github.com/serithemage/serverless-openclaw) 의 라이센스 따름.

## 크레딧

- 발표: 이상현 (AWSKRUG, AWS Serverless Hero) — [serithemage/serverless-openclaw](https://github.com/serithemage/serverless-openclaw)
- 한국어 가이드: [AI-Dico](https://github.com/AI-Dico)
