# 여행 중 도우미 (On-Trip Help) — 설계

작성일: 2026-08-21

## 배경

현재 SeoulFit의 챗봇은 **여행 전** 한 종류뿐이다. `/chat`은 LangGraph 스레드로 슬롯을
채워 일정을 생성하는 전용 플로우이고, 입력 가드레일(`guardrail_gate.py`)이 "서울 여행
계획" 밖의 질문을 차단한다. 여행자가 **서울에 도착한 뒤** 겪는 문제 — 여권을 잃었다,
아프다, 지금 여기 뭐가 있나 — 는 이 플로우가 다루지 못한다.

여행 중 도우미는 이 세 상황만 다루는 별도 모드다.

## 목표

1. **여권분실** — 자국 대사관의 주소·전화를 오프라인에서도 즉시 찾는다
2. **응급실** — 현재 위치에서 가까운, 실제로 운영 중인 응급실을 병상 상황과 함께 찾는다
3. **주변 추천** — 현재 위치 도보권의 카페·음식점을 거리순으로 받는다

## 비목표

- 자연어 대화. 이번 범위는 퀵액션 3버튼과 결정적 응답이다
- 의료 판단. 증상을 묻거나 분류하지 않는다
- 여행 전 챗봇의 LangGraph 상태에 개입하는 것

---

## 1. 화면과 네비게이션

하단 탭 5개(Chat / Explore / Lens / Events / Profile)는 이미 만석이고, 6번째를 넣으면
`AppBottomNav`의 60px 폭 레이아웃과 라우트 배열을 전부 손봐야 한다. 대신 **Chat 탭을 두
모드로 나눈다.**

```
/chat        ConversationalIntakeScreen   여행 전 (기존, 변경 최소)
/live-help   LiveHelpScreen               여행 중 (신규)
```

둘 다 `AppBottomNav(currentIndex: 0)`을 쓴다. 헤더의 세그먼트 토글
`Plan | On-trip`이 `pushReplacementNamed`로 전환한다 — 기존 탭 전환과 같은 방식이다.

저장된 여행의 날짜가 구조화되어 있지 않아(`SavedTrip.date`가 `String`) "여행 중"을 자동
판정할 수 없다. **기본값은 Plan, 전환은 수동**이다.

`LiveHelpScreen` 본문:

```
🐣  What can I help you with?

┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ 🛂 Lost      │ │ 🏥 Emergency │ │ 📍 Near me   │
│    passport  │ │    room      │ │              │
└──────────────┘ └──────────────┘ └──────────────┘
```

버튼을 누르면 같은 화면 안에서 결과 뷰로 전환한다. 라우트를 늘리지 않는다.
LLM 호출은 없다 — 응급 상황에서 지연도 환각도 만들지 않기 위해서다.

---

## 2. 여권분실

### 데이터

