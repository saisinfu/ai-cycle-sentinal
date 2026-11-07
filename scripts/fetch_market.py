"""Daily market snapshot for the app, run by GitHub Actions (Yahoo Finance via yfinance).

Writes
- data/market.json        one quote per ticker: price, 1-day change, 52-week high, drawdown,
                          200-day average, 1/3-month change, trailing P/E (+ kept 5-year average P/E)
- data/price_events.json  sharp moves in tickers the app follows:
                          day_drop  = fell >= 7% in one session
                          drawdown  = crossed 20% below its 52-week high (edge-triggered)
Tickers come from config/sectors.json (sector stocks + main-port proxies) plus market gauges.
"""
from __future__ import annotations

import json
import math
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "sectors.json"
MARKET = ROOT / "data" / "market.json"
EVENTS = ROOT / "data" / "price_events.json"

DAY_DROP = -7.0
DRAWDOWN = -20.0
REARM = -15.0  # drawdown alert re-arms after the price recovers above -15%

GAUGES = {
    "^VIX": "ดัชนีความกลัว VIX",
    "^TNX": "ดอกเบี้ยพันธบัตรสหรัฐ 10 ปี",
    "CL=F": "น้ำมันดิบ WTI",
    "DX-Y.NYB": "ดัชนีค่าเงินดอลลาร์",
    "SMH": "กองทุนหุ้นชิป",
    "XLF": "กองทุนหุ้นการเงิน",
    "XLV": "กองทุนหุ้นสุขภาพ",
    "XLP": "กองทุนหุ้นสินค้าจำเป็น",
    "PEJ": "กองทุนหุ้นท่องเที่ยวและสันทนาการ",
    "ITA": "กองทุนหุ้นอากาศยานและกลาโหม",
}


def tickers_from_config() -> tuple[list[str], dict[str, str]]:
    cfg = json.loads(CONFIG.read_text())
    names: dict[str, str] = {}
    for s in cfg["sectors"] + cfg.get("sectors_next", []):
        for st in s["stocks"]:
            names[st["ticker"]] = st.get("name", st["ticker"])
    for a in cfg.get("main_port", []):
        if a.get("proxy"):
            names[a["proxy"]] = a.get("name", a["proxy"])
    followed = list(names)
    names.update({k: v for k, v in GAUGES.items() if k not in names})
    return followed, names


def r(x, n=2):
    return None if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))) else round(float(x), n)


def snapshot(t: str) -> dict | None:
    import yfinance as yf
    for attempt in range(3):
        try:
            h = yf.Ticker(t).history(period="2y", auto_adjust=False)
            if h is None or len(h) < 30:
                raise RuntimeError("short history")
            c = h["Close"].dropna()
            last, prev = float(c.iloc[-1]), float(c.iloc[-2])
            win = c[c.index >= c.index[-1] - pd.Timedelta(days=365)]
            hi = float(win.max())

            def back(days):
                s = c[c.index <= c.index[-1] - pd.Timedelta(days=days)]
                return float(s.iloc[-1]) if len(s) else None

            m1, m3 = back(30), back(91)
            q = {
                "price": r(last), "prev_close": r(prev),
                "change_1d_pct": r((last / prev - 1) * 100),
                "high_52w": r(hi), "drawdown_pct": r((last / hi - 1) * 100),
                "ma200": r(c.tail(200).mean()) if len(c) >= 200 else None,
                "chg_1m_pct": r((last / m1 - 1) * 100) if m1 else None,
                "chg_3m_pct": r((last / m3 - 1) * 100) if m3 else None,
                "price_1m_ago": r(m1), "price_3m_ago": r(m3),
                "as_of": str(c.index[-1].date()),
                "source_url": f"https://finance.yahoo.com/quote/{t}",
            }
            try:
                info = yf.Ticker(t).get_info()
                q["currency"] = info.get("currency") or ("THB" if t.endswith(".BK") else "USD")
                pe = info.get("trailingPE")
                if isinstance(pe, (int, float)) and 0 < pe < 1000:
                    q["pe"] = r(pe)
            except Exception as e:  # noqa: BLE001
                print(f"{t}: info failed ({e})", file=sys.stderr)
                q["currency"] = "THB" if t.endswith(".BK") else "USD"
            return q
        except Exception as e:  # noqa: BLE001
            print(f"{t}: attempt {attempt} failed ({e})", file=sys.stderr)
            time.sleep(4)
    return None


