from typing import Optional, Any
from typing_extensions import TypedDict
from langgraph.graph.message import add_messages
from typing import Annotated


class TravelState(TypedDict, total=False):
    travel_dates: Optional[str]        # 여행 날짜/기간 (자유 텍스트, LLM 추출 원본)
    trip_start_date: Optional[str]     # travel_dates에서 뽑아낸 여행 시작일 ISO "YYYY-MM-DD".
                                        # 앵커할 날짜가 없으면(예: "3일간") None — 폴백이지 에러 아님.
                                        # graph.py의 _extract_trip_info 처리 단계에서 채워짐
                                        # (rag.parse_trip_start_date). Generator(planner.py)는
                                        # 아직 이 값을 쓰지 않음 — 넘겨받을 준비만 된 상태.
    category: Optional[str]            # 관심사 카테고리
    restrictions: Optional[str]        # 식이/신체 제약
    companion: Optional[str]           # 동행자
    pace: Optional[str]                # 여행 스타일
    region: Optional[str]              # 서울 지역
    current_step: str                  # start | collecting_basics | collecting_region | confirm | retrieving | planning | critic | done
    confirmed: bool                    # 최종 컨펌 여부
    messages: Annotated[list, add_messages]  # 대화 히스토리 (reducer 적용)

    # RAG + planning
    retrieved_courses: list[dict[str, Any]]   # FAISS 검색 결과 코스 리스트 (flat merge of all segment anchors)
    day_segments: Optional[list[dict[str, Any]]]  # per-day-segment anchor courses (Index A)
    itinerary: Optional[dict[str, Any]]       # 최종 일정 (구조화된 JSON)

    # Planner → critic_repair handoff
    planning_context: Optional[dict[str, Any]]
    critic_report: Optional[dict[str, Any]]
