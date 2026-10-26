"""Candidate finance index v3: signals picked on pre-2010 data only, judged on 2010+.

Procedure (fixed before looking at the test years):
1. Candidate signals, each with a direction set from economic reasoning, not from the data.
2. Anchors (worst/best) = 10th/90th percentile of the TRAIN period (to end-2009).
3. Keep candidates whose TRAIN correlation with next-12-month bank returns is >= 0.05
   (average of KBW bank index and JPM); weight them in proportion to that correlation.
4. Judge on the TEST period (2010+): correlation, returns by zone, and DCA strategies
   (current tilt rules, and a stronger variant) against plain DCA and against the v1 index.

Run: python backtest/finance_v3.py [--synthetic]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import finance_backtest as fb  # noqa: E402

SPLIT = pd.Timestamp("2010-01-01")
EXTRA_TICKERS = ["VWEHX", "VFITX", "HYG", "IEF"]
IC_MIN = 0.05


def ic(a: pd.Series, b: pd.Series) -> float | None:
    df = pd.concat([a, b], axis=1).dropna()
    return round(float(df.rank().corr().iloc[0, 1]), 3) if len(df) > 24 else None


def candidates(panel: pd.DataFrame, px: pd.DataFrame) -> tuple[pd.DataFrame, list[dict]]:
    c = pd.DataFrame(index=panel.index)
    c["dq_level"] = panel["cc_delinquency_pct"]
    c["dq_change_12m"] = panel["cc_delinquency_pct"] - panel["cc_delinquency_pct"].shift(12)
    c["yield_curve"] = panel["yield_curve_10y2y_pct"]
    c["loan_growth"] = panel["loan_growth_pct"]
    c["fed_policy"] = panel["fed_policy_score"]

    def r6(t):
        p = px[t].reindex(panel.index) if t in px.columns else pd.Series(np.nan, panel.index)
        return (p / p.shift(6) - 1) * 100

    def trend(t):
        p = px[t].reindex(panel.index) if t in px.columns else pd.Series(np.nan, panel.index)
        return (p / p.rolling(10).mean() - 1) * 100

    credit = r6("VWEHX") - r6("VFITX")
    alt = r6("HYG") - r6("IEF")
    c["credit_momentum_6m"] = credit.combine_first(alt)
    c["bank_trend_10m"] = trend("^BKX").combine_first(trend("XLF"))
    c["market_trend_10m"] = trend("SPY")

    specs = [
        {"key": "dq_level", "dir": -1, "label": "หนี้บัตรเครดิตค้างชำระ (ระดับ)", "live": "FRED DRCCLACBS"},
        {"key": "dq_change_12m", "dir": -1, "label": "หนี้ค้างชำระเปลี่ยนจาก 12 เดือนก่อน", "live": "FRED DRCCLACBS"},
        {"key": "credit_momentum_6m", "dir": 1, "label": "กองทุนหุ้นกู้เสี่ยงสูง vs พันธบัตรรัฐ (6 เดือน)", "live": "HYG vs IEF ผลตอบแทน 6 เดือน"},
        {"key": "bank_trend_10m", "dir": 1, "label": "หุ้นธนาคารเทียบเส้นเฉลี่ย 10 เดือน", "live": "XLF เทียบเส้นเฉลี่ย 200 วัน"},
        {"key": "market_trend_10m", "dir": 1, "label": "S&P 500 เทียบเส้นเฉลี่ย 10 เดือน", "live": "SPY เทียบเส้นเฉลี่ย 200 วัน"},
        {"key": "yield_curve", "dir": 1, "label": "ส่วนต่างดอกเบี้ย 10 ปี − 2 ปี", "live": "FRED T10Y2Y"},
        {"key": "loan_growth", "dir": 1, "label": "การเติบโตสินเชื่อ", "live": "Fed H.8"},
        {"key": "fed_policy", "dir": 1, "label": "ทิศทาง Fed (ผ่อนคลาย = ดี)", "live": "FOMC"},
    ]
    return c, specs


def anchor(c: pd.DataFrame, specs: list[dict]) -> list[dict]:
    train = c[c.index < SPLIT]
    out = []
    for s in specs:
        lo, hi = float(train[s["key"]].quantile(0.10)), float(train[s["key"]].quantile(0.90))
        worst, best = (lo, hi) if s["dir"] > 0 else (hi, lo)
        out.append(dict(s, field=s["key"], worst=round(worst, 3), best=round(best, 3), weight=1.0))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--synthetic", action="store_true")
    args = ap.parse_args()

    cfg = json.loads(fb.CONFIG.read_text())
    fin = next(s for s in cfg["sectors"] if s["id"] == "finance")
    rules_cur = fin["rules"]
    rules_prev = fin.get("rules_previous", rules_cur)

    if args.synthetic:
        f, p = fb.synthetic()
        rng = np.random.default_rng(1)
        for t in EXTRA_TICKERS + ["^BKX"]:
            idx = pd.date_range("1990-01-01", "2026-09-30", freq="D")
            p[t] = pd.Series(np.exp(np.cumsum(rng.normal(0.0002, 0.01, len(idx)))) * 10, idx)
    else:
        f, _ = fb.fetch_all()
        p = fb.prices_yahoo(fb.TICKERS + EXTRA_TICKERS)
    for k, v in p.items():
        print(f"price {k}: {v.index.min().date()} -> {v.index.max().date()}", flush=True)

    panel, _ = fb.build_panel(f)
    px = fb.monthly_returns(p)
    rf = panel["rf"]
    cand, specs = candidates(panel, px)
    specs = anchor(cand, specs)

    test_assets = [a for a in ["^BKX", "JPM"] if a in px.columns]
    report_assets = [a for a in ["XLF", "^BKX", "KBE", "JPM"] if a in px.columns]

    def fwd12(a):
        q = px[a].reindex(cand.index)
        return q.shift(-12) / q - 1

    # Score each candidate and measure TRAIN / TEST correlation.
    scores = {}
    table = []
    for s in specs:
        sc = ((cand[s["key"]] - s["worst"]) / (s["best"] - s["worst"]) * 100).clip(0, 100)
        scores[s["key"]] = sc
        tr = [ic(sc[sc.index < fb.pd.Timestamp(SPLIT)], fwd12(a)) for a in test_assets]
        te = [ic(sc[sc.index >= SPLIT], fwd12(a)) for a in test_assets]
        table.append({"key": s["key"], "label": s["label"], "dir": s["dir"], "worst": s["worst"], "best": s["best"],
                      "train_ic": fb._avg(tr), "test_ic": fb._avg(te),
                      "first": str(cand[s["key"]].first_valid_index().date()) if cand[s["key"]].first_valid_index() is not None else None})

    chosen = [t for t in table if t["train_ic"] is not None and t["train_ic"] >= IC_MIN]
    tot = sum(t["train_ic"] for t in chosen) or 1
    v3_signals = [dict(next(s for s in specs if s["key"] == t["key"]), weight=round(t["train_ic"] / tot, 3)) for t in chosen]
    print("chosen:", [(s["key"], s["weight"]) for s in v3_signals], flush=True)

    def index_of(sig):
        sub = pd.DataFrame({s["key"]: scores[s["key"]] if s["key"] in scores else
                            ((panel[s["field"]] - s["worst"]) / (s["best"] - s["worst"]) * 100).clip(0, 100) for s in sig})
        w = pd.Series({s["key"]: s["weight"] for s in sig})
        need = sub.notna().all(axis=1)
        return ((sub * w).sum(axis=1) / w.sum())[need]

    v1_idx, _ = fb.score(panel, fin["signals"])
    v1_idx = v1_idx.dropna()
    v3_idx = index_of(v3_signals) if v3_signals else pd.Series(dtype=float)

    strong = {"X": {"SECTOR": ["BUY_DCA", 100]}, "W": {"SECTOR": ["BUY_DCA", 100]}, "D": {"SECTOR": ["BUY_DCA", 50]}}

    def evaluate(idx: pd.Series, label: str) -> dict:
        if idx.empty:
            return {"label": label, "empty": True}
        z = fb.zones(idx)
        out = {"label": label, "from": str(idx.index.min().date()), "flips_test": fb.flips(z[z.index >= SPLIT]),
               "share_test": {c: round(float((z[z.index >= SPLIT] == c).mean()), 3) for c in "XWD"},
               "ic_test": {a: ic(idx[idx.index >= SPLIT], fwd12(a)) for a in report_assets},
               "ic_train": {a: ic(idx[idx.index < SPLIT], fwd12(a)) for a in report_assets},
               "forward_test": {}, "strategy_test": {}, "strategy_full": {}}
        zt = z[z.index >= SPLIT]
        for a in [a for a in ["XLF", "^BKX", "JPM"] if a in px.columns]:
            out["forward_test"][a] = fb.forward_table(zt, idx.reindex(zt.index), px[a])["by_zone"]
            one = px[[a]].rename(columns={a: "SECTOR"})
            for tag, rs in [("current_rules", fb.sector_rules(rules_cur)), ("previous_rules", fb.sector_rules(rules_prev)),
                            ("strong_tilt", strong)]:
                for period, start in [("strategy_test", SPLIT), ("strategy_full", None)]:
                    sp = fb.strategy_pair(z, one, rf, rs, start=start)
                    if sp:
                        out[period].setdefault(a, {})[tag] = {
                            "irr_diff_pp": round(sp["irr_diff_pp"], 2), "plain_irr": round(sp["plain"]["irr"] * 100, 2),
                            "dd_rules": round(sp["rules"]["max_dd"] * 100, 1), "dd_plain": round(sp["plain"]["max_dd"] * 100, 1),
                            "from": sp["from"]}
        return out

    res = {
        "generated": pd.Timestamp.utcnow().isoformat(),
        "synthetic": args.synthetic,
        "split": str(SPLIT.date()),
        "procedure": __doc__,
        "candidates": table,
        "chosen": [{k: s[k] for k in ("key", "label", "weight", "worst", "best", "live")} for s in v3_signals],
        "v1": evaluate(v1_idx, "v1 (current app index)"),
        "v3": evaluate(v3_idx, "v3 candidate"),
        "latest_v3": None if v3_idx.empty else {"date": str(v3_idx.index[-1].date()), "index": round(float(v3_idx.iloc[-1]), 1),
                                                 "zone": fb.zones(v3_idx).iloc[-1],
                                                 "values": {s["key"]: round(float(cand[s["key"]].dropna().iloc[-1]), 2) for s in v3_signals}},
    }
    fb.OUT.mkdir(parents=True, exist_ok=True)
    (fb.OUT / "finance_v3.json").write_text(json.dumps(res, indent=1, ensure_ascii=False, default=str))
    pd.concat({"v1": v1_idx, "v3": v3_idx}, axis=1).join(cand).round(3).to_csv(fb.OUT / "finance_v3_monthly.csv")
    chart(v1_idx, v3_idx, px)
    print(json.dumps({k: res[k] for k in ("candidates", "chosen", "latest_v3")}, indent=1, ensure_ascii=False, default=str))
    for k in ("v1", "v3"):
        print(k, json.dumps({x: res[k].get(x) for x in ("ic_test", "share_test", "flips_test", "strategy_test")}, default=str))


def chart(v1, v3, px):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, (a1, a2) = plt.subplots(2, 1, figsize=(11, 7), sharex=True)
    fig.patch.set_facecolor("#121212")
    for ax in (a1, a2):
        ax.set_facecolor("#1E1E1E")
        ax.tick_params(colors="#A0A0A0")
        for s in ax.spines.values():
            s.set_color("#333")
        ax.axvspan(SPLIT, px.index.max(), color="#8AB4F8", alpha=.06, lw=0)
    a1.plot(v1.index, v1.values, color="#A0A0A0", lw=1, label="v1 (current)")
    if len(v3):
        a1.plot(v3.index, v3.values, color="#00E676", lw=1.2, label="v3 candidate")
    a1.axhline(70, color="#00E676", lw=.5, ls="--")
    a1.axhline(40, color="#FF5252", lw=.5, ls="--")
    a1.legend(facecolor="#1E1E1E", labelcolor="#F5F5F5", edgecolor="#333")
    a1.set_ylabel("Index", color="#A0A0A0")
    asset = "^BKX" if "^BKX" in px.columns else "XLF"
    q = px[asset].dropna()
    a2.plot(q.index, q.values, color="#F5F5F5", lw=1)
    a2.set_yscale("log")
    a2.set_ylabel(f"{asset} (log)", color="#A0A0A0")
    a2.text(SPLIT, q.max(), "  test period (not used to choose signals)", color="#8AB4F8", fontsize=9, va="top")
    fig.tight_layout()
    fig.savefig(fb.OUT / "finance_v3.png", dpi=110, facecolor=fig.get_facecolor())


if __name__ == "__main__":
    main()