def main() -> None:
    followed, names = tickers_from_config()
    old = json.loads(MARKET.read_text()) if MARKET.exists() else {"quotes": {}}
    oldq = old.get("quotes", {})
    quotes, failed = {}, []
    for t in names:
        q = snapshot(t)
        prev = oldq.get(t, {})
        if q is None:
            failed.append(t)
            if prev:
                quotes[t] = dict(prev, stale=True)
            continue
        # keep slow-moving fields maintained elsewhere
        for k in ("pe_5y_avg", "pe_source_url"):
            if prev.get(k) is not None:
                q[k] = prev[k]
        if "pe" not in q and prev.get("pe") is not None:
            q["pe"] = prev["pe"]
        q["name"] = names[t]
        q["gauge"] = t not in followed
        quotes[t] = q
        print(f"{t:10s} {q['price']:>10} {q['change_1d_pct']:>7}% dd {q['drawdown_pct']}% ({q['as_of']})", flush=True)

    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    MARKET.write_text(json.dumps({"updated_at": now, "source": "Yahoo Finance (GitHub Actions)",
                                  "failed": failed, "quotes": quotes}, ensure_ascii=False, indent=1))

    # ---- price events
    ev = json.loads(EVENTS.read_text()) if EVENTS.exists() else {"events": [], "armed": {}}
    events, armed = ev.get("events", []), ev.get("armed", {})
    seen = {(e["ticker"], e["kind"], e["date"]) for e in events}
    for t in followed:
        q = quotes.get(t)
        if not q or q.get("stale"):
            continue
        d, dd, ch = q["as_of"], q.get("drawdown_pct"), q.get("change_1d_pct")
        if ch is not None and ch <= DAY_DROP and (t, "day_drop", d) not in seen:
            events.append({"date": d, "ticker": t, "name": names[t], "kind": "day_drop", "value": ch, "price": q["price"],
                           "drawdown_pct": dd,
                           "title_th": f"{t} ร่วง {abs(ch):.1f}% ในวันเดียว",
                           "detail_th": f"ปิดที่ {q['price']:,} (ก่อนหน้า {q['prev_close']:,}) ต่ำกว่าจุดสูงสุด 52 สัปดาห์ {abs(dd or 0):.1f}%"})
        if dd is not None:
            if dd <= DRAWDOWN and armed.get(t, True) and (t, "drawdown", d) not in seen:
                events.append({"date": d, "ticker": t, "name": names[t], "kind": "drawdown", "value": dd, "price": q["price"],
                               "drawdown_pct": dd,
                               "title_th": f"{t} ต่ำกว่าจุดสูงสุดเกิน 20%",
                               "detail_th": f"ราคา {q['price']:,} ต่ำกว่าจุดสูงสุด 52 สัปดาห์ ({q['high_52w']:,}) อยู่ {abs(dd):.1f}%"})
                armed[t] = False
            elif dd > REARM:
                armed[t] = True
    events = sorted(events, key=lambda e: (e["date"], e["ticker"]))[-150:]
    EVENTS.write_text(json.dumps({"updated_at": now, "rules": {"day_drop_pct": DAY_DROP, "drawdown_pct": DRAWDOWN, "rearm_pct": REARM},
                                  "armed": armed, "events": events}, ensure_ascii=False, indent=1))
    print(f"{len(quotes)} quotes, {len(failed)} failed, {len(events)} events", flush=True)
    if len(failed) > len(names) / 2:
        sys.exit(1)


if __name__ == "__main__":
    main()
