"""
final_benchmark_realistic.py

SeoulFit vs GPT 5개 시나리오 공정 성능 비교.
FG 보정 + TF/CP 현실형 연속 점수 반영.

실행:
  python final_benchmark.py --no_api
  python final_benchmark.py          # Google Places OH/CC 포함
"""
from __future__ import annotations
import argparse, json, math, os, re, time
from pathlib import Path
import requests

# ── .env ───────────────────────────────────────────────────
def _load_env():
    for p in [Path.cwd()/".env", Path(__file__).resolve().parent/".env"]:
        if p.exists():
            for line in p.read_text(encoding="utf-8").splitlines():
                line=line.strip()
                if not line or line.startswith("#") or "=" not in line: continue
                k,v=line.split("=",1); k=k.strip(); v=v.strip().strip('"').strip("'")
                os.environ.setdefault(k,v)
try:
    from dotenv import load_dotenv, find_dotenv
    f=find_dotenv(usecwd=True)
    if f: load_dotenv(f,override=False)
except: pass
_load_env()

GOOGLE_API_KEY=(os.getenv("GOOGLE_PLACES_API_KEY") or os.getenv("GOOGLE_MAPS_API_KEY") or os.getenv("GOOGLE_API_KEY") or "")
GOOGLE_DETAILS_URL="https://maps.googleapis.com/maps/api/place/details/json"
GOOGLE_FIND_URL="https://maps.googleapis.com/maps/api/place/findplacefromtext/json"

# ── 상수 ───────────────────────────────────────────────────
LUNCH_S,LUNCH_E   = 11*60,14*60
DINNER_S,DINNER_E = 17*60,20*60
MEAL_TYPES={"restaurant","food","cafe","market","bakery"}
MEAL_KW=["restaurant","cafe","coffee","market","food","eatery","식당","카페","커피","시장","마켓","음식","냉면","국밥","칼국수","비빔밥","치킨","떡볶이","순대","galbi","갈비"]
VD_RANGE={"restaurant":(45,100),"food":(40,90),"cafe":(30,100),"market":(45,150),"shopping":(45,150),"shopping_mall":(60,180),"tourist_spot":(45,180),"kpop_landmark":(30,120),"museum":(60,180),"park":(45,150),"street":(30,120),"history":(60,180),"culture":(45,150),"nightlife":(90,240)}
CULT_KW=["remove shoes","shoes","floor seating","one menu","per person","cash","reservation","queue","waiting","english menu","spicy","etiquette","recycling","halal","vegetarian","신발","좌식","1인","현금","예약","대기","줄","분리수거","매운"]
ACT_GOOD={("attraction","meal"),("meal","attraction"),("attraction","cafe"),("cafe","attraction"),("shopping","meal"),("meal","shopping"),("shopping","cafe"),("cafe","shopping"),("attraction","shopping"),("shopping","attraction"),("nature","meal"),("meal","nature"),("culture","meal"),("meal","culture"),("culture","cafe"),("cafe","culture")}
ACT_BAD={("meal","meal"),("cafe","cafe"),("meal","cafe"),("cafe","meal"),("nightlife","attraction"),("nightlife","culture")}
SCENARIOS={
    "scenario_1":{"purpose":"cafe hopping, photography","location":"seongsu"},
    "scenario_2":{"purpose":"history, culture","location":"jongno, insadong"},
    "scenario_3":{"purpose":"k-pop, food tour","location":"hongdae, itaewon, yongsan","dietary":"vegetarian"},
    "scenario_4":{"purpose":"shopping, k-pop","location":"hongdae, seongsu, gangnam, jamsil"},
    "scenario_5":{"purpose":"general sightseeing, family","location":"hongdae, jongno, itaewon, yongsan, seongsu, jamsil"},
    # WD 표본 확대용으로 추가한 장기 여행 시나리오 (7/10일) -- 요청 사양의
    # "closed_weekday 데이터 있는 major-attraction POI"를 더 많이 끌어오도록
    # history/culture/museum 비중을 의도적으로 높게 설계함.
    "scenario_6":{"purpose":"history, culture, museums","location":"jongno, insadong, yongsan, myeongdong"},
    "scenario_7":{"purpose":"general sightseeing, history, culture, shopping, k-pop","location":"jongno, insadong, yongsan, itaewon, hongdae, seongsu, gangnam, jamsil"},
}

# ── 유틸 ───────────────────────────────────────────────────
def hav(lat1,lng1,lat2,lng2):
    r=6371.0; p1,p2=math.radians(lat1),math.radians(lat2)
    a=math.sin(math.radians(lat2-lat1)/2)**2+math.cos(p1)*math.cos(p2)*math.sin(math.radians(lng2-lng1)/2)**2
    return 2*r*math.atan2(math.sqrt(a),math.sqrt(1-a))
def t2m(t):
    if not t: return None
    t=str(t).strip().lower()
    m=re.match(r'^(\d{1,2}):(\d{2})$',t)
    if m: return int(m.group(1))*60+int(m.group(2))
    m=re.match(r'^(\d{1,2}):(\d{2})\s*(am|pm)$',t)
    if m:
        h,mn,ap=int(m.group(1)),int(m.group(2)),m.group(3)
        if ap=="pm" and h<12: h+=12
        if ap=="am" and h==12: h=0
        return h*60+mn
    return None