외교부 [주한공관주소록](https://www.mofa.go.kr/www/pgm/m_4073/uss/cnsrshp/inKoEmblgbdAdres.do)에서
수집·정규화한 **서울 소재 118개 공관**을 `assets/data/embassies.json`으로 번들한다.
**백엔드를 거치지 않는다.** 여권을 잃은 사람은 데이터로밍이 끊겨 있을 수 있다.

수집 파이프라인 (수집 완료, 리포에 반영됨):

```
uv run --with httpx python backend/tools/scrape_mofa.py   # → backend/tools/_mofa_raw.json (159건)
uv run python backend/tools/normalize.py                   # → assets/data/embassies.json (118건)
```

레코드 스키마:

```json
{ "country_en": "Philippines", "country_ko": "필리핀", "iso2": "PH",
  "kind": "embassy", "mission_ko": "필리핀", "city": "서울",
  "postal_code": "04346", "address_ko": "서울특별시 용산구 회나무로 80",
  "phone": "788-2100/1", "phone_dial": "02-7882100",
  "email": "seoulpe@philembassy-seoul.com", "website": "" }
```

`phone`은 원문 그대로 표시용, `phone_dial`은 `tel:` 링크용이다. 원본은 지역번호를
대부분 생략하고 `3785-1427/ 749-8982/3`, `794-6482~3`처럼 복수 번호를 슬래시·물결로
잇는다. `normalize.py`가 첫 번호만 뽑아 지역번호를 채우며, 파싱이 조용히 틀리면 엉뚱한
곳으로 전화가 걸리므로 assert 셀프체크를 붙여두었다.

수집 시 제외한 것: 국제기구 30건(유엔난민기구·녹색기후기금 등 — 여권 재발급과 무관),
서울 외 영사관 11건(부산·제주·광주).

### 알려진 한계

- **웹사이트 15/118.** 원본에 없다. 대사관 URL을 추측해 채우지 않는다 — 여권 잃은
  사람에게 틀린 도메인을 주는 것은 없는 것보다 나쁘다. 링크가 없으면 버튼을 숨긴다
- **긴급전화·업무시간 전무.** 원본에 필드 자체가 없고, 118개 대사관 홈페이지를 각각
  크롤링해 얻은 값은 금방 썩는다. 대신 아래 배너로 대체한다

### 고정 배너

결과 화면 상단에 항상 노출한다. 대표전화는 새벽에 받지 않지만 이 둘은 받는다.

- **1330** — 한국관광공사 24시간 다국어 관광통역안내
- **112** — 경찰. 여권 분실은 경찰 신고가 대사관 방문보다 먼저다

### UI

국가 검색(영문·한글·ISO2 매칭) → 카드에 주소·전화·이메일. `url_launcher`로 `tel:`
전화걸기, 주소 문자열로 지도 앱 열기. 좌표는 저장하지 않는다 — 주소로 지도 검색을
열면 충분하고 지오코딩 단계가 통째로 사라진다.

---

## 3. 응급실

### 검증 결과

E-Gen(`B552657/ErmctInfoInqireService`)의 9개 오퍼레이션을 모두 실호출한 결과
**2개만 쓴다.**

| 오퍼레이션 | 판단 | 근거 |
|---|---|---|
| `getEgytLcinfoInqire` | **사용** | 좌표·거리를 주는 유일한 엔드포인트. `distance`(km) 오름차순 |
| `getEmrrmRltmUsefulSckbdInfoInqire` | **사용** | `dutyTel3`(응급실 직통)와 `hvec`(가용병상)의 유일한 출처 |
| `getEgytListInfoInqire` | 제외 | 위치조회가 같은 데이터 + 거리까지 준다. 완전 중복 |
| `getSrsillDissAceptncPosblInfoInqire` | 제외 | 질환별 수용가능 여부. 관광객 챗봇이 분류할 영역이 아니고 틀리면 위험 |
| `getStrm*` (외상센터 3종) | 제외 | 이송처는 119가 결정한다. 관광객이 직접 찾아가는 곳이 아님 |
| `getEmrrmSrsillDissMsgInqire` | 제외 | 서울만 755건. "산부인과 NICU 부재로 모든 산모 수용 불가" 같은 의료 한국어 노이즈 |
| `getEgytBassInfoInqire` | 조건부 | hpid당 1콜이라 목록엔 못 쓴다. 상세 화면에서만 (아래) |

**2번째 콜이 필요한 이유는 병상이 아니라 전화번호다.** 위치조회가 주는 `dutyTel1`은
병원 대표번호라 새벽에 걸면 받지 않는다. 응급실 직통번호 `dutyTel3`는 실시간 병상
응답에만 있다.

### 조인

`hpid`로 조인한다. 실시간 목록에 없는 기관은 응급실을 운영하지 않는 일반 병원이므로
**자동으로 걸러진다** — 별도 필터링 로직이 필요 없다.

실측(홍대입구 기준): 위치조회 102곳 → 실제 운영 응급실 **52곳**, 2콜 **0.8초**.

`STAGE1=서울특별시`만으로 서울 전체 55개 기관이 1콜에 온다(51KB, 2.2초). 페이지네이션
불필요.

### 캐시와 트래픽

각 오퍼레이션 일일 1000콜. 조회당 2콜이면 하루 500회.
**실시간 병상은 서울 전체가 한 응답이므로 60초 캐시**하면 사실상 위치조회만 소모되어
1000회까지 늘어난다. 갱신주기는 실측상 분 단위(`hvidate` 기준, 2콜 사이에 세브란스
병상이 1→4로 변동)라 60초 캐시로 신선도 손실이 없다.

### 병상 표시 — 음수 처리

`hvec`는 **정원 초과를 음수로 표현한다.** 실측: 서울아산 -6, 서울대 -5, 서울성모 -4,
강북삼성 -1. 서울 55곳 중 음수 5 · 0 2 · 여유 48.

`-6 beds`로 렌더링하면 안 된다. `hvec > 0`이면 병상 수, **`hvec <= 0`이면 "만원/Full"**.

### 폴백

**응급 화면은 어떤 경우에도 막다른 길을 만들지 않는다.** 위치 실패든 API 실패든 항상
최소 정보를 보여준다: 119 안내 + 서울 권역응급의료센터 5곳 하드코딩. 이 부분은
간결함을 이유로 잘라내지 않는다.

### 조건부 확장 (Phase 2)

목록에서 병원을 탭했을 때만 `getEgytBassInfoInqire`를 1콜 호출한다. `dutyMapimg`가
`"2호선 신촌역 1번출구 셔틀버스 이용 또는 3번 출구 10분 거리"` 같은 실제 찾아가는 길을
주는데, 외국인에게는 좌표보다 유용하다.

---

## 4. 주변 추천

### 정책 (실호출 검증 완료)

- Google Places **Nearby Search**, `language=en`
- 반경 **500m → 부족하면 1000m, 거기서 중단**
- `user_ratings_total >= 50` 필터
- **순수 거리순, 5개**
- 프랜차이즈를 거르지 않는다 (의사결정 완료)

반경 상한이 핵심이다. 상한 없이 5개를 채우려 하면 주거지역에서 2km까지 밀려나
도보 20분 거리의 스타벅스를 "내 위치 기반 추천"으로 내놓는다.
**못 채우면 있는 만큼만 준다** — "근처에 3곳 있어요"가 "20분 걸어가세요"보다 정직하다.

6개 시나리오 실측 (최대 2콜):

| 지점 | cafe | restaurant |
|---|---|---|
| 신금호 (주거) | 3/5 · 2콜 | 5/5 · 2콜 |
| 홍대입구 (번화가) | 5/5 · 1콜 | 5/5 · 1콜 |
| 북악산 자락 (외곽) | 5/5 · 2콜 | 5/5 · 2콜 |

### 구현 시 주의

- **`user_ratings_total` 키가 아예 없는 업소가 있다.** 구글은 리뷰가 0인 곳에서 이
  필드와 `rating`을 빼고 내려준다. `.get("user_ratings_total", 0)`으로 읽으면 크래시
  회피가 아니라 의미상 정확하고(키 없음 = 리뷰 0개), 필터가 알아서 걸러낸다.
  `rating`도 없을 수 있으므로 null이면 평점 뱃지를 숨긴다
- **`rankby=distance`는 `radius`와 함께 쓸 수 없다.** 반경 확장 전략을 쓰므로
  `radius`를 쓰고 거리 정렬은 하버사인으로 직접 계산한다
- **`language=en`이 상호를 번역하지 않는다.** 구글은 등록된 상호를 준다
  (`신금호숯불갈비 본점`, `골목냉면 胡同冷面`). 영문명이 등록된 업소만 영문으로 나온다.
  외국인 대상 앱이지만 이건 API 한계이므로 그대로 노출한다
- `open_now`는 실려 오지만 결측될 수 있다 — 없으면 상태 뱃지를 숨긴다

---

## 5. 위치 획득

`geolocator` 패키지를 추가하고 단일 함수 `currentLatLng()`로 감싼다.

1. 권한 요청 → GPS 좌표
2. 거부/실패 → 지역 수동 선택 바텀시트 (`geo.py`의 `SEOUL_AREA_CENTERS` 재사용)

**iOS `Info.plist`에 `NSLocation*` 키가 하나도 없다.** 온보딩의
`Permission.location.request()`
([onboarding_screen.dart:118](../../../lib/screens/onboarding_screen.dart#L118))는 iOS에서
사실상 동작하지 않는다. `NSLocationWhenInUseUsageDescription`을 추가하면 이 버그도 함께
고쳐진다.

Android는 `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`이
[AndroidManifest.xml:4-5](../../../android/app/src/main/AndroidManifest.xml#L4-L5)에 이미
선언되어 있어 손댈 것이 없다.

---

## 6. 백엔드 계약

`backend/live_help.py`를 `APIRouter`로 만들어 `lens_router`와 같은 방식으로 마운트한다.
Places 키는 이미 `GOOGLE_PLACES_API_KEY`로 백엔드 `.env`에 있고
[planner.py:192](../../../backend/planner.py#L192)에 nearbysearch 헬퍼가 있으므로
재사용한다. 클라이언트에 키를 노출하는
[place_detail_screen.dart:11](../../../lib/screens/place_detail_screen.dart#L11) 방식은
따라가지 않는다.

신규 환경변수: `EGEN_API_KEY` (data.go.kr **Decoding** 키. Encoding 키를 쓰면 `%`가
이중 인코딩되어 `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`가 난다).

### `POST /nearby`

```json
// 요청
{ "lat": 37.553675, "lng": 127.021367, "type": "cafe", "want": 5 }

// 응답
{ "radius_used": 1000,
  "places": [
    { "name": "Ediya Coffee Shingumhoyeok Branch",
      "address": "66, 금호산길, 성동구",
      "lat": 37.553945, "lng": 127.019638, "distance_m": 155,
      "rating": 4.1, "reviews": 80, "open_now": true,
      "place_id": "ChIJzcwU3GyjfDURf8kf5ENstiY" } ] }
```

### `POST /emergency-rooms`

```json
// 요청
{ "lat": 37.5563, "lng": 126.9236, "want": 5 }

// 응답
{ "updated_at": "20260821182414",
  "hospitals": [
    { "name": "연세대학교의과대학세브란스병원",
      "address": "서울특별시 서대문구 연세로 50-1 (신촌동)",
      "lat": 37.5621, "lng": 126.9408, "distance_km": 1.65,
      "er_phone": "02-2227-7777",
      "beds": 4, "beds_state": "available" } ] }
```

`beds_state`는 `available` | `full`. `hvec <= 0`이면 `full`이고 `beds`는 그대로 넘기되
프런트는 숫자를 렌더링하지 않는다.

---

## 7. 프런트 구조

| 파일 | 역할 |
|---|---|
| `lib/screens/live_help_screen.dart` | 3버튼 + 결과 뷰 3종 |
| `lib/services/live_help_service.dart` | 백엔드 2콜 + 에셋 로드 + `currentLatLng()` |
| `lib/models/live_help.dart` | `Embassy` / `EmergencyRoom` / `NearbyPlace` |
| `lib/widgets/chat_mode_toggle.dart` | `Plan \| On-trip` 세그먼트, 양쪽 헤더에서 공유 |

위치 로직은 별도 파일로 빼지 않고 `live_help_service.dart` 안의 최상위 함수로 둔다 —
호출 지점이 둘뿐이다.

### 수정하는 파일

- `backend/api.py` — 라우터 마운트 2줄
- `lib/main.dart` — `/live-help` 라우트 1줄
- `lib/screens/conversational_intake_screen.dart` — 헤더에 토글 삽입
- `pubspec.yaml` — `geolocator`, `assets/data/`
- `lib/theme/app_theme.dart` — `kDanger` 토큰 추가 (현재 위험색이 없다)
- `ios/Runner/Info.plist` — `NSLocationWhenInUseUsageDescription` (Android는 이미 선언됨)
- `backend/.env` — `EGEN_API_KEY`

디자인 토큰과 모션은 `seoulfit-flutter-ui` 스킬의 계약을 따른다. 새 색·간격 값을
하드코딩하기 전에 해당 스킬을 먼저 확인한다.

---

## 8. 에러 처리

| 상황 | 동작 |
|---|---|
| 위치 권한 거부 | 지역 수동 선택 바텀시트 |
| 위치 획득 실패 | 동일 |
| Places 실패 | "지금은 주변 정보를 못 가져왔어요" + 재시도 |
| E-Gen 실패 | **119 안내 + 권역응급의료센터 5곳 하드코딩 폴백** |
| 대사관 검색 결과 없음 | 1330 배너는 그대로 두고 "검색 결과 없음" |

여권분실은 에셋 기반이라 네트워크 실패 경로가 없다.

---

## 9. 테스트

`backend/test_live_help.py` — 기존 `test_*.py`들과 같은 형식의 assert 기반 셀프체크.
`backend/_fixtures`에 실제 응답을 저장해 쓴다.

1. E-Gen XML 파싱 — `hpid` 조인, `hvec` 음수 → `full`
2. Places 필터 — `user_ratings_total` 키 결손 → 0 취급 → 제외
3. 반경 확장 — 500m에서 충족 시 1000m를 호출하지 않음
4. 하버사인 거리 계산

프런트는 `flutter analyze` + 실기기 위치 스모크.

`backend/tools/normalize.py`의 전화번호 파싱 assert는 이미 통과 상태다.

---

## 10. 리스크

| 리스크 | 대응 |
|---|---|
| 외교부 페이지 구조 변경 시 재수집 실패 | `scrape_mofa.py`가 항목 0건이면 즉시 종료하고 사유를 출력 |
| 대사관 데이터 노후화 | 번들 데이터라 앱 릴리스 주기를 따른다. 재수집 명령을 README에 남긴다 |
| E-Gen 1000콜/일 초과 | 60초 캐시. 초과 시 폴백 경로가 이미 있다 |
| 프랜차이즈 위주 추천 | 의사결정 완료 — 이번 범위에서는 거르지 않는다 |

## 미해결

없음. 세 기능 모두 실호출로 검증했고 정책 결정도 완료했다.
