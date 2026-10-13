# Agent Meter

Codex, Claude Code, Antigravity의 **계정 잔여 한도**를 보여주는 한국어 macOS 메뉴 막대 앱입니다. Swift / SwiftUI / AppKit으로 직접 구현했습니다. 사용량 연결에는 각 서비스의 CLI 또는 앱 로그인 정보가 필요합니다.

## 다운로드

**[macOS 설치 ZIP 다운로드](https://github.com/carter51200/agent-meter/releases/download/v0.3.0/Agent-Meter.zip)** · [릴리스 안내](https://github.com/carter51200/agent-meter/releases/tag/v0.3.0)

초기 테스트 버전입니다. Apple 개발자 ID 서명·공증은 아직 없으며, 다른 맥에서 설치 시 macOS가 실행을 차단할 수 있습니다. 각 사용자의 계정을 연결해야 하며 배포 파일에는 로그인 정보가 들어 있지 않습니다.

## 실행과 두 기기 설치

- macOS 14 이상. 빌드한 앱은 Apple Silicon과 Intel을 모두 지원합니다.
- `dist/Agent Meter.app`을 각 맥의 `/Applications`로 복사하고 실행하세요.
- 다른 맥으로는 `dist/Agent-Meter.zip`을 전달해 압축을 풀면 됩니다. 인증 정보는 포함되지 않습니다.
- 두 기기에서 각 서비스의 같은 계정으로 로그인하면 계정 전체 한도를 조회합니다. 이 맥의 토큰 소비량이나 API 비용이 아닙니다.
- 메뉴 막대에는 **Codex → Claude Code → Antigravity** 순서로 단색 로고가 표시됩니다. 하나의 항목 안에 함께 그려 순서가 바뀌거나 서비스 사이에 다른 아이콘이 끼어들지 않습니다. 숫자는 각 도구에서 조회된 한도 중 가장 적게 남은 비율입니다. `—`는 정보가 없다는 뜻입니다.
- 아이콘 클릭으로 상세 정보를 열고, 오른쪽 클릭으로 새로고침하거나 종료합니다. 2분마다 갱신하며 잠자기에서 깨어나면 다시 조회합니다.
- 클릭하면 실제 macOS 기본 메뉴(`NSMenu`)가 열립니다. 큰 카드와 고정 높이를 없애고 서비스별 구분선, 기본 진행 막대, 시스템 글꼴을 사용합니다. 로고는 메뉴와 상세 화면 모두 단색이며 밝은·어두운 모드를 자동으로 따릅니다. 모델별 상세 한도와 설정은 기본 하위 메뉴로 엽니다.
- 설정 하위 메뉴에서 로그인 시 자동 실행을 켤 수 있습니다. 초기에는 꺼져 있습니다.

## 서비스 연결

**Codex:** `codex login`의 ChatGPT 로그인 정보를 `~/.codex/auth.json`에서 읽습니다. 터미널 실행 시 `CODEX_HOME`도 지원합니다. API 키만 있으면 구독 한도는 조회하지 못합니다. 서버가 반환한 기간으로 제목을 정하므로 첫 번째 한도가 주간이면 주간으로 표시합니다.

**Claude Code:** `~/.claude/.credentials.json` 또는 macOS의 `Claude Code-credentials` 키체인 항목을 읽습니다. `CLAUDE_CONFIG_DIR`는 터미널 실행 시 지원합니다. ‘Claude 연결’을 직접 눌렀을 때만 키체인 허용 창을 띄웁니다. 자동 갱신은 키체인 허용 창을 띄우지 않습니다. CLI에 로그인하려면 `claude` 안에서 `/login`을 실행하세요. 로그인 토큰이 만료되면 ‘CLI 연결’에서 Claude Code에 이미 로그인하고 신뢰한 작업 폴더를 선택할 수 있습니다. 앱이 해당 폴더에서 일회성 `claude /usage` 화면을 조회하여 CLI가 자신의 로그인을 갱신하도록 합니다. API 키 방식이면 구독 한도를 가져올 수 없습니다.

**Antigravity (실험적):** ‘CLI 연결’에서 `agy`에 이미 로그인하고 신뢰한 작업 폴더를 선택하세요. 앱은 해당 폴더에서 일회성 터미널을 열어 `/usage`만 실행하고 종료합니다. 최신 CLI의 외부 API 제한을 피하면서 Gemini 및 Claude + GPT의 주간·5시간 한도를 읽습니다. 연결된 폴더가 없으면 실행 중인 Antigravity 로컬 서버를 읽습니다. 단순 모델 사용 가능 여부를 100% 한도로 표시하지 않습니다. 새 계정 로그인이나 OAuth 원격 fallback은 포함하지 않습니다.

## 요금제 표시

서비스 이름 아래 요금제를 표시합니다.

- Codex: 사용량 응답의 `plan_type`을 사용합니다.
- Claude Code: 로그인 정보의 `subscriptionType`을 우선하며 Max 5×/20×도 구분합니다. Team 계정의 한도 등급이 Max여도 요금제를 Team으로 표시합니다. 이 정보는 로그인 시 기록되므로 요금제 변경 후 재로그인이 필요할 수 있습니다.
- Antigravity: 서버가 제공하는 `userTier.name` 또는 CLI 화면의 명시적인 요금제 라벨을 사용합니다. 현재 `agy /usage` 화면이 요금제를 제공하지 않으면 **요금제 확인 안 됨**으로 표시합니다. 내부 `planInfo.planName`이나 모델 이름·잔여 한도로 Google AI 요금제를 추정하지 않습니다.

## 개인정보와 한계

- 로그인 정보를 복사·저장·수정하거나 다른 맥으로 동기화하지 않습니다. 각 도구가 가진 로그인을 읽기 전용으로 사용합니다.
- 사용량 요청은 해당 서비스 또는 `127.0.0.1`에만 전송됩니다. 로그인 토큰과 전체 서버 응답은 로그에 기록하지 않습니다.
- 원격 HTTPS 인증서 검증을 사용하며 요청 리디렉션은 거부합니다. Antigravity의 자체 서명 인증서는 `127.0.0.1`에 한해 허용합니다.
- Antigravity 로컬 서버 탐색에 프로세스 명령줄과 해당 프로세스의 리슨 포트 정보를 사용합니다. 이 정보는 저장하거나 외부에 보내지 않습니다.
- 실패한 수치를 과거 계정의 데이터로 대체하지 않습니다. 실패하면 `—`와 안내문을 표시합니다. 갱신 중에는 직전 측정값과 확인 시간을 표시합니다.
- CLI 연결은 선택한 폴더에서 해당 CLI를 잠시 실행합니다. `/usage` 외의 프롬프트를 보내지 않으며 모델 추론을 요청하지 않습니다. 초기 설정이나 신뢰 확인 화면이 나타나면 앱은 승인하지 않고 종료하며, 그 폴더에서 CLI 초기 설정을 먼저 마치도록 안내합니다. CLI가 자체적으로 로그인 갱신이나 설정·로그 기록을 수행할 수 있습니다.
- API와 CLI 화면은 안정적 계약이 아니므로 서비스 변경에 따라 수정이 필요할 수 있습니다.
- 개발자 ID 서명·Apple 공증은 없습니다. 다른 맥에서는 Gatekeeper가 실행을 막을 수 있으므로 시스템 설정 → 개인정보 보호 및 보안에서 이 앱의 실행을 허용해야 할 수 있습니다.
- 이 기기에서의 확인 결과는 아래 검증 기록을 참고하세요. 다른 맥의 계정 연결과 동작은 그 기기에서 별도로 확인해야 합니다.

## 개발

macOS와 Swift 6 이상을 지원하는 Xcode Command Line Tools가 필요합니다.

```sh
swift run ParserChecks
zsh scripts/build-app.sh
open "dist/Agent Meter.app"
```

안전한 진단(계정 이메일·토큰은 출력하지 않음):

```sh
"dist/Agent Meter.app/Contents/MacOS/AgentMeter" --check
```

키체인 허용 창을 표시하는 진단은 `--check --connect-claude`를 사용합니다. `--workspace /absolute/path`는 두 CLI가 사용할 폴더를 이 맥의 앱 설정에 저장합니다. 그 폴더는 미리 로그인·신뢰 확인이 끝난 곳이어야 합니다. `--check --force-cli`는 Claude와 Antigravity의 터미널 대체 경로를 검증합니다. 실제 사용량을 보여주는 별도 미리보기 창은 `--preview`로 실행합니다.

## 조회 방식 참고

프로토콜과 응답 구조를 확인할 때 [CodexBar의 provider 문서](https://github.com/steipete/CodexBar/tree/main/docs)를 참고했습니다. 이 앱의 구현과 UI는 이 프로젝트에서 새로 작성했습니다.

## 로고

Codex는 [CodexBar의 단색 Codex/OpenAI 심벌](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBar/Resources/ProviderIcon-codex.svg)을 사용합니다. 원본 SVG의 경로를 AppKit으로 렌더링했으며 MIT 라이선스를 앱에 동봉합니다. Claude 심벌은 공식 앱의 `TrayIconTemplate@2x.png`, Antigravity는 [Google 공식 Press Assets](https://antigravity.google/press)의 단색 아이콘을 사용합니다. 서비스 로고는 서비스 식별을 위한 것이며 이 앱의 공식 제휴를 의미하지 않습니다. Agent Meter 자체 앱 아이콘은 이 프로젝트에서 AppKit으로 그립니다.

## 검증 기록

2026-10-12, 이 맥에서 다음을 확인했습니다.

- 파서 검사 11개 통과: 기간별 한도, 정보 누락, ANSI 화면 및 갱신 숫자, 모델별 한도.
- 세 서비스의 실제 로그인 상태에서 계정 잔여 한도 조회. Claude 및 Antigravity CLI 대체 경로도 확인.
- Apple Silicon / Intel 범용 앱 빌드와 macOS 14 최소 버전.
- 실제 UI에서 세 서비스의 단색 로고와 Codex → Claude Code → Antigravity 순서.
- macOS 기본 메뉴 열기·Esc 닫기, 실계정 한도 표시, 미리보기 창을 닫은 뒤 메뉴 막대 프로세스 유지.
- Mac mini 및 다른 MacBook에서의 설치와 로그인 연결은 아직 확인하지 않았습니다.

2026-10-13, 요금제 판별 검사 4개를 추가해 총 15개 검사로 확대했습니다. 배포 ZIP에는 앱과 리소스만 포함되며 `.build`, 로그, 개인 작업 폴더와 인증 파일은 포함하지 않습니다.
