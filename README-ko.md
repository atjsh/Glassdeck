# Glassdeck

![Glassdeck Terminal Screenshot](.github/media/glassdeck-simulator.png)

실제 터미널 엔진을 탑재한 iOS 26 SSH 클라이언트.

[English](README.md)

## Features

**Terminal & Shell**
*   **SSH terminal sessions**: `libghostty-vt` (GhosttyTerminal, GhosttyRenderState, key/mouse encoders)를 통한 완전한 VT100/xterm 에뮬레이션.
*   **PTY shell**: 런타임 리사이즈가 가능한 양방향 비동기 브리지 (SSHPTYBridge actor).
*   **Glassdeck-owned Metal renderer**: Core Image 기반, GhosttyKit에 의존하지 않음.
*   **Render coalescing**: 빠른 상태 변경을 통합하기 위한 `scheduleRender()`와 UIKit `layoutSubviews` 배칭.
*   **Local scrollback**: 기본 10,000줄, 1K–100K 설정 가능, Metal 가속 뷰포트 스크롤링.

**Connectivity**
*   **Auto-reconnection**: 지수 백오프 (5회 시도, 1–30초 지연, 2배수), 일시적 vs 영구적 실패 분류.
*   **Session persistence & restore**: UserDefaults에 JSON 스냅샷 저장, 포그라운드 시 자동 복원, 선택적 Core Location 백그라운드 유지.
*   **Connection profiles**: JSON 영속성을 갖춘 CRUD, 비밀번호 또는 SSH 키 인증, 메모, 마지막 접속 날짜.
*   **TOFU host key verification**: 키체인 기반 known_hosts, SHA-256 지문, 신규 자동 신뢰 / 불일치 거부.

**Input & Hardware**
*   **Hardware keyboard**: 90개 이상의 UIKeyCommands (Ctrl+문자, 화살표, 기능 키, Tab, Escape, PageUp/Down, Home/End).
*   **Touch/pointer input**: I-beam 커서가 있는 UIPointerInteraction, 전체 SGR 마우스 보고, 드래그 추적.
*   **IME support** (Experimental): 마크된 텍스트 / 조합 중 플래그를 포함한 UITextInput.

**Advanced Tools**
*   **SFTP**: 탐색, 미리보기 (UTF-8, 기본 8KB), 업로드, 삭제, 다운로드, iOS 공유 시트 내보내기.
*   **External display routing**: 전용 씬 델리게이트, 원격 포인터 오버레이, 디스플레이 라우팅 피커.
*   **Terminal settings**: 디스플레이 타겟별 프로필 (iPhone vs 외부 모니터), 8가지 색상 테마, 폰트 크기, 커서 스타일, 벨.

## Repository Layout

```
Glassdeck/
├── Glassdeck/               iOS 앱: SwiftUI 뷰, UIKit 터미널 서피스, 입력 처리
│   ├── App/                 앱 진입점, 환경, 델리게이트, 애니메이션 데모
│   ├── Input/               키보드, 포인터, IME 입력 조정
│   ├── Models/              세션 관리, 영속성, 자격 증명, 백그라운드 유지
│   ├── Remote/              외부 디스플레이 지오메트리, 원격 트랙패드 조정
│   ├── Scenes/              메인 + 외부 디스플레이 씬 델리게이트
│   ├── SSH/                 SSH 세션 관찰 가능 모델
│   ├── Terminal/            GhosttySurface UIView, Metal 렌더러, SwiftUI 래퍼
│   ├── Views/               모든 SwiftUI 뷰 (연결, 터미널, SFTP, 설정 등)
│   └── Resources/           Assets.xcassets, AppIcon.icon
├── GlassdeckCore/           공유 라이브러리 — SSH, 터미널, 모델의 단일 진실 공급원(SSOT)
│   ├── Models/              ConnectionProfile, ConnectionStore, AppSettings, RemoteControlMode
│   ├── SSH/                 SSHConnectionManager, SFTPManager, SSHPTYBridge, SSHAuthenticator,
│   │                        HostKeyVerifier, SSHReconnectManager, SSHKeyManager 등
│   └── Terminal/            GhosttyVTBindings, TerminalConfiguration (8개 테마), TerminalIO, 타입
├── Frameworks/              Vendored CGhosttyVT.xcframework (정적 라이브러리, iOS 기기 + 시뮬레이터)
├── GlassdeckApp.xcodeproj/  생성된 Xcode 프로젝트 (project.yml에서 xcodegen으로 생성)
├── Scripts/                 빌드, 실행, 테스트 자동화
├── Tests/                   유닛, UI, 통합, 성능 테스트
├── Vendor/                  포크된 swift-ssh-client 의존성
├── Backlogs/                코드 리뷰 결과 및 백로그 추적
├── Package.swift            SPM 매니페스트 (swift-tools-version: 6.2)
├── project.yml              xcodegen 프로젝트 정의
├── LICENSE                  MIT
├── README.md                영문 문서
└── README-ko.md             한글 문서
```

