# Glassdeck

![Glassdeck Terminal Screenshot](.github/media/glassdeck-simulator.png)

[GhosttyKit](https://github.com/ghostty-org/ghostty) 기반의 iOS SSH 터미널 앱.

[English](README.md)

## Features

**Terminal & Shell**

- **SSH terminal sessions**: `GhosttyKit` 터미널 API를 통한 VT100/xterm 에뮬레이션.
- **PTY shell**: 런타임 리사이즈가 가능한 양방향 비동기 브리지 (SSHPTYBridge actor).
- **터미널 렌더링**: GhosttyKit 기반 렌더링 파이프라인 위에 Glassdeck 자체 표면 통합/생명주기 로직이 동작.
- **Render coalescing**: 빠른 상태 변경을 통합하기 위한 `scheduleRender()`와 UIKit `layoutSubviews` 배칭.
- **Local scrollback**: 기본 10,000줄, 1K–100K 설정 가능, Metal 가속 뷰포트 스크롤링.

**Connectivity**

- **Auto-reconnection**: 지수 백오프 (5회 시도, 1–30초 지연, 2배수), 일시적 vs 영구적 실패 분류.
- **Session persistence & restore**: UserDefaults에 JSON 스냅샷 저장, 포그라운드 시 자동 복원, 선택적 Core Location 백그라운드 유지.
- **Connection profiles**: JSON 영속성을 갖춘 CRUD, 비밀번호 또는 SSH 키 인증, 메모, 마지막 접속 날짜.
- **TOFU host key verification**: 키체인 기반 known_hosts, SHA-256 지문, 신규 자동 신뢰 / 불일치 거부.

**Input & Hardware**

- **Hardware keyboard**: 90개 이상의 UIKeyCommands (Ctrl+문자, 화살표, 기능 키, Tab, Escape, PageUp/Down, Home/End).
- **Touch/pointer input**: I-beam 커서가 있는 UIPointerInteraction, 전체 SGR 마우스 보고, 드래그 추적.
- **IME support** (Experimental): 마크된 텍스트 / 조합 중 플래그를 포함한 UITextInput.

**Advanced Tools**

- **External display routing**: 전용 씬 델리게이트, 원격 포인터 오버레이, 디스플레이 라우팅 피커.
- **Terminal settings**: 디스플레이 타겟별 프로필 (iPhone vs 외부 모니터), 8가지 색상 테마, 폰트 크기, 커서 스타일, 벨.

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
│   ├── Views/               모든 SwiftUI 뷰 (연결, 터미널, 설정 등)
│   └── Resources/           Assets.xcassets, AppIcon.icon
├── GlassdeckCore/           공유 라이브러리 — SSH, 터미널, 모델의 단일 진실 공급원(SSOT)
│   ├── Models/              ConnectionProfile, ConnectionStore, AppSettings, RemoteControlMode
│   ├── SSH/                 SSHConnectionManager, SSHPTYBridge, SSHAuthenticator,
│   │                        HostKeyVerifier, SSHReconnectManager, SSHKeyManager 등
│   └── Terminal/            GhosttyKitSurfaceIO, TerminalConfiguration (8개 테마), TerminalIO, 타입
├── Frameworks/              GhosttyKit.xcframework (로컬에서 materialize된 의존성)
├── GlassdeckApp.xcodeproj/  소스에 체크인된 네이티브 Xcode 프로젝트
├── Scripts/                 빌드, 실행, 테스트 자동화
├── Tools/
│   └── GlassdeckBuild/      Swift-native 호스트 러너 (빌드/테스트 오케스트레이션)
│       ├── Package.swift
│       └── Package.resolved
├── Tests/                   유닛, UI, 통합, 성능 테스트
├── Vendor/                  포크된 swift-ssh-client 의존성
├── Backlogs/                코드 리뷰 결과 및 백로그 추적
├── AGENTS.md                Codex 및 서브에이전트용 저장소 워크플로 규칙
├── LICENSE                  MIT
├── README.md                영문 문서
└── README-ko.md             한글 문서
```

## Architecture

```
SwiftUI Views (ConnectionListView, SessionTabView, TerminalContainerView)
       │
SessionManager (오케스트레이터 — @MainActor, 1082줄)
SessionLifecycleCoordinator (수명 주기 이벤트, 영속성, 복원)
       │
  ┌────┼────────────────┐
  │    │                 │
SSH Layer       Terminal UI        Input Layer
SSHConnectionManager  GhosttySurface (UIView)  KeyboardInputHandler
SSHAuthenticator      Metal renderer (CI)      PointerInputHandler
SSHPTYBridge          GhosttyKitSurfaceIO        SessionKeyboardInputHost
HostKeyVerifier       TerminalConfiguration    RemoteTrackpadCoordinator
SSHReconnectManager
       │
GlassdeckCore (공유 라이브러리 — 유일한 진실 공급원)
       │
외부: GhosttyKit · swift-ssh-client · SwiftNIO SSH · Swift Crypto
```

**Data flow**: 사용자 접속 → SSHConnectionManager 인증 (비밀번호/키) → HostKeyVerifier TOFU 확인 → PTY로 셸 오픈 → SSHPTYBridge가 셸↔터미널 양방향 브리지 → GhosttyKitSurfaceIO가 VT 스트림을 GhosttyKit로 전달 → GhosttySurface가 Metal로 렌더링 → 입력이 VT 인코딩을 통해 다시 셸로 흐름.

## Terminal Engine

- `GhosttyKitSurfaceIO.swift` — GhosttyKit 콜백과 터미널 I/O를 연결하는 Swift 어댑터.
- `GhosttyTerminalView.swift` — UIKit + Metal 터미널 서피스 래퍼와 입력 브리지.
- 터미널 동작은 `GhosttyKit`을 중심으로 동작합니다.
- 로컬로 materialize된 의존성 프레임워크는 관리되는 Ghostty 소스 상태와 동기화가 필요합니다.

## Vendored Ghostty Build

`Frameworks/GhosttyKit.xcframework` — 체크인 가능한 Xcode 프로젝트에서 참조되는 로컬 터미널 의존성입니다.
Gitignore로 관리되어 기본적으로 트래킹되지 않으며 필요 시 materialize됩니다.

관리되는 Ghostty 소스에서 다시 빌드/갱신:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build deps ghostty
```

Common profile:

- `--profile release-fast` (릴리스 유사 빌드)
- `--profile debug` (기본)

## Development

### Xcode 워크플로

체크인된 `GlassdeckApp.xcodeproj`를 `glassdeck-build` 런처로 사용합니다:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build build --scheme app
```

### 시뮬레이터에서 실행

iOS 시뮬레이터에서 빌드 & 실행:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build run --scheme app
```

### 테스트 실행

시뮬레이터에서의 유닛 테스트:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme unit
```

Docker 대상 라이브 SSH 통합 테스트 (컨테이너 자동 시작, 스모크 체크 먼저 실행):

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme unit --only-testing "GlassdeckAppTests/Integration.test"
```

라이브 Docker SSH 대상 터미널 렌더링 성능 테스트:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme ui --only-testing "GlassdeckAppUITests/TerminalPerformance"
```

애니메이션 렌더링 성능 테스트 (시뮬레이터):

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme ui --only-testing "GlassdeckAppUITests/Animation"
```

애니메이션 렌더링 성능 테스트 (기기) - `DEVICE_ID` 필요:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme ui --only-testing "GlassdeckAppUITests/Animation"
```

### UI 테스트 실행

스크린샷 캡처 + 아티팩트 내보내기가 포함된 UI 테스트:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme ui --only-testing "GlassdeckAppUITests/..."
```

애니메이션 렌더링 시각적 검증 (스크린샷 비교):

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme ui --only-testing "GlassdeckAppUITests/AnimationDemo"
```

### 테스트 유틸리티

러너가 내보낸 최신 결과 및 아티팩트 조회:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build artifacts --command build
swift run --package-path Tools/GlassdeckBuild glassdeck-build artifacts --command test
```

### 공통 플래그

| Flag                    | Description                                          |
| ----------------------- | ---------------------------------------------------- |
| `--worker <id>`         | 병렬 실행 시 아티팩트 디렉터리 분리                   |
| `--scheme <name>`       | 빌드/실행/테스트 스킴 선택 (`app`, `unit`, `ui`)       |
| `--simulator <name>`    | 실행/테스트 대상 시뮬레이터 지정 (`iPhone 17`)       |
| `--dry-run`             | 생성된 명령만 출력                                   |
| `--only-testing <target>` | 특정 테스트 타겟만 xcodebuild 전달                  |

### 시뮬레이터 타겟

기본값: 최신 iOS 런타임의 `iPhone 17`. `SIMULATOR_ID=<udid>`로 재정의 가능.

### 빌드 아티팩트

- `.build/glassdeck-build/logs/<command>/` — raw 명령 로그
- `.build/glassdeck-build/results/<command>/` — xcresult 번들
- `.build/glassdeck-build/artifacts/<command>/latest/` — 최신 내보내기 결과와 요약
- `.build/glassdeck-build/derived-data/<worker>/` — 워커별 DerivedData 재사용

**Note**: `GlassdeckApp.xcodeproj`는 소스에 체크인되므로 더 이상 xcodegen 재생성 단계가 필요하지 않습니다.

## Docker SSH Test Target

정식 라이브 테스트 엔드포인트 (별도의 Raspberry Pi 대체).

**Requirements**: Mac용 Docker Desktop.

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build docker up
swift run --package-path Tools/GlassdeckBuild glassdeck-build docker down
```

- **Port**: 22222 (기본값)
- **User**: glassdeck
- **Auth**: 비밀번호 + 키 모두 활성화됨

**Seeded home directory**:

- `~/bin/health-check.sh`
- `~/testdata/preview.txt`
- `~/testdata/nested/dir/info.txt`
- `~/testdata/nano-target.txt`
- `~/upload-target/`

**Note**: 물리 iPhone 테스트를 위해서는 iPhone과 Mac이 동일한 LAN에 있어야 합니다.

## Manual Smoke Checklist

1.  Docker SSH 시작: `swift run --package-path Tools/GlassdeckBuild glassdeck-build docker up`
2.  또는 전체 제품군 실행: `swift run --package-path Tools/GlassdeckBuild glassdeck-build test --scheme unit --only-testing "GlassdeckAppTests/Integration.test"`
3.  시뮬레이터 또는 iPhone에서 앱 실행
4.  출력된 호스트/포트로 프로필 생성, 비밀번호 인증으로 연결
5.  두 번째 프로필 생성 또는 SSH 키 인증으로 전환
6.  `~/bin/health-check.sh`, `pwd`, `ls ~/testdata` 실행
7.  렌더링, 타이핑, 붙여넣기, 특수 키, 리사이즈, 연결 해제, 재연결 확인
8.  외부 모니터 + 물리 키보드 연결 시: 세션 라우팅, 마우스/커서 모드 테스트, 두 손가락 스크롤, 로컬 터미널 보기, `nano --mouse ~/testdata/nano-target.txt`를 검증

## Dependencies

| Dependency       | Source                                             | Purpose                   |
| ---------------- | -------------------------------------------------- | ------------------------- |
| GhosttyKit       | `Frameworks/GhosttyKit.xcframework` (로컬 materialize, 미추적) | 터미널 + 렌더링 엔진        |
| swift-ssh-client | Vendor/ (fork)       | 고수준 SSH 클라이언트     |
| swift-nio-ssh    | SPM (≥0.9.0)         | 저수준 SSH 프로토콜       |
| swift-nio        | SPM (≥2.65.0)        | 비동기 네트워킹           |
| Swift Crypto     | (via NIO SSH)        | Ed25519/P256 키, SHA-256  |
| Core Location    | System               | 선택적 백그라운드 유지    |

## Notes

- GlassdeckCore는 공유 SSH, 키, 모델 및 터미널 로직의 유일한 진실 공급원(SSOT)입니다.
- 터미널 구현은 GhosttyKit을 중심으로 동작하며, 로컬 의존성 아티팩트를 사용합니다.
- `glassdeck-build deps ghostty`로 필요 시 터미널 의존성 아티팩트를 갱신합니다.
- Docker SSH 서버는 정식 인수(acceptance) 타겟입니다.

## License

MIT — [LICENSE](LICENSE) 참조.
