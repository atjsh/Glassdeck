# Glassdeck

[English](README.md) | 한국어

Glassdeck는 SwiftUI로 작성된 실험적인 iOS 26용 SSH 클라이언트입니다. 이 저장소는 iPhone 중심의 터미널 경험을 목표로 하며, 세션 관리, 외부 디스플레이 라우팅, 하드웨어 입력 지원, 그리고 온디바이스 AI 기능을 위한 훅을 포함합니다.

## 개요

- 연결 관리와 다중 세션 터미널 흐름을 위한 SwiftUI 앱 구조
- `swift-nio-ssh`와 `swift-ssh-client` 위에 구성된 SSH 연결 및 세션 스캐폴딩
- 외부 디스플레이 scene 지원, keyboard/pointer input handler, terminal configuration model
- Foundation Models 통합을 염두에 둔 AI assistant UI 및 서비스 placeholder

## 주요 내용

### 현재 저장소에 포함된 것

- 검색, 생성/수정 흐름, `UserDefaults` 기반 로컬 저장을 포함한 연결 프로필 관리
- connect, open shell, disconnect, multi-session routing을 담당하는 session management
- 전용 routing picker와 별도 terminal view를 갖춘 external display scene 지원
- 테마, font size, cursor style, scrollback 설정을 위한 terminal configuration model
- Keychain 기반 SSH key storage helper와 password/key auth model
- 메인 앱 셸에 연결된 help browser와 AI assistant sheet

### 준비 중이거나 부분 구현 상태

- `GhosttyKit` 통합은 `Glassdeck/Terminal/GhosttyTerminalView.swift`에 스캐폴딩되어 있지만, 이 저장소에는 framework가 포함되어 있지 않고 bridge 코드는 아직 주석 처리되어 있습니다
- Foundation Models 기반 AI는 아직 활성화되어 있지 않으며, `AIAssistant`는 통합이 완료될 때까지 placeholder 응답을 반환합니다
- PTY resize 처리, host key verification wiring, SSH key import/export UX 일부 등 몇몇 SSH/terminal 동작은 아직 TODO 상태입니다
- 현재 persistence는 `UserDefaults`를 사용하며, 코드 주석에는 이후 SwiftData로 옮길 계획이 남아 있습니다

## 현재 상태

- 완성된 프로덕션 클라이언트가 아닌 public work in progress 상태입니다
- 현재 코드베이스 작업에는 Xcode 26과 iOS 26 SDK가 필요합니다
- 지원되는 개발 흐름은 package를 Xcode에서 열고 iOS target으로 실행하는 방식입니다
- `swift build`는 아직 기본 지원 경로가 아닙니다. 현재 CLI 빌드에서는 SSH dependency와의 platform compatibility 문제로 실패합니다
- GhosttyKit, Foundation Models 같은 선택적 통합은 추가 설정이나 미완성 구현이 필요합니다

## 요구 사항

- Xcode 26 beta와 iOS 26 SDK가 설치된 macOS 환경
- 현재 제품 방향 기준으로 iPhone 15 Pro를 주 대상 기기로 가정
- 온디바이스 AI 경로를 완성하고 테스트하려면 Apple Intelligence 지원 하드웨어 필요
- Ghostty 기반 terminal integration을 작업하려면 선택적으로 `GhosttyKit.xcframework` 필요

## 빌드 및 실행

이 저장소는 Xcode 중심 워크플로를 기본으로 사용해야 합니다.

```bash
git clone git@github-atjsh:atjsh/Glassdeck
cd Glassdeck
swift package resolve
open Package.swift
```

그다음:

1. Xcode 26에서 package를 엽니다.
2. iOS 26 대상 기기를 선택합니다.
3. Xcode에서 build/run 합니다.

CLI 빌드를 위한 package platform metadata가 정리되기 전까지는 `swift build`를 기본 검증 단계로 간주하지 않는 편이 맞습니다.

### 선택적 GhosttyKit 설정

Ghostty 기반 terminal 경로를 이어서 작업하려면:

1. [Ghostty](https://github.com/ghostty-org/ghostty)에서 `./macos/build.nu --scheme Ghostty-iOS --configuration Release --action build`로 `GhosttyKit.xcframework`를 빌드합니다.
2. 생성된 framework를 `Frameworks/`에 배치합니다.
3. `Glassdeck/Terminal/GhosttyTerminalView.swift`에서 `import GhosttyKit`과 관련 bridge 코드를 활성화합니다.
4. vendored framework 기준으로 terminal surface lifecycle과 rendering 경로를 검증합니다.

## 아키텍처 개요

```text
Glassdeck/
├── App/        App entry point, app delegate, Info.plist
├── Scenes/     Main and external display scene delegate
├── Views/      Connection, terminal UI, settings, help를 위한 SwiftUI 흐름
├── Models/     Connection profile, app setting, session state
├── SSH/        Connection lifecycle, auth, PTY bridge, key storage
├── Terminal/   Terminal surface wrapper, configuration, protocol
├── Input/      Keyboard 및 pointer input handling
└── AI/         AI assistant actor와 overlay UI scaffolding
```

## 로드맵 / 알려진 공백

- GhosttyKit rendering bridge를 완성하고 placeholder terminal 동작을 제거
- AI placeholder 응답을 실제 Foundation Models availability check와 generation flow로 교체
- Host key verification wiring, terminal resize request, richer key import/export UX 등 SSH 완성도 향상
- CLI 빌드를 문서화 가능한 지원 경로로 만들 수 있도록 package metadata 재정비
- `UserDefaults` 기반 persistence를 SwiftData로 옮길지 재평가

## 라이선스

MIT입니다. 자세한 내용은 [LICENSE](LICENSE)를 확인하세요.