## Architecture

```
SwiftUI Views (ConnectionListView, SessionTabView, TerminalContainerView, SFTPBrowserView)
       │
SessionManager (오케스트레이터 — @MainActor, 1082줄)
SessionLifecycleCoordinator (수명 주기 이벤트, 영속성, 복원)
       │
  ┌────┼────────────────┐
  │    │                 │
SSH Layer       Terminal UI        Input Layer
SSHConnectionManager  GhosttySurface (UIView)  KeyboardInputHandler
SSHAuthenticator      Metal renderer (CI)      PointerInputHandler
SSHPTYBridge          GhosttyVTBindings        SessionKeyboardInputHost
HostKeyVerifier       TerminalConfiguration    RemoteTrackpadCoordinator
SSHReconnectManager
SFTPManager
       │
GlassdeckCore (공유 라이브러리 — 유일한 진실 공급원)
       │
외부: libghostty-vt (C) · swift-ssh-client · SwiftNIO SSH · Swift Crypto
```

**Data flow**: 사용자 접속 → SSHConnectionManager 인증 (비밀번호/키) → HostKeyVerifier TOFU 확인 → PTY로 셸 오픈 → SSHPTYBridge가 셸↔터미널 양방향 브리지 → GhosttyVTBindings가 VT 시퀀스 처리 → GhosttySurface가 Metal로 렌더링 → 입력이 VT 인코딩을 통해 다시 셸로 흐름.

## Terminal Engine

*   `GhosttyVTBindings.swift` (1,217 lines) — GhosttyTerminal, GhosttyRenderState, 키 인코더, 마우스 인코더 소유.
*   `GhosttyVTTypes.swift` — 순수 Swift 렌더 프로젝션 및 입력 디스크립터 타입.
*   `GhosttyTerminalView.swift` — UIView + CAMetalLayer, Core Image Metal 렌더러, UIKit 입력 브리지.
*   렌더러는 Glassdeck 소유입니다. 이 저장소는 GhosttyKit에 의존하지 않습니다.
*   VT C API는 업스트림 WIP입니다. 벤더링된 static xcframework는 동기화 상태를 유지해야 합니다.

## Vendored Ghostty Build

`Frameworks/CGhosttyVT.xcframework` — 정적 라이브러리, 저장소에 커밋됨.

로컬 Ghostty 체크아웃에서 다시 빌드:
```bash
./Scripts/build-cghosttyvt.sh
```

**Defaults**:
*   Device: aarch64-ios
*   Simulator ARM64: aarch64-ios-simulator -Dcpu=apple_a17
*   Optional x86_64 simulator: INCLUDE_X86_64_SIMULATOR=true
*   SIMD: 비활성화 (순수 정적, 기기 안전)
*   Requires: Zig 0.15.2+, xcodebuild, Ghostty 소스

## Development

### Xcode 프로젝트 재생성

`project.yml`에서 xcodegen을 통해 Xcode 프로젝트 생성:

```bash
./Scripts/generate-xcodeproj.sh
```

또한 `patch-local-package-product.py`를 통해 로컬 SPM 패키지 + 리소스를 연결하도록 생성된 .pbxproj를 패치합니다.

### 시뮬레이터에서 실행

iOS 시뮬레이터에서 빌드 & 실행:

```bash
./Scripts/run-ios-sim.sh
```

테스트 픽스처와 함께 애니메이션 데모 모드로 실행:

```bash
./Scripts/run-animation-demo-sim.sh
```

### 테스트 실행

시뮬레이터에서의 유닛 테스트:

```bash
./Scripts/test-ios-sim.sh
```

Docker 대상 라이브 SSH 통합 테스트 (컨테이너 자동 시작, 스모크 체크 먼저 실행):

```bash
./Scripts/test-live-docker-ssh.sh
```

라이브 Docker SSH 대상 터미널 렌더링 성능 테스트:

```bash
./Scripts/test-docker-render-perf.sh
```

애니메이션 렌더링 성능 테스트 (시뮬레이터):

```bash
./Scripts/test-animation-render-sim.sh
```

