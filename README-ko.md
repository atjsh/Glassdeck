# Glassdeck

Glassdeck는 공용 Swift 코어와 생성된 Xcode 앱 타깃으로 구성된 iOS 26용 SSH 클라이언트입니다. 현재 리비전은 실제 `libghostty-vt` 백엔드, Glassdeck 자체 Metal 렌더러, PTY 지원 SSH shell, 그리고 확장 중인 SFTP 워크플로를 포함합니다.

## 현재 범위

- `libghostty-vt` 기반 SSH 터미널 세션
- vendored `swift-ssh-client`를 통한 PTY shell 생성 및 runtime resize
- 외부 디스플레이 라우팅
- 하드웨어 키보드, 터치, focus, paste, 로컬 scrollback 처리
- SFTP 디렉터리 브라우징, 텍스트 preview, 업로드, 삭제, export

## 저장소 구조

```text
Glassdeck/
├── Glassdeck/            iOS 앱 셸, SwiftUI 뷰, UIKit 터미널 surface
├── GlassdeckCore/        공용 모델, SSH, 터미널 바인딩, SFTP
├── Frameworks/           vendored CGhosttyVT xcframework
├── GlassdeckApp.xcodeproj 시뮬레이터/디바이스 실행용 생성된 iOS 앱 프로젝트
├── Scripts/              Ghostty 패키징, 시뮬레이터 실행, Docker SSH 타깃
├── Tests/                iOS 시뮬레이터 XCTest 소스
└── Vendor/               포크한 swift-ssh-client dependency
```

## 터미널 아키텍처

- `GlassdeckCore/Terminal/GhosttyVTBindings.swift`가 `GhosttyTerminal`, `GhosttyRenderState`, key encoder, mouse encoder를 소유합니다.
- `GlassdeckCore/Terminal/GhosttyVTTypes.swift`는 순수 Swift render projection과 input descriptor 타입을 정의합니다.
- `Glassdeck/Terminal/GhosttyTerminalView.swift`는 `CAMetalLayer` 기반 UIKit surface와 Core Image 기반 Metal 렌더러, UIKit 입력 브리지를 포함합니다.
- `GlassdeckCore/SSH/SSHPTYBridge.swift`는 계속 UI-agnostic PTY bridge 역할을 수행합니다.

## Ghostty 아티팩트 갱신

`Frameworks/CGhosttyVT.xcframework`는 Apple 플랫폼용 static library 아티팩트로 저장소에 포함되어 있습니다. 로컬 Ghostty checkout으로 다시 만들려면:

```bash
./Scripts/build-cghosttyvt.sh
```

기본값:

- device target: `aarch64-ios`
- simulator target: `aarch64-ios-simulator -Dcpu=apple_a17`
- 선택적 Intel simulator slice: `INCLUDE_X86_64_SIMULATOR=true`
- VT 패키징 방식: runtime framework embed가 없는 static xcframework
- SIMD: iOS용 vendored 빌드는 pure-static, device-safe 아카이브를 위해 기본적으로 비활성화

## 개발

### Xcode 프로젝트 다시 생성

```bash
./Scripts/generate-xcodeproj.sh
```

### 표준 iOS 시뮬레이터 실행

```bash
./Scripts/run-ios-sim.sh
./Scripts/run-ios-sim.sh --clean
```

### 시뮬레이터 XCTest 실행

```bash
./Scripts/test-ios-sim.sh
./Scripts/test-ios-sim.sh --clean
```

직접 `xcodebuild` 플래그를 조합하지 않고 단일 테스트만 실행하려면:

```bash
./Scripts/test-ios-sim.sh --only-testing GlassdeckAppTests/RemoteControlStateTests
```

### Docker SSH 라이브 통합 테스트 실행

```bash
./Scripts/test-live-docker-ssh.sh
```

### Docker UI 스크린샷 테스트 실행

```bash
./Scripts/test-docker-ui-sim.sh
```

### 표준 라이브 SSH 테스트 타깃 시작

```bash
./Scripts/docker/start-test-ssh.sh
```

호스트 측 스모크 검증이 필요하면:

```bash
./Scripts/docker/smoke-test-ssh.sh
```

Docker 타깃을 중지하려면:

```bash
./Scripts/docker/stop-test-ssh.sh
```

로그를 함께 보고 싶다면:

```bash
./Scripts/run-ios-sim.sh --logs
```

시뮬레이터 실행과 XCTest 스크립트는 기본적으로 증분 빌드를 사용합니다. 깨끗한 빌드 그래프가 필요하면 `--clean` 또는 `--rebuild`를 사용하세요. 각 XCTest 실행은 raw `xcodebuild` 로그를 `.build/TestLogs/`에, `xcresult` 번들을 `.build/TestResults/`에 저장합니다.

