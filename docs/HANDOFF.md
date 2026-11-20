# AI-Cycle Sentinel — handoff for a new Claude account

Read this first if you are Claude in a new session or account picking up this project.
The owner is a non-technical Thai investor: talk to him in Thai, plainly, and keep the
"rule-based information, not investment advice" framing. Personal budget numbers (salary,
tax details) are deliberately NOT in this public repo — they live in the app's settings on
his phone; ask him if you need them.

## What exists

| Part | Where | Runs on |
|---|---|---|
| Android app (Flutter, Riverpod) | `app/` | phone; APK built by GitHub Actions, released as `app-v1.0.N` |
| Sector definitions, signals, rules | `config/sectors.json` (copy bundled in `app/assets/`) | read by the app at runtime — edits go live without a new APK |
| Daily sector readings | `data/<sector>.json` (`readings.json` = ai) | written by the **morning** scheduled task |
| News feed with portfolio impact | `data/news.json` | morning + evening scheduled tasks |
| Run summaries (= push notification text) | `data/briefs.json` | morning + evening scheduled tasks |
| Prices, drawdowns, 200-day line, gauges | `data/market.json` | GitHub Actions `market.yml` (Yahoo Finance) 05:20 and 19:40 Bangkok |
| Sharp price moves | `data/price_events.json` | same job: ≥7 % one-day drop, or crossing −20 % from the 52-week high |
| Backtests | `backtest/` → `backtest/results/`, summary in `data/backtest.json` | GitHub Actions `backtest.yml` on push to `backtest/*.py` |
| APK build + signing | `.github/workflows/build-apk.yml`, `app/signing/debug.keystore` | on push to `app/**` |

Scheduled tasks (Claude, cloud, auto-approve) — prompts are in `docs/tasks/`:
- `docs/tasks/morning.md` — daily 07:58 Bangkok (`CRON_TZ=Asia/Bangkok 58 7 * * *`), push notification on.
- `docs/tasks/evening.md` — daily 20:52 Bangkok (`CRON_TZ=Asia/Bangkok 52 20 * * *`), push notification on.
They must run in a session that has this repo attached with **push** access; a task created
before the repo was attached failed with HTTP 403 on push.

## Sectors (config/sectors.json)
ai (KLAC/AVGO/ETN), finance (JPM/V/GS), health (LLY/ISRG/UNH), staples (COST/PEP/MCD),
travel (BKNG/MAR/ABNB), space (LMT/RKLB/ASTS), gold (GLD/GDX; drivers: real yield, dollar, central-bank buying, ETF flows, breakeven inflation; also Thai gold-bar price and USD/THB). Main port: gold (GLD), S&P 500 (SPY),
NASDAQ (QQQ), KKP.BK. Each sector: 5 signals, clamped linear 0–100 score, weighted index,
zones EXPANSION ≥70 / EARLY_WARNING / DIGESTION <40 with a ±3 dead-band. New sectors are added
under `sectors_next` first (collected but hidden), then promoted with
`python scripts/new_sectors.py --promote` once data exists.

## Decisions that came from evidence (keep them)
1. **35-year finance backtest** (`backtest/finance_backtest.py`, data from DBnomics/Fed because FRED
   blocks GitHub runners): the sector index barely predicts 12-month returns (rank corr ≈ 0);
   pausing/selling on signals lost 0.3–1.0 %/yr vs plain DCA. → **Rules v2: never pause or sell;
   every zone keeps buying and only tilts weights; DIGESTION keeps 20 % of the sector budget as cash.**
2. **Index v3 attempt** (`finance_v3.py`, signals picked on pre-2010 data): +0.30 corr in-sample,
   ~0 / negative after 2010 → not adopted. Only credit-card delinquency held up in both periods.
   Advice given: stop searching for timing signals (overfitting risk).
3. **Flexible budget** (`backtest/dynamic_budget.py`, 11 assets, 15–40 years): buying more after
   drawdowns from a cash reserve ≈ plain DCA (median −0.04 %/yr for "dip_only"). Adopted because
   the owner wants dynamic investing; the app says honestly it does not add return.
   App default `dip_only`: within 10 % of the 52-week high ×0.9 (10 % to reserve), −10…−20 % ×1.5,
   below −20 % ×2.5, extra funded from the reserve, reserve capped at 6 months of base.
4. Sector scores measure fundamentals, not prices; price pressure is shown separately
   (market pulse card, stock price card, price events).

## App structure (app/lib)
`data/` engine (scoring, hysteresis, attribution, alerts, zone plans), budget + tax (Thai 2569
brackets, ThaiESG/RMF), flex (flexible budget), feed (news, price events, briefs), backtest model,
repository (raw.githubusercontent.com fetch + shared_preferences cache). `ui/` overview, sector,
budget, alerts (news / price / signal filters + briefs link), briefs, news detail, backtest,
method, tax, settings. Version in `app/pubspec.yaml`; bump it with each app change.

## Owner preferences
- Thai UI and messages, non-technical explanations, provenance (source + reason) for every number.
- Wants: more sectors, important-news alerts with impact analysis, price-aware guidance,
  flexible (not fixed) monthly investing, everything visible inside the app.
- Thai stocks are not a focus unless credibly worth watching.