애니메이션 렌더링 성능 테스트 (기기) - `DEVICE_ID` 필요:

```bash
./Scripts/test-animation-render-device.sh
```

### UI 테스트 실행

스크린샷 캡처 + 아티팩트 내보내기가 포함된 UI 테스트:

```bash
./Scripts/test-docker-ui-sim.sh
```

애니메이션 렌더링 시각적 검증 (스크린샷 비교):

```bash
./Scripts/test-animation-demo-visible-sim.sh
```

### 테스트 유틸리티

스크린샷 테스트 아티팩트 검토를 위한 로컬 웹 UI:

```bash
./Scripts/view-test-artifacts.py
```

### 공통 플래그

| Flag | Description |
|------|-------------|
| `--clean`, `--rebuild` | 빌드 그래프 초기화 강제 |
| `--verbose` | raw xcodebuild 스트림 활성화 (`GLASSDECK_VERBOSE=1`) |
| `--only-testing TARGET` | 특정 테스트 타겟 실행 |

### 시뮬레이터 타겟

기본값: 최신 iOS 런타임의 `iPhone 17`. `SIMULATOR_ID=<udid>`로 재정의 가능.

### 빌드 아티팩트

*   `.build/TestLogs/` — raw xcodebuild 로그
*   `.build/TestResults/` — xcresult 번들
*   `.build/TestArtifacts/docker-ui/` — UI 스크린샷 내보내기

**Note**: `project.yml`이 프로젝트보다 최신이면 스크립트가 `generate-xcodeproj.sh`를 통해 자동으로 재생성합니다.

## Docker SSH Test Target

정식 라이브 테스트 엔드포인트 (별도의 Raspberry Pi 대체).

**Requirements**: Mac용 Docker Desktop.

```bash
./Scripts/docker/start-test-ssh.sh
./Scripts/docker/stop-test-ssh.sh
```

*   **Port**: 22222 (기본값)
*   **User**: glassdeck
*   **Auth**: 비밀번호 + 키 모두 활성화됨

**Seeded home directory**:
*   `~/bin/health-check.sh`
*   `~/testdata/preview.txt`
*   `~/testdata/nested/dir/info.txt`
*   `~/testdata/nano-target.txt`
*   `~/upload-target/`

**Note**: 물리 iPhone 테스트를 위해서는 iPhone과 Mac이 동일한 LAN에 있어야 합니다.

## Manual Smoke Checklist

1.  Docker SSH 시작: `./Scripts/docker/start-test-ssh.sh`
2.  또는 전체 제품군 실행: `./Scripts/test-live-docker-ssh.sh`
3.  시뮬레이터 또는 iPhone에서 앱 실행
4.  출력된 호스트/포트로 프로필 생성, 비밀번호 인증으로 연결
5.  두 번째 프로필 생성 또는 SSH 키 인증으로 전환
6.  `~/bin/health-check.sh`, `pwd`, `ls ~/testdata` 실행
7.  렌더링, 타이핑, 붙여넣기, 특수 키, 리사이즈, 연결 해제, 재연결 확인
8.  SFTP 브라우저 열기 → testdata 탐색, 미리보기, 업로드, 삭제
9.  외부 모니터 + 물리 키보드 연결 시: 세션 라우팅, 마우스/커서 모드 테스트, 두 손가락 스크롤, 로컬 터미널 보기, `nano --mouse ~/testdata/nano-target.txt`를 검증

## Dependencies

| Dependency | Source | Purpose |
|-----------|--------|---------|
| libghostty-vt | Vendored xcframework | 터미널 VT 에뮬레이션 엔진 |
| swift-ssh-client | Vendor/ (fork) | 고수준 SSH 클라이언트 |
| swift-nio-ssh | SPM (≥0.9.0) | 저수준 SSH 프로토콜 |
| swift-nio | SPM (≥2.65.0) | 비동기 네트워킹 |
| Swift Crypto | (via NIO SSH) | Ed25519/P256 키, SHA-256 |
| Core Location | System | 선택적 백그라운드 유지 |

## Notes

*   GlassdeckCore는 공유 SSH, 키, 모델 및 터미널 로직의 유일한 진실 공급원(SSOT)입니다.
*   Metal 렌더러는 Glassdeck 소유이며 GhosttyKit에 의존하지 않습니다.
*   VT C API는 업스트림 WIP이므로 벤더링된 xcframework + 빌드 스크립트의 동기화를 유지해야 합니다.
*   Docker SSH 서버는 정식 인수(acceptance) 타겟입니다.

## License

MIT — [LICENSE](LICENSE) 참조.