기존처럼 raw `xcodebuild` 스트림이 필요하면 `--verbose` 또는 `GLASSDECK_VERBOSE=1`을 사용하면 됩니다.

```bash
./Scripts/test-ios-sim.sh --verbose
./Scripts/run-ios-sim.sh --verbose
GLASSDECK_VERBOSE=1 ./Scripts/test-live-docker-ssh.sh
```

기본 시뮬레이터 타깃은 최신 설치 iOS runtime의 `iPhone 17`입니다.

시뮬레이터 실행 경로는 생성된 `GlassdeckApp.xcodeproj`와 `GlassdeckApp` scheme을 사용합니다. 시뮬레이터 단위 테스트 스크립트는 기본적으로 `GlassdeckAppUnit`, Docker UI 스크린샷 스크립트는 `GlassdeckAppUI`를 사용하므로 unit-only 실행에서 `GlassdeckAppUITests`를 다시 컴파일하지 않습니다. 특정 시뮬레이터를 직접 지정하려면 `SIMULATOR_ID`를 설정하고, 그렇지 않으면 스크립트가 사용 가능한 최신 `iPhone 17`을 자동으로 선택합니다. `project.yml`이 더 최신이면 저장소 스크립트가 `./Scripts/generate-xcodeproj.sh`로 프로젝트를 다시 생성합니다.

현재 Glassdeck의 지원 플랫폼은 iOS만입니다. 기본 개발 경로는 생성된 Xcode 프로젝트와 위의 시뮬레이터 스크립트입니다.

## Docker SSH 테스트 타깃

이제 Glassdeck의 표준 라이브 테스트 엔드포인트는 별도 Raspberry Pi가 아니라 저장소 안의 Docker SSH 서버입니다.

- 저장소를 실행하는 Mac에 Docker Desktop이 필요합니다.
- 기본적으로 OpenSSH를 `22222` 포트로 공개합니다.
- 동일한 `glassdeck` 사용자에 대해 비밀번호 인증과 SSH 키 인증을 모두 지원합니다.
- 홈 디렉터리에 다음 테스트 데이터를 고정으로 시드합니다.
  - `~/bin/health-check.sh`
  - `~/testdata/preview.txt`
  - `~/testdata/nested/dir/info.txt`
  - `~/testdata/nano-target.txt`
  - `~/upload-target/`

`./Scripts/docker/start-test-ssh.sh`는 Glassdeck에서 그대로 사용할 host, port, username, password, SSH private-key 경로와 현재 host-key fingerprint를 출력합니다. 물리 iPhone 테스트에서는 Docker를 실행하는 Mac과 iPhone이 같은 LAN에 있어야 합니다.

## 수동 스모크 체크리스트

- `./Scripts/docker/start-test-ssh.sh`로 Docker SSH 타깃 시작
- 또는 `./Scripts/test-live-docker-ssh.sh`로 Docker 타깃 기동, 호스트 스모크 검증, `iPhone 17`용 live `SSHConnectionManager` XCTest를 한 번에 실행
- 시뮬레이터 또는 물리 iPhone에서 앱 실행
- 출력된 host/port로 연결 프로필을 만들고 비밀번호 인증으로 접속
- 두 번째 프로필을 만들거나 인증 방식을 바꿔 SSH 키 인증으로도 접속
- 터미널에서 `~/bin/health-check.sh`, `pwd`, `ls ~/testdata`를 실행해 로그인과 명령 실행을 확인
- 터미널 렌더링, 입력, paste, 특수 키, resize, disconnect, reconnect 확인
- 터미널 툴바에서 SFTP 브라우저를 열고 `~/testdata` 탐색, `preview.txt` preview, `~/upload-target` 업로드, 업로드한 파일 삭제 확인
- 외부 모니터와 물리 키보드가 연결된 상태에서 active session을 외부 디스플레이로 라우팅하고 `Mouse` 모드, `Cursor` 모드, 두 손가락 스크롤, `View Local Terminal`, `nano --mouse ~/testdata/nano-target.txt`를 검증

## 참고

- 공용 SSH, key, model, terminal 로직의 기준 구현은 `GlassdeckCore`입니다.
- 렌더러는 Glassdeck 소유 구현이며 `GhosttyKit`에 의존하지 않습니다.
- upstream VT C API는 아직 변경 가능성이 있으므로 vendored static xcframework와 빌드 스크립트를 같이 관리해야 합니다.
- Docker SSH 서버가 비밀번호 인증, SSH 키 인증, SFTP, 외부 디스플레이 수동 검증의 기준 타깃입니다.
