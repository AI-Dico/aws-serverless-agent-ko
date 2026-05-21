#!/usr/bin/env bash
# 사전 요구사항 점검 — 실패하면 어떤 도구를 설치해야 하는지 알려줌
set -euo pipefail

green() { printf '\033[32m✓\033[0m %s\n' "$1"; }
red()   { printf '\033[31m✗\033[0m %s — %s\n' "$1" "$2"; }

fail=0

# Node 22+
if command -v node >/dev/null 2>&1; then
  v=$(node -v | sed 's/v//')
  major=${v%%.*}
  if [ "$major" -ge 22 ]; then green "Node $v"; else red "Node $v" "22 이상 필요. brew install node@22"; fail=1; fi
else
  red "Node" "미설치. brew install node@22"; fail=1
fi

# npm 10+
if command -v npm >/dev/null 2>&1; then
  v=$(npm -v); green "npm $v"
else
  red "npm" "Node 와 함께 설치됨"; fail=1
fi

# Docker
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    green "Docker daemon running"
  else
    red "Docker" "데몬 미실행. Docker Desktop 또는 colima start"; fail=1
  fi
else
  red "Docker" "미설치. brew install --cask docker"; fail=1
fi

# AWS CLI v2
if command -v aws >/dev/null 2>&1; then
  v=$(aws --version 2>&1 | awk '{print $1}')
  green "$v"
else
  red "AWS CLI" "미설치. brew install awscli"; fail=1
fi

# CDK
if command -v cdk >/dev/null 2>&1; then
  v=$(cdk --version 2>&1)
  green "CDK $v"
else
  red "AWS CDK" "미설치. npm install -g aws-cdk"; fail=1
fi

# Git
if command -v git >/dev/null 2>&1; then
  green "$(git --version)"
else
  red "git" "미설치"; fail=1
fi

if [ $fail -eq 0 ]; then
  printf '\n\033[32m모든 사전요구사항 통과\033[0m — 다음: ./scripts/01-aws-configure.sh\n'
  exit 0
else
  printf '\n\033[31m누락된 도구 설치 후 다시 실행\033[0m\n'
  exit 1
fi
