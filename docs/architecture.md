# 아키텍처

## 전체 구조

```mermaid
graph TB
    subgraph 사용자["👤 사용자 인터페이스"]
        TG[Telegram 앱]
        WEB[웹 브라우저]
    end

    subgraph CDN["🌐 CDN + 정적"]
        CF[CloudFront]
        S3W[S3 — React SPA]
    end

    subgraph API["🔌 API 계층"]
        APIGW_WS[API Gateway<br/>WebSocket]
        APIGW_REST[API Gateway<br/>REST]
    end

    subgraph Lambda["⚡ Gateway Lambda 7개"]
        WSCONN[ws-connect]
        WSMSG[ws-message]
        WSDISC[ws-disconnect]
        TGWH[telegram-webhook]
        APIH[api-handler]
        WD[watchdog]
        PW[prewarm]
    end

    subgraph Compute["🤖 Agent 실행"]
        LA[Lambda Container<br/>OpenClaw<br/>1.35s cold]
        FG[ECS Fargate Spot<br/>15min+ tasks]
    end

    subgraph Storage["💾 영속화"]
        DDB[(DynamoDB<br/>5 tables)]
        S3D[(S3 — sessions)]
    end

    subgraph LLM["🧠 LLM"]
        BR[Bedrock Claude<br/>Sonnet/Haiku]
    end

    TG -->|webhook| APIGW_REST
    WEB --> CF
    CF --> S3W
    WEB -->|WebSocket| APIGW_WS

    APIGW_WS --> WSCONN
    APIGW_WS --> WSMSG
    APIGW_WS --> WSDISC
    APIGW_REST --> TGWH
    APIGW_REST --> APIH
    APIGW_REST --> WD
    APIGW_REST --> PW

    WSMSG --> LA
    WSMSG --> FG
    TGWH --> LA
    TGWH --> FG

    LA --> BR
    FG --> BR

    LA <--> DDB
    FG <--> DDB
    LA <--> S3D
    FG <--> S3D

    style LA fill:#90EE90
    style FG fill:#FFE4B5
    style BR fill:#FFD700
```

## 듀얼 컴퓨트의 비밀

```mermaid
flowchart LR
    Msg[메시지 도착] --> R{route-classifier}

    R -->|짧은 작업| L[Lambda<br/>1.35s cold]
    R -->|/heavy 힌트| F[Fargate<br/>새로 띄움]
    R -->|기존 Fargate<br/>실행 중| FE[Fargate<br/>재사용]
    R -->|Lambda 실패| FB[Fargate<br/>fallback]

    L --> Done[✓]
    F --> Done
    FE --> Done
    FB --> Done

    style L fill:#90EE90
    style F fill:#FFE4B5
    style FE fill:#87CEEB
    style FB fill:#FFB6C1
```

코드: `packages/gateway/src/services/route-classifier.ts`

| 모드 | 콜드 | 비용 | 한계 |
|---|---|---|---|
| Lambda (기본) | 1.35s | $0/유휴 | **15분 timeout** |
| Fargate Spot | ~68s | $0/유휴 | 무제한 |
| 스마트 라우팅 | 둘 다 | 동일 | 자동 선택 |

## CDK Stacks 의존성

```mermaid
graph TD
    Secrets[SecretsStack<br/>SSM SecureString 5개]
    Network[NetworkStack<br/>VPC, no NAT]
    Storage[StorageStack<br/>5 DynamoDB + S3 + ECR]
    Auth[AuthStack<br/>Cognito User Pool]
    Compute[ComputeStack<br/>ECS Cluster + TaskDef]
    Lambda[LambdaAgentStack<br/>Container Function]
    Api[ApiStack<br/>API GW + 7 Lambdas]
    Web[WebStack<br/>S3 + CloudFront]
    Mon[MonitoringStack<br/>Dashboard + Alarms]

    Secrets --> Lambda
    Secrets --> Api
    Network --> Storage
    Network --> Compute
    Storage --> Compute
    Storage --> Lambda
    Storage --> Api
    Storage --> Web
    Auth --> Api
    Auth --> Web
    Compute --> Api
    Lambda --> Api
    Api --> Mon
    Web --> Mon

    style Secrets fill:#FFE4B5
    style Lambda fill:#90EE90
```

**배포 순서**:
1. SecretsStack (parameter 4개 주입 — 첫 1회만)
2. ECR repo `serverless-openclaw-lambda-agent` 생성 + 이미지 푸시
3. 나머지 `cdk deploy --all`

## 데이터 흐름 — Telegram 메시지

```mermaid
sequenceDiagram
    autonumber
    participant TG as Telegram
    participant API as API GW REST
    participant TGWH as telegram-webhook<br/>Lambda
    participant SSM as SSM Parameter
    participant LA as Lambda Agent<br/>Container
    participant S3 as S3
    participant DDB as DynamoDB
    participant BR as Bedrock Claude

    TG->>API: POST /telegram (메시지)
    API->>TGWH: invoke
    TGWH->>SSM: getParameters (decrypted)
    SSM-->>TGWH: bot token + secret
    TGWH->>TGWH: secret_token 검증
    TGWH->>DDB: 대화 이력 조회
    TGWH->>LA: invoke (메시지 + 컨텍스트)
    LA->>S3: 세션 로드 (sessions/{userId}/...)
    LA->>BR: invokeModel (Claude)
    BR-->>LA: 응답
    LA->>S3: 세션 저장
    LA->>DDB: 대화 저장
    LA-->>TGWH: 응답 텍스트
    TGWH->>TG: sendMessage
```

## DynamoDB 스키마

| Table | PK | SK | TTL | 용도 |
|---|---|---|---|---|
| Conversations | `USER#{userId}` | `CONV#{id}#MSG#{ts}` | ✓ | 메시지 이력 |
| Settings | `USER#{userId}` | `SETTING#{key}` | — | 사용자 설정 |
| TaskState | `USER#{userId}` | — | ✓ | Fargate task 상태 |
| Connections | `CONN#{connId}` | — | ✓ | WebSocket 연결 |
| PendingMessages | `USER#{userId}` | `MSG#{ts}#{uuid}` | ✓ | 콜드스타트 큐 |

전부 **PAY_PER_REQUEST** — 사용한 만큼만 과금.

## 보안 모델

```mermaid
graph LR
    User[👤 User] -->|JWT| Cognito[Cognito<br/>User Pool]
    Cognito -->|verified| WS[WS Connect Lambda]
    WS -->|userId| DDB

    TG[Telegram] -->|secret_token<br/>header| TGWH[telegram-webhook]
    TGWH -->|verify| SSM

    Lambda[Lambda Agent] -->|IAM Role| Bedrock
    Lambda -->|IAM Role| S3

    style Cognito fill:#FFE4B5
    style SSM fill:#FFB6C1
    style Bedrock fill:#FFD700
```

**원칙**:
- API key 절대 디스크 미저장 (SSM SecureString → 런타임 env)
- Server-side userId만 (IDOR 방지)
- Bridge Bearer token (모든 endpoint 인증)
- Cognito JWT (`aws-jwt-verify` 로 ws-connect 에서 검증)

## 추가 자료

- 원본 발표: [serithemage/serverless-openclaw](https://github.com/serithemage/serverless-openclaw)
- 상세 설계: 원본 `docs/architecture.md`, `docs/lambda-migration-journey.md`
