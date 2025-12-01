# Project Moa

지라(Jira) 이슈를 수집하여 에픽/버전별로 정리된 연말 회고 리포트를 생성하는 도구입니다.

## 프로젝트 소개

Project Moa는 Swift Vapor와 Leaf를 사용해 만든 Jira 연말 회고용 리포터 웹 애플리케이션입니다. 팀의 한 해 동안의 작업 내역을 Jira에서 수집하고, 에픽 및 버전별로 정리하여 시각적인 연말 회고 리포트를 생성합니다.

## 주요 기능

- **연말 통계 시각화**: 한 해 동안의 작업 통계를 시각적으로 확인할 수 있습니다.
- **에픽별 작업 내역 리포팅**: 에픽 단위로 완료된 작업들을 정리하여 보여줍니다.
- **버전별 작업 내역 리포팅**: 릴리즈 버전별로 작업 내역을 분류하여 제공합니다.

## 기술 스택

- **Swift**: 서버 사이드 로직 구현
- **Vapor**: Swift 기반 웹 프레임워크
- **Leaf**: Vapor의 템플릿 엔진

## 설치 및 실행 방법

### 요구 사항

- Swift 5.9 이상
- macOS 또는 Linux

### 설치

1. 저장소를 클론합니다:
   ```bash
   git clone https://github.com/kyuhyeonKurly/moa.git
   cd moa
   ```

2. 의존성을 설치합니다:
   ```bash
   swift package resolve
   ```

### 실행

개발 모드로 실행:
```bash
swift run
```

릴리즈 빌드로 실행:
```bash
swift build -c release
.build/release/App
```

### 환경 변수 설정

`.env` 파일을 생성하여 필요한 환경 변수를 설정합니다:
```
JIRA_BASE_URL=https://your-jira-instance.atlassian.net
JIRA_USERNAME=your-email@example.com
JIRA_API_TOKEN=your-api-token
```