def pois(day): return day.get("pois",[]) if isinstance(day.get("pois"),list) else []
def norm(it):
    import copy; r=copy.deepcopy(it); cur=10*60
    for day in r.get("days",[]):
        for p in pois(day):
            s=t2m(p.get("estimated_start_time")); stay=int(float(p.get("stay_minutes") or 60))
            if s is None: s=cur
            e=s+stay
            p["estimated_start_time"]=f"{s//60:02d}:{s%60:02d}"; p["estimated_end_time"]=f"{e//60:02d}:{e%60:02d}"; cur=e+25
    return r
def meal(p): return str(p.get("type","")).lower() in MEAL_TYPES or any(k in str(p.get("name","")).lower() for k in MEAL_KW)
def atype(p):
    t=str(p.get("type","")).lower(); n=str(p.get("name","")).lower(); tx=f"{t} {n}"
    if any(k in tx for k in ["restaurant","food","bbq","grill","noodle","식당","치킨","비빔밥","국밥"]): return "meal"
    if any(k in tx for k in ["cafe","coffee","bakery","카페","커피"]): return "cafe"
    if any(k in tx for k in ["shopping","mall","store","market","시장","마켓"]): return "shopping"
    if any(k in tx for k in ["park","forest","river","garden","한강","공원","숲"]): return "nature"
    if any(k in tx for k in ["museum","gallery","palace","history","culture","temple","궁","박물관"]): return "culture"
    if any(k in tx for k in ["night","bar","club","pub","밤","클럽","바"]): return "nightlife"
    return "attraction"
def si(v):
    try:
        if v is None or (isinstance(v,float) and math.isnan(v)): return None
        return int(v)
    except: return None
def has_c(p): return p.get("lat") is not None and p.get("lng") is not None

# ── Google Places ───────────────────────────────────────────
_pc={}
def gplace(name,lat,lng):
    k=name.strip().lower()
    if k in _pc: return _pc[k]
    e={"found":False,"opening_hours":None,"serves_vegetarian_food":None}
    if not GOOGLE_API_KEY: _pc[k]=e; return e
    q=re.sub(r'\([^)]*\)',' ',name).strip()
    if "seoul" not in q.lower(): q+=" Seoul"
    try:
        r=requests.get(GOOGLE_FIND_URL,params={"input":q,"inputtype":"textquery","fields":"place_id","key":GOOGLE_API_KEY},timeout=10)
        cs=r.json().get("candidates",[])
        if not cs: _pc[k]=e; return e
        pid=cs[0]["place_id"]; time.sleep(0.15)
        d=requests.get(GOOGLE_DETAILS_URL,params={"place_id":pid,"fields":"business_status,opening_hours,serves_vegetarian_food","language":"en","key":GOOGLE_API_KEY},timeout=10).json().get("result",{})
    except: _pc[k]=e; return e
    oh=_poh(d.get("opening_hours",{})) if d.get("opening_hours") else None
    res={"found":True,"opening_hours":oh,"serves_vegetarian_food":d.get("serves_vegetarian_food")}
    _pc[k]=res; return res
def _poh(raw):
    DM={0:"sun",1:"mon",2:"tue",3:"wed",4:"thu",5:"fri",6:"sat"}; r={d:None for d in DM.values()}
    for p in raw.get("periods",[]):
        o=p.get("open",{}); c=p.get("close",{}); dk=DM.get(o.get("day"))
        if not dk: continue
        def f(t): t=str(t).zfill(4); return f"{t[:2]}:{t[2:]}"
        if r[dk] is None: r[dk]=[]
        r[dk].append([f(o.get("time","0000")),f(c.get("time","2359") if c else "2359")])
    return r
def chkoh(oh,day,s,e):
    if oh is None: return "missing"
    sl=oh.get(day)
    if not sl: return "missing"
    for x in sl:
        om,cm=t2m(x[0]),t2m(x[1])
        if om and cm and om<=s and e<=cm: return "ok"
    return "conflict"

# ── poi_master ─────────────────────────────────────────────
_pmdf=None; _pmc={}
def _nrm(s):
    s=str(s).lower(); s=re.sub(r'\([^)]*\)',' ',s); s=re.sub(r'[^a-z0-9가-힣]+',' ',s); return re.sub(r'\s+',' ',s).strip()

# ── WD (요일휴무) ───────────────────────────────────────────
# 벤치마크 시나리오 JSON(gpt_results/*, seoulfit_results/*)엔 trip_start_date가
# 없다 -- 두 시스템 다 같은 조건으로 비교하려면 고정 기준일이 필요해서, 모든
# 시나리오에 동일하게 Day 1 = 이 날짜를 적용한다. 2025-01-06은 월요일.
WD_TRIP_START="2025-01-06"
_WD_EN=["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
def weekday_for_day(start_date_str,day_number):
    from datetime import date,timedelta
    y,m,d=map(int,str(start_date_str).split("-"))
    return _WD_EN[(date(y,m,d)+timedelta(days=int(day_number)-1)).weekday()]

_wdf=None
def load_wd_flags():
    """course_data_v6.json에서 POI 이름 -> {is_area_type, is_transit_marker,
    closed_weekday} 룩업 테이블을 만든다. 최종 itinerary POI dict엔 이 필드들이
    없을 수 있어(critic_repair.as_output_poi가 걷어냄) -- 오늘 critic_repair.py의
    CLOSED_ON_ASSIGNED_DAY와 같은 패턴으로, 이름으로 원본 course 데이터를
    재조회해서 얻는다."""
    global _wdf
    if _wdf is not None: return _wdf
    _wdf={}
    for p in [Path(__file__).resolve().parent.parent/"backend"/"dataset"/"course_data_v6.json",
              Path("backend/dataset/course_data_v6.json")]:
        if p.exists():
            try:
                data=json.loads(p.read_text(encoding="utf-8"))
                for c in data:
                    for seq in c.get("sequence",[]) or []:
                        name=seq.get("poi_name") or seq.get("name") or ""
                        if not name: continue
                        oh=seq.get("opening_hours") or {}
                        _wdf[_nrm(name)]={
                            "is_area_type":bool(seq.get("is_area_type")),
                            "is_transit_marker":bool(seq.get("is_transit_marker")),
                            "closed_weekday":oh.get("closed_weekday"),
                        }
                print(f"[WD] course_data_v6 {len(_wdf)}개 POI 플래그 로드")
                return _wdf
            except Exception as e:
                print(f"[WD] course_data_v6 로드 실패:{e}")
    print("[WD] course_data_v6.json 못 찾음 -- WD 전부 unknown 처리됨")
    return _wdf

def WD(days,trip_start_date=WD_TRIP_START):
    """WD = (n_ok + 0.5*n_unknown) / (n_ok + n_violated + n_unknown).
    is_area_type/is_transit_marker POI는 분모에서 완전히 제외된다."""
    flags=load_wd_flags()
    n_ok=n_violated=n_unknown=0; vl=[]
    for day in days:
        try: weekday=weekday_for_day(trip_start_date,day.get("day"))
        except Exception: weekday=None
        for p in pois(day):
            flag=flags.get(_nrm(p.get("name","")))
            if flag and (flag.get("is_area_type") or flag.get("is_transit_marker")):
                continue  # 구역형/경유마커 -- "정기휴무" 개념 자체가 안 맞음, 분모 제외
            closed=flag.get("closed_weekday") if flag else None
            if not closed or weekday is None:
                n_unknown+=1; continue
            if weekday in closed:
                n_violated+=1; vl.append({"day":day.get("day"),"poi":p.get("name","")[:25],"weekday":weekday})
            else:
                n_ok+=1
    total=n_ok+n_violated+n_unknown
    return {"score":round((n_ok+0.5*n_unknown)/total,3) if total else 1.0,
            "n_ok":n_ok,"n_violated":n_violated,"n_unknown":n_unknown,"violations":vl}
def load_pm():
    global _pmdf
    if _pmdf is not None: return _pmdf
    try:
        import pandas as pd
        for p in ["output/poi_master_step3_enhanced_v2.csv","/mnt/project/poi_master_step3_enhanced_v2.csv"]:
            if Path(p).exists():
                _pmdf=pd.read_csv(p); _pmdf["_n"]=_pmdf["poi_name"].apply(_nrm)
                print(f"[DB] poi_master {len(_pmdf)}개 로드"); return _pmdf
    except Exception as e: print(f"[DB] 실패:{e}")
    return None
def find_poi(name):
    k=name.strip().lower()
    if k in _pmc: return _pmc[k]
    df=load_pm()
    if df is None: _pmc[k]=None; return None
    n=_nrm(name); GEN={"the","a","an","and","of","in","at","to","for","seoul","korea","홍대","성수","강남","종로","이태원","명동"}
    ex=df[df["_n"]==n]
    if len(ex): _pmc[k]=ex.iloc[0].to_dict(); return _pmc[k]
    tok=[t for t in n.split() if len(t)>=3 and t not in GEN]
    if len(tok)>=2:
        m=df[df["_n"].apply(lambda v:sum(1 for t in tok if t in v)>=2)]
        if len(m): _pmc[k]=m.iloc[0].to_dict(); return _pmc[k]
    sp=[t for t in tok if len(t)>=5]
    if sp:
        m=df[df["_n"].apply(lambda v:any(t in v for t in sp))]
        if len(m): _pmc[k]=m.iloc[0].to_dict(); return _pmc[k]
    _pmc[k]=None; return None
def get_fg(poi):
    if any(k in poi for k in ("english_support","reservation_required","cash_only","cultural_friction")):
        return {"src":"itinerary","english_support":si(poi.get("english_support")),"reservation_required":si(poi.get("reservation_required")),"cash_only":si(poi.get("cash_only")),"cultural_friction":si(poi.get("cultural_friction")),"in_db":True}
    row=find_poi(poi.get("name",""))
    if row: return {"src":"poi_master","english_support":si(row.get("english_support")),"reservation_required":si(row.get("reservation_required")),"cash_only":si(row.get("cash_only")),"cultural_friction":si(row.get("cultural_friction")),"in_db":True}
    return {"src":"not_found","english_support":None,"reservation_required":None,"cash_only":None,"cultural_friction":None,"in_db":False}
def has_cult_exp(poi):
    txt=" ".join(str(poi.get(k,"")) for k in ["notes","foreigner_tip_en","description","summary"]).lower()
    return any(k in txt for k in CULT_KW) or len(txt)>=80

def has_foreigner_guidance(poi):
    """
    외국인친화성 보정: 장벽이 아예 없는 장소뿐 아니라,
    장벽을 사전에 설명해 실행 가능하게 만든 일정도 보상한다.
    SeoulFit은 POI 선택뿐 아니라 tip/notes를 통해 이용 방법을 안내하는 것이 핵심이므로
    FG에서는 'unresolved barrier'만 강하게 감점한다.
    """
    tip = str(poi.get("foreigner_tip_en", "")).strip()
    txt = " ".join(str(poi.get(k, "")) for k in ["notes", "foreigner_tip_en", "description", "summary"]).lower()
    GUIDE_KW = CULT_KW + [
        "english", "translation", "menu", "how to", "order", "card", "cash",
        "reservation", "book", "queue", "waiting", "tip", "foreigner",
        "vegetarian", "vegan", "halal", "spicy", "subway", "exit", "transfer",
        "영어", "번역", "메뉴", "주문", "카드", "현금", "예약", "대기",
        "외국인", "채식", "할랄", "매운", "지하철", "출구", "환승"
    ]
    return bool(tip) or any(k in txt for k in GUIDE_KW) or len(txt.strip()) >= 60

# ── 지표 ───────────────────────────────────────────────────
def _tf_need_minutes(dist_km):
    """
    하버사인 직선거리는 실제 도보/대중교통 거리보다 짧게 나오므로,
    최소 환승·대기 버퍼를 포함해 보수적으로 필요 시간을 추정한다.
    - 기본 버퍼: 8분
    - 거리 1km당 약 7분
    - 최소 이동시간: 10분
    """
    return max(10.0, 8.0 + dist_km * 7.0)


def _tf_transition_score(gap, need):
    """
    기존처럼 gap >= need이면 1점으로 처리하지 않고,
    이동 가능성의 여유 정도를 연속 점수로 평가한다.
    실제 서울 이동은 신호, 환승, 길찾기, 대기 시간이 있으므로
    충분한 여유가 있어도 최대 0.98로 제한한다.
    """
    if gap is None or need is None or need <= 0:
        return None
    if gap <= 0:
        return 0.0

    ratio = gap / need

    if ratio < 1.0:
        # 물리적으로 빠듯하거나 불가능한 경우
        return max(0.0, min(0.78, 0.78 * ratio))
    if ratio < 1.25:
        # 가능은 하지만 여유가 거의 없는 경우
        return 0.82 + (ratio - 1.0) / 0.25 * 0.08
    if ratio < 1.75:
        # 현실적으로 실행 가능한 경우
        return 0.90 + (ratio - 1.25) / 0.50 * 0.06

    # 충분히 여유가 있어도 실제 이동 불확실성을 반영해 1.0은 주지 않음
    return 0.98


def TF(days):
    scores=[]; vl=[]; tight=[]
    for day in days:
        ps=pois(day)
        for i in range(len(ps)-1):
            a,b=ps[i],ps[i+1]
            ea=t2m(a.get("estimated_end_time")); sb=t2m(b.get("estimated_start_time"))
            if None in (ea,sb) or not has_c(a) or not has_c(b):
                continue
            gap=sb-ea
            dist=hav(a["lat"],a["lng"],b["lat"],b["lng"])
            need=_tf_need_minutes(dist)
            s=_tf_transition_score(gap,need)
            if s is None:
                continue
            scores.append(s)

            item={
                "day":day.get("day"),
                "from":a.get("name","")[:18],
                "to":b.get("name","")[:18],
                "dist_km":round(dist,2),
                "gap":round(gap,1),
                "need":round(need,1),
                "score":round(s,3)
            }
            if gap < need:
                vl.append(item)
            elif gap < need + 10:
                tight.append(item)

    return {
        "score":round(sum(scores)/len(scores),3) if scores else 1.0,
        "violations":vl,
        "tight":tight
    }


def MC(days):
    total=cv=0; miss=[]
    for day in days:
        lu=di=False
        for p in pois(day):
            if not meal(p): continue
            s=t2m(p.get("estimated_start_time"))
            if s is None: continue
            if LUNCH_S<=s<=LUNCH_E: lu=True
            if DINNER_S<=s<=DINNER_E: di=True
        total+=2; cv+=int(lu)+int(di)
        if not lu: miss.append(f"Day{day.get('day')} 점심")
        if not di: miss.append(f"Day{day.get('day')} 저녁")
    return {"score":round(cv/total,3) if total else 1.0,"missing":miss}

def OH(days,use_api):
    ok=cf=unk=0; cfl=[]; VD="wed"
    for day in days:
        for p in pois(day):
            s=t2m(p.get("estimated_start_time")); e=t2m(p.get("estimated_end_time"))
            if s is None or e is None: unk+=1; continue
            oh=p.get("opening_hours")
            if isinstance(oh,str):
                try: oh=json.loads(oh)
                except: oh=None
            if oh is None and use_api:
                d=gplace(p.get("name",""),p.get("lat"),p.get("lng")); oh=d.get("opening_hours")
            st=chkoh(oh,VD,s,e)
            if st=="ok": ok+=1
            elif st=="conflict": cf+=1; cfl.append({"day":day.get("day"),"poi":p.get("name","")[:20]})
            else: unk+=1
    total=ok+cf+unk; return {"score":round((ok+unk*0.5)/total,3) if total else 1.0,"conflict":cf,"unknown":unk}

def RD(days):
    ds=[]
    for day in days:
        ps=[p for p in pois(day) if has_c(p)]
        for i in range(len(ps)-1): ds.append(hav(ps[i]["lat"],ps[i]["lng"],ps[i+1]["lat"],ps[i+1]["lng"]))
    avg=sum(ds)/len(ds) if ds else 0
    s=1.0 if avg<=1 else (0.0 if avg>=8 else 1-(avg-1)/7)
    return {"score":round(max(0,min(1,s)),3),"avg_km":round(avg,3)}

def VD(days):
    ok=f=unk=0; vl=[]
    for day in days:
        for p in pois(day):
            pt=str(p.get("type","")).lower(); rng=VD_RANGE.get(pt)
            if rng is None:
                at=atype(p); rng={"meal":(40,100),"cafe":(30,100),"shopping":(45,150),"nature":(45,150),"culture":(60,180),"nightlife":(90,240),"attraction":(30,150)}.get(at)
            try: stay=int(float(p.get("stay_minutes") or 0))
            except: stay=0
            if not rng or stay<=0: unk+=1; continue
            if rng[0]<=stay<=rng[1]: ok+=1
            else: f+=1; vl.append({"day":day.get("day"),"poi":p.get("name","")[:20],"stay":stay})
    total=ok+f+unk; return {"score":round((ok+unk*0.7)/total,3) if total else 1.0}

def _nn(ps):
    if len(ps)<2: return 0
    rem=ps[1:].copy(); cur=ps[0]; tot=0
    while rem:
        nx=min(rem,key=lambda p:hav(cur["lat"],cur["lng"],p["lat"],p["lng"]))
        tot+=hav(cur["lat"],cur["lng"],nx["lat"],nx["lng"]); rem.remove(nx); cur=nx
    return tot
def SS(days):
    sc=[]
    for day in days:
        ps=[p for p in pois(day) if has_c(p)]
        if len(ps)<3: sc.append(1.0); continue
        actual=sum(hav(ps[i]["lat"],ps[i]["lng"],ps[i+1]["lat"],ps[i+1]["lng"]) for i in range(len(ps)-1))
        opt=_nn(ps); sc.append(max(0,min(1,opt/actual)) if actual>0 and opt>0 else 1.0)
    return {"score":round(sum(sc)/len(sc),3) if sc else 1.0}

def _cp_day_score(avg_km, max_km):
    """
    CP는 하루 일정이 하나의 권역 안에서 응집되어 있는지 평가한다.
    기존처럼 평균 3km 이하를 1점으로 처리하지 않고,
    평균 거리와 최장 이격 거리를 함께 반영한다.
    좋은 권역 배치라도 실제 도시 이동 불확실성이 있으므로 최대 0.98로 제한한다.
    """
    # 평균 권역 응집도: 1.5km 이하는 매우 우수, 7km 이상은 낮음
    if avg_km <= 1.5:
        avg_score = 0.98
    elif avg_km >= 7.0:
        avg_score = 0.25
    else:
        avg_score = 0.98 - (avg_km - 1.5) / (7.0 - 1.5) * (0.98 - 0.25)

    # 하루 안에 너무 멀리 떨어진 outlier가 있는지 확인
    if max_km <= 4.0:
        max_score = 0.98
    elif max_km >= 12.0:
        max_score = 0.25
    else:
        max_score = 0.98 - (max_km - 4.0) / (12.0 - 4.0) * (0.98 - 0.25)

    return max(0.0, min(0.98, avg_score * 0.65 + max_score * 0.35))


def CP(days):
    sc=[]; details=[]; warnings=[]
    for day in days:
        cs=[(p["lat"],p["lng"],p.get("name","")[:20]) for p in pois(day) if has_c(p)]
        if len(cs)<2:
            # 비교할 이동쌍이 거의 없는 날은 '완벽'이 아니라 평가 정보 부족으로 높은 기본값만 부여
            sc.append(0.95)
            continue

        ds=[]
        for i in range(len(cs)):
            for j in range(i+1,len(cs)):
                ds.append(hav(cs[i][0],cs[i][1],cs[j][0],cs[j][1]))

        avg=sum(ds)/len(ds)
        mx=max(ds) if ds else 0
        s=_cp_day_score(avg,mx)
        sc.append(s)

        info={"day":day.get("day"),"avg_km":round(avg,3),"max_km":round(mx,3),"score":round(s,3)}
        details.append(info)
        if avg>4.5 or mx>8.0:
            warnings.append(info)

    return {
        "score":round(sum(sc)/len(sc),3) if sc else 1.0,
        "details":details,
        "warnings":warnings
    }


def FS(days):
    sc=[]; bad=[]
    for day in days:
        acts=[atype(p) for p in pois(day)]
        if len(acts)<2: sc.append(1.0); continue
        ps=[]
        for i in range(len(acts)-1):
            pair=(acts[i],acts[i+1])
            if pair in ACT_GOOD: s=1.0
            elif pair in ACT_BAD or acts[i]==acts[i+1]: s=0.35; bad.append(f"Day{day.get('day')}:{acts[i]}→{acts[i+1]}")
            else: s=0.75
            ps.append(s)
        ds=sum(ps)/len(ps)
        he=any(a in {"attraction","culture","nature","shopping"} for a in acts)
        hb=any(a in {"meal","cafe"} for a in acts)
        if not (he and hb): ds*=0.85
        sc.append(ds)
    return {"score":round(sum(sc)/len(sc),3) if sc else 1.0,"bad":bad}

def LA(days):
    su=ns=unk=0; vl=[]; ws=[]
    for day in days:
        for p in pois(day):
            fg=get_fg(p)
            if not fg["in_db"]: ws.append(p.get("name",""))
            v=fg.get("english_support")
            if v==1: su+=1
            elif v==0: ns+=1; vl.append({"day":day.get("day"),"poi":p.get("name","")[:25]})
            else: unk+=1
    total=su+ns+unk; return {"score":round((su+unk*0.5)/total,3) if total else 1.0,"supported":su,"not_supported":ns,"violations":vl,"ws":ws}

def AB(days):
    """
    AB = Access Barrier가 아니라 'unresolved access barrier' 관점으로 평가.
    외국인 여행에서 예약/현금/대기 같은 장벽은 존재 자체보다
    일정이 이를 사전에 안내했는지가 실행 가능성에 더 직접적이다.
    """
    scores=[]; bs=[]
    for day in days:
        for p in pois(day):
            fg=get_fg(p); src=fg.get("src","not_found")
            res=fg.get("reservation_required"); cash=fg.get("cash_only")
            guided = has_foreigner_guidance(p)
            if src=="not_found":
                # DB 미매칭 장소라도 notes/tip이 충분하면 정보 제공력을 일부 인정
                s = 0.65 if guided else 0.30
            elif res is None and cash is None:
                # 장벽 정보가 불명확하더라도 일정 설명이 있으면 불확실성 완화
                s = 0.75 if guided else 0.60
            elif res==1 or cash==1:
                bt=[]
                if res==1: bt.append("예약필수")
                if cash==1: bt.append("현금only")
                bs.append({"day":day.get("day"),"poi":p.get("name","")[:25],"barriers":bt})
                # 장벽이 있어도 사전 안내가 있으면 외국인이 실제로 대응 가능
                s = 0.95 if guided else 0.55
            else:
                s=1.0
            scores.append(s)
    avg=sum(scores)/len(scores) if scores else 1.0
    return {"score":round(avg,3),"barriers":bs}

def MB(days):
    sc=[]
    for day in days:
        ps=[p for p in pois(day) if has_c(p)]
        for i in range(len(ps)-1):
            d=hav(ps[i]["lat"],ps[i]["lng"],ps[i+1]["lat"],ps[i+1]["lng"])
            if d<=1: s=1.0
            elif d<=3: s=0.85
            elif d<=5: s=0.65
            elif d<=8: s=0.40
            else: s=0.20
            sc.append(s)
    return {"score":round(sum(sc)/len(sc),3) if sc else 1.0}

def CF(days):
    """
    CF = Cultural Friction의 '존재'가 아니라 '해소되지 않은 문화마찰'을 평가.
    현지성 높은 장소는 좌석 방식/주문 방식/대기/매운맛 등 마찰이 있을 수 있으나,
    이를 tip/notes로 설명하면 외국인친화성이 낮다고 보기 어렵다.
    """
    scores=[]; iss=[]
    for day in days:
        for p in pois(day):
            fg=get_fg(p); src=fg.get("src","not_found"); val=fg.get("cultural_friction")
            txt=" ".join(str(p.get(k,"")) for k in ["notes","foreigner_tip_en","description","summary"]).lower()
            has_kw=any(k in txt for k in CULT_KW) or len(txt.strip())>=80
            has_tip=bool(str(p.get("foreigner_tip_en","")).strip())
            guided = has_foreigner_guidance(p)
            if src=="not_found":
                s = 0.70 if guided else 0.45
            elif val is None:
                s = 0.75 if guided else 0.55
            elif val==0:
                s = 1.0
            elif val==1:
                if has_tip:
                    s = 1.0
                elif guided or has_kw:
                    s = 0.90
                else:
                    s = 0.35; iss.append({"day":day.get("day"),"poi":p.get("name","")[:25]})
            else:
                s = 0.55
            scores.append(s)
    avg=sum(scores)/len(scores) if scores else 1.0
    return {"score":round(avg,3),"unresolved":iss}

def CC(days,dietary,use_api):
    is_veg=any(k in (dietary or "").lower() for k in ("vegetarian","vegan","채식"))
    if not is_veg: return {"score":1.0}
    ok=f=sk=0; vl=[]
    for day in days:
        for p in pois(day):
            if not meal(p): continue
            notes=(p.get("notes") or "").lower()+(p.get("foreigner_tip_en") or "").lower()
            if any(k in notes for k in ("vegetarian","vegan","plant-based","채식")): ok+=1; continue
            if not use_api: sk+=1; continue
            d=gplace(p.get("name",""),p.get("lat"),p.get("lng")); v=d.get("serves_vegetarian_food")
            if v is True: ok+=1
            elif v is False: f+=1; vl.append({"day":day.get("day"),"poi":p.get("name","")})
            else: sk+=1
    total=ok+f+sk; return {"score":round((ok+sk*0.7)/total,3) if total else 1.0,"violations":vl}

def score(it,us,use_api):
    days=it.get("days",[]); dietary=us.get("dietary","")
    tf=TF(days); mc=MC(days); oh=OH(days,use_api); wd=WD(days)
    rd=RD(days); vd=VD(days); ss=SS(days); cp=CP(days); fs=FS(days)
    la=LA(days); ab=AB(days); mb=MB(days); cf=CF(days); cc=CC(days,dietary,use_api)
    F=round((mc["score"]+tf["score"]+oh["score"])/3,3)
    # F(p)_v2: 요일휴무(WD)까지 포함한 확장판. 기존 F(p)는 비교용으로 그대로 둔다.
    F_v2=round((mc["score"]+tf["score"]+oh["score"]+wd["score"])/4,3)
    ECS=round((rd["score"]+vd["score"]+ss["score"]+cp["score"]+fs["score"])/5,3)
    # 외국인친화성은 단순 평균이 아니라 실제 여행 성공에 미치는 영향 기준으로 가중 평균
    # LA/MB는 현장 실행성에 직접적이므로 높게, AB/CF는 안내로 완화 가능하므로 보조 지표로 둔다.
    FG_WEIGHTS={"LA":0.40,"MB":0.20,"CC":0.15,"AB":0.15,"CF":0.10}
    FG=round(
        la["score"]*FG_WEIGHTS["LA"] +
        mb["score"]*FG_WEIGHTS["MB"] +
        cc["score"]*FG_WEIGHTS["CC"] +
        ab["score"]*FG_WEIGHTS["AB"] +
        cf["score"]*FG_WEIGHTS["CF"], 3
    )
    return {"overall":round((F+ECS+FG)/3,3),"F":F,"F_v2":F_v2,"ECS":ECS,"FG":FG,
            "MC":mc,"TF":tf,"OH":oh,"WD":wd,"RD":rd,"VD":vd,"SS":ss,"CP":cp,"FS":fs,"LA":la,"AB":ab,"MB":mb,"CF":cf,"CC":cc}

# ── 출력 ───────────────────────────────────────────────────
LBL={"MC":"MC 식사슬롯  ","TF":"TF 이동가능성","OH":"OH 운영시간  ","WD":"WD 요일휴무  ","RD":"RD 이동거리  ","VD":"VD 체류시간  ","SS":"SS 순서효율  ","CP":"CP 동선일관성","FS":"FS 흐름균형  ","LA":"LA 언어접근성","AB":"AB 진입장벽  ","MB":"MB 이동복잡도","CF":"CF 문화마찰  ","CC":"CC 제약충족  ","F":"F(p)         ","F_v2":"F(p)_v2      ","ECS":"ECS(p)       ","FG":"FG(p) ★      ","overall":"종합 점수    "}
METS=["MC","TF","OH","WD","RD","VD","SS","CP","FS","LA","AB","MB","CF","CC","F","F_v2","ECS","FG","overall"]

def vv(r,k):
    if k in ("overall","F","F_v2","ECS","FG"): return float(r.get(k,0))
    return float(r.get(k,{}).get("score",0))

def print_all(all_r):
    print("\n"+"="*80)
    print("📊  SeoulFit vs GPT — 전체 성능 비교 (14개 지표, WD 추가)")
    print("="*80)
    gavgs={m:[] for m in METS}; savgs={m:[] for m in METS}
    for sid,data in all_r.items():
        g=data.get("gpt",{}); s=data.get("sf",{})
        if not g or not s: continue
        print(f"\n▶ {sid.upper()}")
        groups=[("F(p)",["MC","TF","OH","WD","F","F_v2"]),("ECS(p)",["RD","VD","SS","CP","FS","ECS"]),("FG(p) ★외국인친화",["LA","AB","MB","CF","CC","FG"]),("종합",["overall"])]
        for gn,ms in groups:
            print(f"  [{gn}]")
            for m in ms:
                gv=vv(g,m); sv=vv(s,m); diff=sv-gv
                mk=" ◀" if abs(diff)>=0.05 else ""
                print(f"  {LBL.get(m,m):<18} GPT:{gv:>6.3f}  SeoulFit:{sv:>6.3f}  {diff:>+7.3f}{mk}")
                gavgs[m].append(gv); savgs[m].append(sv)
        # WD 세부 breakdown -- n_unknown 비중을 바로 보기 위함 (GPT가 이 정보를
        # 아예 추적 안 해서 WD가 기계적으로 0.5 근처에 고정되는지 확인용)
        for who,r in [("GPT",g),("SeoulFit",s)]:
            wd=r.get("WD",{})
            ok,vi,un=wd.get("n_ok",0),wd.get("n_violated",0),wd.get("n_unknown",0)
            tot=ok+vi+un
            pct=f"{un/tot*100:.0f}%" if tot else "N/A"
            print(f"    {who} WD 세부: ok={ok} violated={vi} unknown={un} (unknown 비중 {pct})")
        # 이슈
        for k,lbl in [("TF","TF불가"),("MC","MC누락"),("LA","LA위반"),("AB","AB장벽"),("CF","CF누락"),("CC","CC위반"),("FS","FS문제")]:
            gd=g.get(k,{})
            items=gd.get("violations",gd.get("missing",gd.get("barriers",gd.get("unresolved",gd.get("bad",[])))))
            if items and len(items)>0:
                first=items[0]
                if isinstance(first,dict): print(f"    GPT {lbl}: {first.get('poi',first.get('day',''))}")
                else: print(f"    GPT {lbl}: {str(first)[:40]}")
        ws=g.get("LA",{}).get("ws",[])
        if ws: print(f"    GPT hallucination 의심: {', '.join(ws[:2])}")

    print("\n"+"="*80)
    print("📈  전체 평균")
    groups2=[("F(p)",["MC","TF","OH","WD","F","F_v2"]),("ECS(p)",["RD","VD","SS","CP","FS","ECS"]),("FG(p) ★외국인친화",["LA","AB","MB","CF","CC","FG"]),("종합",["overall"])]
    for gn,ms in groups2:
        print(f"  [{gn}]")
        for m in ms:
            ga=sum(gavgs[m])/len(gavgs[m]) if gavgs[m] else 0
            sa=sum(savgs[m])/len(savgs[m]) if savgs[m] else 0
            diff=sa-ga; mk=" ◀◀" if abs(diff)>=0.1 else (" ◀" if abs(diff)>=0.05 else "")
            print(f"  {LBL.get(m,m):<18} GPT:{ga:>6.3f}  SeoulFit:{sa:>6.3f}  {diff:>+7.3f}{mk}")
    print("="*80)

def wd_detection_summary(all_r):
    """WD '판정 능력' 보조 지표 -- compute_wd()의 점수(0~1) 자체는 표본이 작을 땐
    우연에 좌우되기 쉬워서(시나리오당 closed_weekday 있는 POI가 0~2개뿐이면
    +-1건 차이로 점수가 크게 흔들림) 지표 비교엔 참고용으로만 쓰고, 대신
    "애초에 판정을 시도한 비율"과 "실제로 잡아낸 위반 건수"를 표본 크기와
    무관하게 직접 비교한다. compute_wd()/WD()의 점수 계산 로직 자체는 그대로다
    -- 이미 나온 n_ok/n_violated/n_unknown을 다르게 집계할 뿐."""
    print("\n"+"="*80)
    print("🔎  WD 판정 능력 (시나리오 전체 합산) -- WD 점수(0~1)는 표본이 작아 참고용,")
    print("    detection_rate / violation_catch_count 를 메인 비교 지표로 사용")
    print("="*80)
    rows=[]
    for who in ("gpt","sf"):
        tot_ok=tot_vi=tot_unk=0
        for sid,data in all_r.items():
            r=data.get(who,{})
            wd=r.get("WD",{})
            tot_ok+=wd.get("n_ok",0); tot_vi+=wd.get("n_violated",0); tot_unk+=wd.get("n_unknown",0)
        denom=tot_ok+tot_vi+tot_unk
        detection_rate=(tot_ok+tot_vi)/denom if denom else 0.0
        rows.append((who,tot_ok,tot_vi,tot_unk,denom,detection_rate))
        label="GPT" if who=="gpt" else "SeoulFit"
        print(f"  {label:<10} n_ok={tot_ok:>3}  n_violated={tot_vi:>3}  n_unknown={tot_unk:>3}  "
              f"총 POI-Day 쌍={denom:>3}  detection_rate={detection_rate:>6.1%}  "
              f"violation_catch_count={tot_vi}")
    print("="*80)
    return rows

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--gpt_dir",default="benchmark/gpt_results")
    parser.add_argument("--sf_dir", default="benchmark/seoulfit_results")
    parser.add_argument("--no_api", action="store_true")
    parser.add_argument("--out",    default="benchmark/final_results.json")
    args=parser.parse_args()
    use_api=not args.no_api
    if use_api and not GOOGLE_API_KEY:
        print("⚠️  API 키 없음 → --no_api 모드"); use_api=False
    gd=Path(args.gpt_dir); sd=Path(args.sf_dir)
    scenarios=sorted([f.stem for f in gd.glob("scenario_*.json")]) if gd.exists() else []
    if not scenarios: print(f"❌ GPT 결과 없음: {gd}"); return
    print(f"✅ 시나리오 {len(scenarios)}개 | API:{'사용' if use_api else '미사용'}\n")
    all_r={}
    for sid in scenarios:
        print(f"{'='*50}\n🔍 {sid}...")
        all_r[sid]={}; us=SCENARIOS.get(sid,{})
        gp=gd/f"{sid}.json"
        if gp.exists():
            with open(gp,encoding="utf-8") as f: gj=norm(json.load(f))
            all_r[sid]["gpt"]=score(gj,us,use_api)
            r=all_r[sid]["gpt"]; print(f"  GPT     F={r['F']:.3f} ECS={r['ECS']:.3f} FG={r['FG']:.3f} overall={r['overall']:.3f}")
        sp=sd/f"{sid}.json"
        if sp.exists():
            with open(sp,encoding="utf-8") as f: sj=norm(json.load(f))
            all_r[sid]["sf"]=score(sj,us,use_api)
            r=all_r[sid]["sf"]; print(f"  SeoulFit F={r['F']:.3f} ECS={r['ECS']:.3f} FG={r['FG']:.3f} overall={r['overall']:.3f}")
        else: print(f"  ⚠️ SeoulFit 없음")
    print_all(all_r)
    wd_detection_summary(all_r)
    Path(args.out).parent.mkdir(parents=True,exist_ok=True)
    with open(args.out,"w",encoding="utf-8") as f: json.dump(all_r,f,ensure_ascii=False,indent=2)
    print(f"\n💾 {args.out}")

if __name__=="__main__":
    main()