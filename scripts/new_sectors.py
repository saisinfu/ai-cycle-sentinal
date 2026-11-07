"""One-off: add the health, staples, travel and space sectors to config/sectors.json under
"sectors_next" (collected by the daily task but not yet shown by the app). Promote them to
"sectors" with --promote once each has at least one reading."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CFG = ROOT / "config" / "sectors.json"

NOTE = ("กฎตั้งต้นที่ Claude ร่าง (ยังไม่ได้ทดสอบย้อนหลัง) ใช้หลักเดียวกับหมวดอื่น: DCA ต่อทุกโซน ไม่หยุดไม่ขาย "
        "ปรับแค่น้ำหนักไปหาหุ้นที่ทนกว่า และกันเงินสด 20% ในช่วงย่อยการลงทุน")


def sig(key, field, label, label_en, short, weight, worst, best, display, rng, why, source, url, freq, kind="data"):
    return {"key": key, "field": field, "label": label, "label_en": label_en, "short": short, "weight": weight,
            "worst": worst, "best": best, "display": display, "range": rng, "why": why, "source": source,
            "source_url": url, "frequency": freq, "kind": kind}


def zone_rules(base, w, d):
    return {"X": {t: ["BUY_DCA", v] for t, v in base.items()},
            "W": {t: list(a) for t, a in w.items()},
            "D": {t: list(a) for t, a in d.items()}}


HEALTH = {
    "id": "health", "name": "สุขภาพ / Health & Wellness", "icon": "health", "data": "data/health.json",
    "confidence": "medium",
    "confidence_note": "3 จาก 5 สัญญาณเป็นตัวเลขรายไตรมาสจากงบบริษัท 1 ตัวเป็นค่าประเมิน (ความเสี่ยงนโยบาย) · ยังไม่ได้ทดสอบย้อนหลัง",
    "summary": {
        "X": "ความต้องการยาและบริการสุขภาพโตดี ต้นทุนประกันคุมได้ · DCA ตามน้ำหนักปกติ",
        "W": "มีแรงกดดันบางด้าน เช่น ต้นทุนรักษาสูงหรือความเสี่ยงนโยบายราคายา · DCA ต่อ แต่เอียงไปหาธุรกิจที่ทนกว่า",
        "D": "ต้นทุนหรือนโยบายกดดันกำไรทั้งกลุ่ม · DCA ต่อ 80% ของงบ ไม่ขาย กันเงินสด 20% ไว้ซื้อเพิ่ม",
    },
    "signals": [
        sig("glp1_demand", "lly_revenue_growth_yoy_pct", "ยอดขาย Eli Lilly (ยา GLP-1)", "Eli Lilly revenue growth", "ยอดขายยา GLP-1",
            0.25, 0, 40, "{lly_revenue_growth_yoy_pct:+1}% เทียบปีก่อน", "0% → +40%",
            "ยาลดน้ำหนัก/เบาหวานกลุ่ม GLP-1 เป็นตัวขับเคลื่อนใหญ่ที่สุดของกลุ่มสุขภาพตอนนี้",
            "งบไตรมาส Eli Lilly", "https://investor.lilly.com/financial-information/quarterly-results", "รายไตรมาส"),
        sig("insurer_cost", "unh_medical_care_ratio_pct", "สัดส่วนค่ารักษาของ UnitedHealth", "UnitedHealth medical care ratio", "ต้นทุนค่ารักษา",
            0.20, 92, 82, "{unh_medical_care_ratio_pct:1}% ของเบี้ย", "92% → 82%",
            "ยิ่งต่ำ ประกันสุขภาพยิ่งมีกำไร ถ้าพุ่งสูงแปลว่าคนใช้บริการมากกว่าที่คาด",
            "งบไตรมาส UnitedHealth", "https://www.unitedhealthgroup.com/investors.html", "รายไตรมาส"),
        sig("surgery_volume", "isrg_procedure_growth_yoy_pct", "จำนวนผ่าตัดด้วยหุ่นยนต์ da Vinci", "Intuitive da Vinci procedure growth", "ผ่าตัดด้วยหุ่นยนต์",
            0.20, 5, 20, "{isrg_procedure_growth_yoy_pct:+1}% เทียบปีก่อน", "+5% → +20%",
            "สะท้อนความต้องการผ่าตัดและการลงทุนของโรงพยาบาล",
            "งบไตรมาส Intuitive Surgical", "https://isrg.intuitive.com/", "รายไตรมาส"),
        sig("policy_risk", "hc_policy_risk", "ความเสี่ยงนโยบายสุขภาพสหรัฐ", "US health policy risk", "ความเสี่ยงนโยบาย",
            0.20, 8, 2, "{hc_policy_risk:1}/10", "8 → 2 (ยิ่งต่ำยิ่งดี)",
            "การคุมราคายา, Medicare, ภาษีนำเข้ายา กระทบกำไรทั้งกลุ่มได้เร็ว",
            "Claude ประเมินจากข่าวนโยบาย (CMS, ทำเนียบขาว, สภาคองเกรส)", "https://www.cms.gov/newsroom", "รายวัน", "estimate"),
        sig("hc_jobs", "healthcare_jobs_growth_yoy_pct", "การจ้างงานสาธารณสุขสหรัฐ", "US health care employment growth", "จ้างงานสาธารณสุข",
            0.15, 0.5, 4.0, "{healthcare_jobs_growth_yoy_pct:+1}% เทียบปีก่อน", "+0.5% → +4.0%",
            "จ้างงานเพิ่ม = ความต้องการบริการสุขภาพยังโต",
            "FRED: CES6562000001", "https://fred.stlouisfed.org/series/CES6562000001", "รายเดือน"),
    ],
    "stocks": [{"ticker": "LLY", "name": "Eli Lilly"}, {"ticker": "ISRG", "name": "Intuitive Surgical"},
               {"ticker": "UNH", "name": "UnitedHealth Group"}],
    "rules": zone_rules({"LLY": 40, "ISRG": 30, "UNH": 30},
                        {"LLY": ["BUY_DCA", 35], "ISRG": ["BUY_DCA", 25], "UNH": ["OVERWEIGHT_DCA", 40]},
                        {"LLY": ["BUY_DCA", 30], "ISRG": ["BUY_DCA", 20], "UNH": ["OVERWEIGHT_DCA", 30]}),
    "reasons": {
        "X": {"LLY": "ผู้นำยา GLP-1 ยอดขายโตเร็วที่สุดในกลุ่มยาใหญ่", "ISRG": "ผู้นำหุ่นยนต์ผ่าตัด รายได้ประจำจากอุปกรณ์สิ้นเปลือง",
              "UNH": "ประกันสุขภาพรายใหญ่ที่สุดของสหรัฐ ได้ประโยชน์เมื่อต้นทุนรักษาคุมได้"},
        "W": {"LLY": "ยัง DCA ต่อ ลดจาก 40% เหลือ 35% เพราะราคาสะท้อนการเติบโตไว้สูง", "ISRG": "ยัง DCA ต่อ ลดจาก 30% เหลือ 25% หุ้นมูลค่าสูงผันผวนกว่า",
              "UNH": "เพิ่มจาก 30% เป็น 40% ราคาไม่แพงเมื่อเทียบกำไร และรายได้ผูกกับเบี้ยประกันที่ต่อสัญญาทุกปี"},
        "D": {"LLY": "ยัง DCA ต่อ 30% (ไม่หยุด ไม่ขาย)", "ISRG": "ยัง DCA ต่อในน้ำหนักต่ำ 20%",
              "UNH": "คงน้ำหนักหลัก 30% อีก 20% ของงบหมวดเก็บเป็นเงินสดสำรอง"},
    },
    "alerts": [
        {"field": "unh_medical_care_ratio_pct", "op": ">", "value": 90, "zone": "D", "title": "ต้นทุนค่ารักษาพุ่ง",
         "message": "สัดส่วนค่ารักษาของ UnitedHealth {unh_medical_care_ratio_pct:1}% (เกณฑ์แจ้งเตือน: เกิน 90%)"},
        {"field": "hc_policy_risk", "op": ">", "value": 8, "zone": "D", "title": "ความเสี่ยงนโยบายสูง",
         "message": "คะแนนความเสี่ยงนโยบาย {hc_policy_risk:1}/10 (เกณฑ์แจ้งเตือน: เกิน 8)"},
    ],
}

STAPLES = {
    "id": "staples", "name": "อาหาร / ของใช้จำเป็น", "icon": "food", "data": "data/staples.json",
    "confidence": "high",
    "confidence_note": "ทุกสัญญาณเป็นตัวเลขทางการหรือจากบริษัท (รายเดือน) · ยังไม่ได้ทดสอบย้อนหลัง",
    "summary": {
        "X": "ผู้บริโภคมั่นใจ ใช้จ่ายร้านอาหารโต ต้นทุนอาหารนิ่ง · DCA ตามน้ำหนักปกติ",
        "W": "ผู้บริโภคเริ่มระวังหรือต้นทุนวัตถุดิบสูงขึ้น · DCA ต่อ แต่เอียงไปหาสินค้าจำเป็นที่ขึ้นราคาได้",
        "D": "ผู้บริโภคตึงตัวและต้นทุนกดดันกำไร · DCA ต่อ 80% ของงบ ไม่ขาย กันเงินสด 20% ไว้ซื้อเพิ่ม",
    },
    "signals": [
        sig("sentiment", "consumer_sentiment", "ความเชื่อมั่นผู้บริโภค (U. Michigan)", "UMich consumer sentiment", "ความเชื่อมั่นผู้บริโภค",
            0.20, 50, 90, "{consumer_sentiment:1}", "50 → 90",
            "ผู้บริโภคมั่นใจ = กล้าใช้จ่ายกินข้างนอกและซื้อของมากขึ้น",
            "FRED: UMCSENT", "https://fred.stlouisfed.org/series/UMCSENT", "รายเดือน"),
        sig("restaurant_sales", "food_services_sales_yoy_pct", "ยอดขายร้านอาหารสหรัฐ", "Food services & drinking places sales", "ยอดขายร้านอาหาร",
            0.20, 0, 8, "{food_services_sales_yoy_pct:+1}% เทียบปีก่อน", "0% → +8%",
            "วัดการใช้จ่ายกินข้างนอกโดยตรง (เกี่ยวกับ McDonald's)",
            "FRED: RSFSDP", "https://fred.stlouisfed.org/series/RSFSDP", "รายเดือน"),
        sig("food_inflation", "food_at_home_cpi_yoy_pct", "เงินเฟ้ออาหารในบ้าน", "Food at home CPI", "เงินเฟ้ออาหาร",
            0.20, 6, 1.5, "{food_at_home_cpi_yoy_pct:+1}% เทียบปีก่อน", "6% → 1.5% (ยิ่งต่ำยิ่งดี)",
            "อาหารแพงเร็ว = คนซื้อน้อยลงหรือหันไปของถูก ยอดขายแบรนด์ใหญ่ลดลง",
            "FRED: CUSR0000SAF11", "https://fred.stlouisfed.org/series/CUSR0000SAF11", "รายเดือน"),
        sig("input_cost", "fao_food_price_yoy_pct", "ราคาวัตถุดิบอาหารโลก (FAO)", "FAO Food Price Index", "ต้นทุนวัตถุดิบ",
            0.20, 20, -5, "{fao_food_price_yoy_pct:+1}% เทียบปีก่อน", "+20% → −5% (ยิ่งต่ำยิ่งดี)",
            "วัตถุดิบถูกลง = กำไรต่อหน่วยของผู้ผลิตอาหารดีขึ้น",
            "FAO Food Price Index", "https://www.fao.org/worldfoodsituation/foodpricesindex/en/", "รายเดือน"),
        sig("costco_comps", "costco_us_comp_sales_pct", "ยอดขายสาขาเดิม Costco สหรัฐ (ไม่รวมน้ำมัน)", "Costco US comparable sales ex-gas", "ยอดขาย Costco",
            0.20, 0, 8, "{costco_us_comp_sales_pct:+1}%", "0% → +8%",
            "ตัวชี้วัดรายเดือนที่เร็วที่สุดของการจับจ่ายของใช้จำเป็น",
            "Costco รายงานยอดขายรายเดือน", "https://investor.costco.com/", "รายเดือน"),
    ],
    "stocks": [{"ticker": "COST", "name": "Costco Wholesale"}, {"ticker": "PEP", "name": "PepsiCo"},
               {"ticker": "MCD", "name": "McDonald's"}],
    "rules": zone_rules({"COST": 35, "PEP": 30, "MCD": 35},
                        {"COST": ["BUY_DCA", 35], "PEP": ["OVERWEIGHT_DCA", 35], "MCD": ["BUY_DCA", 30]},
                        {"COST": ["BUY_DCA", 30], "PEP": ["OVERWEIGHT_DCA", 30], "MCD": ["BUY_DCA", 20]}),
    "reasons": {
        "X": {"COST": "ยอดสมาชิกและยอดขายโตสม่ำเสมอ", "PEP": "เครื่องดื่มและขนมแบรนด์ใหญ่ ปันผลสม่ำเสมอ",
              "MCD": "ได้ประโยชน์เมื่อคนกินข้างนอกมากขึ้น"},
        "W": {"COST": "ยัง DCA ต่อ 35% คนหันมาซื้อของคุ้มค่าเมื่อเศรษฐกิจชะลอ", "PEP": "เพิ่มจาก 30% เป็น 35% สินค้าจำเป็นราคาไม่แพงเทียบกำไร",
              "MCD": "ยัง DCA ต่อ ลดจาก 35% เหลือ 30% ร้านอาหารอ่อนไหวต่อกำลังซื้อ"},
        "D": {"COST": "ยัง DCA ต่อ 30% (ไม่หยุด ไม่ขาย)", "PEP": "คงน้ำหนักหลัก 30% อีก 20% ของงบหมวดเก็บเป็นเงินสดสำรอง",
              "MCD": "ยัง DCA ต่อในน้ำหนักต่ำ 20%"},
    },
    "alerts": [
        {"field": "food_at_home_cpi_yoy_pct", "op": ">", "value": 5, "zone": "D", "title": "เงินเฟ้ออาหารสูง",
         "message": "ราคาอาหารในบ้าน {food_at_home_cpi_yoy_pct:+1}% เทียบปีก่อน (เกณฑ์แจ้งเตือน: เกิน 5%)"},
        {"field": "consumer_sentiment", "op": "<", "value": 55, "zone": "D", "title": "ผู้บริโภคขาดความมั่นใจ",
         "message": "ความเชื่อมั่นผู้บริโภค {consumer_sentiment:1} (เกณฑ์แจ้งเตือน: ต่ำกว่า 55)"},
    ],
}

TRAVEL = {
    "id": "travel", "name": "ท่องเที่ยว / การเดินทาง", "icon": "travel", "data": "data/travel.json",
    "confidence": "medium",
    "confidence_note": "สัญญาณรายวัน (TSA, น้ำมัน) สดดี แต่ RevPAR โรงแรมมาจากรายงานข่าว CoStar · ยังไม่ได้ทดสอบย้อนหลัง",
    "summary": {
        "X": "คนเดินทางมากขึ้น โรงแรมขึ้นราคาได้ รายได้คนยังโต · DCA ตามน้ำหนักปกติ",
        "W": "ความต้องการเดินทางเริ่มชะลอหรือน้ำมันแพงขึ้น · DCA ต่อ แต่เอียงไปหาแพลตฟอร์มจองที่ทนกว่า",
        "D": "การเดินทางหดตัวหรือกำลังซื้อตึง · DCA ต่อ 80% ของงบ ไม่ขาย กันเงินสด 20% ไว้ซื้อเพิ่ม",
    },
    "signals": [
        sig("tsa", "tsa_throughput_yoy_pct", "ผู้โดยสารผ่านจุดตรวจ TSA", "TSA checkpoint throughput", "ผู้โดยสารสนามบิน",
            0.25, -5, 5, "{tsa_throughput_yoy_pct:+1}% เทียบปีก่อน (เฉลี่ย 7 วัน)", "−5% → +5%",
            "นับคนบินจริงทุกวันในสหรัฐ เร็วที่สุดในการบอกความต้องการเดินทาง",
            "TSA checkpoint numbers", "https://www.tsa.gov/travel/passenger-volumes", "รายวัน"),
        sig("hotel", "us_hotel_revpar_yoy_pct", "รายได้ต่อห้องโรงแรมสหรัฐ (RevPAR)", "US hotel RevPAR", "RevPAR โรงแรม",
            0.20, -5, 5, "{us_hotel_revpar_yoy_pct:+1}% เทียบปีก่อน", "−5% → +5%",
            "รวมทั้งอัตราเข้าพักและราคาห้อง สะท้อนกำไรโรงแรมโดยตรง",
            "CoStar/STR รายสัปดาห์ (ผ่านข่าว)", "https://www.costar.com/", "รายสัปดาห์"),
        sig("oil", "wti_usd", "ราคาน้ำมันดิบ WTI", "WTI crude oil", "ราคาน้ำมัน",
            0.15, 100, 60, "${wti_usd:1}/บาร์เรล", "$100 → $60 (ยิ่งต่ำยิ่งดี)",
            "น้ำมันแพง = ตั๋วเครื่องบินและค่าเดินทางแพง คนเที่ยวน้อยลง",
            "Yahoo Finance: CL=F (data/market.json)", "https://finance.yahoo.com/quote/CL=F", "รายวัน"),
        sig("income", "real_disposable_income_yoy_pct", "รายได้หลังภาษีที่แท้จริงของคนสหรัฐ", "Real disposable personal income", "รายได้คนสหรัฐ",
            0.20, 0, 4, "{real_disposable_income_yoy_pct:+1}% เทียบปีก่อน", "0% → +4%",
            "การท่องเที่ยวเป็นรายจ่ายที่คนตัดก่อนเมื่อรายได้ไม่โต",
            "FRED: DSPIC96", "https://fred.stlouisfed.org/series/DSPIC96", "รายเดือน"),
        sig("bookings", "bkng_room_nights_growth_yoy_pct", "จำนวนคืนที่จองผ่าน Booking", "Booking Holdings room nights", "ยอดจองห้องพัก",
            0.20, 0, 12, "{bkng_room_nights_growth_yoy_pct:+1}% เทียบปีก่อน", "0% → +12%",
            "แพลตฟอร์มจองที่ใหญ่ที่สุดในโลก สะท้อนการเดินทางทั่วโลก",
            "งบไตรมาส Booking Holdings", "https://ir.bookingholdings.com/", "รายไตรมาส"),
    ],
    "stocks": [{"ticker": "BKNG", "name": "Booking Holdings"}, {"ticker": "MAR", "name": "Marriott International"},
               {"ticker": "ABNB", "name": "Airbnb"}],
    "rules": zone_rules({"BKNG": 40, "MAR": 30, "ABNB": 30},
                        {"BKNG": ["OVERWEIGHT_DCA", 45], "MAR": ["BUY_DCA", 30], "ABNB": ["BUY_DCA", 25]},
                        {"BKNG": ["OVERWEIGHT_DCA", 40], "MAR": ["BUY_DCA", 25], "ABNB": ["BUY_DCA", 15]}),
    "reasons": {
        "X": {"BKNG": "แพลตฟอร์มจองที่ใหญ่และทำกำไรดีที่สุด", "MAR": "เครือโรงแรมใหญ่ ได้ค่าธรรมเนียมแฟรนไชส์ ไม่ต้องลงทุนตึกเอง",
              "ABNB": "โตเร็วจากที่พักทางเลือกและประสบการณ์ท่องเที่ยว"},
        "W": {"BKNG": "เพิ่มจาก 40% เป็น 45% กระจายทั่วโลกและกำไรสูง ทนกว่าเมื่อการเดินทางชะลอ", "MAR": "ยัง DCA ต่อ 30%",
              "ABNB": "ยัง DCA ต่อ ลดจาก 30% เหลือ 25% หุ้นเติบโตผันผวนกว่า"},
        "D": {"BKNG": "คงน้ำหนักหลัก 40% อีก 20% ของงบหมวดเก็บเป็นเงินสดสำรอง", "MAR": "ยัง DCA ต่อ 25% (ไม่หยุด ไม่ขาย)",
              "ABNB": "ยัง DCA ต่อในน้ำหนักต่ำ 15%"},
    },
    "alerts": [
        {"field": "tsa_throughput_yoy_pct", "op": "<", "value": -3, "zone": "D", "title": "คนเดินทางทางอากาศลดลง",
         "message": "ผู้โดยสาร TSA {tsa_throughput_yoy_pct:+1}% เทียบปีก่อน (เกณฑ์แจ้งเตือน: ต่ำกว่า −3%)"},
        {"field": "wti_usd", "op": ">", "value": 95, "zone": "D", "title": "น้ำมันแพง",
         "message": "WTI ${wti_usd:1}/บาร์เรล (เกณฑ์แจ้งเตือน: เกิน $95)"},
    ],
}

SPACE = {
    "id": "space", "name": "อวกาศ / กลาโหม", "icon": "space", "data": "data/space.json",
    "confidence": "low",
    "confidence_note": "งบกลาโหมเป็นค่าประเมิน และหุ้นอวกาศ (RKLB, ASTS) ผันผวนสูงมาก ราคาขึ้นกับข่าวมากกว่าตัวเลข · ยังไม่ได้ทดสอบย้อนหลัง",
    "summary": {
        "X": "งบกลาโหมโต การยิงจรวดถี่ขึ้น ต้นทุนเงินไม่แพง · DCA ตามน้ำหนักปกติ",
        "W": "งบหรือดอกเบี้ยเริ่มกดดัน · DCA ต่อ แต่เอียงไปหาผู้รับเหมากลาโหมรายใหญ่ที่มีกำไรแน่นอน",
        "D": "งบสะดุดหรือดอกเบี้ยพุ่ง หุ้นเก็งกำไรเสี่ยงสูง · DCA ต่อ 80% ของงบ ไม่ขาย กันเงินสด 20% ไว้ซื้อเพิ่ม",
    },
    "signals": [
        sig("defense_budget", "defense_budget_score", "สถานะงบกลาโหมสหรัฐ", "US defense budget outlook", "งบกลาโหม",
            0.25, 2, 8, "{defense_budget_score:1}/10", "2 → 8",
            "งบผ่านสภาและเพิ่มขึ้น = สัญญาใหม่สำหรับผู้รับเหมา ถ้าต้องใช้งบชั่วคราว (CR) โครงการใหม่จะเลื่อน",
            "Claude ประเมินจากข่าว NDAA/งบประมาณ", "https://www.congress.gov/", "รายสัปดาห์", "estimate"),
        sig("gpr", "geopolitical_risk_index", "ดัชนีความเสี่ยงภูมิรัฐศาสตร์ (GPR)", "Geopolitical Risk Index", "ความเสี่ยงภูมิรัฐศาสตร์",
            0.15, 80, 180, "{geopolitical_risk_index:0}", "80 → 180",
            "ความขัดแย้งสูง = ประเทศต่างๆ เพิ่มงบกลาโหม (ดีต่อหุ้นกลาโหม แต่ไม่ดีต่อตลาดโดยรวม)",
            "Caldara & Iacoviello GPR Index", "https://www.matteoiacoviello.com/gpr.htm", "รายเดือน"),
        sig("launches", "orbital_launches_ytd_growth_pct", "จำนวนการยิงจรวดขึ้นวงโคจรทั่วโลก", "Global orbital launches YTD", "การยิงจรวด",
            0.20, -10, 25, "{orbital_launches_ytd_growth_pct:+0}% เทียบปีก่อน (สะสมทั้งปี)", "−10% → +25%",
            "ยิงถี่ขึ้น = ความต้องการดาวเทียมและบริการขนส่งอวกาศโต",
            "สถิติการยิงจรวด (Next Spaceflight / Jonathan McDowell)", "https://nextspaceflight.com/launches/past/", "รายเดือน"),
        sig("rklb_backlog", "rklb_backlog_growth_yoy_pct", "งานในมือของ Rocket Lab", "Rocket Lab backlog growth", "งานในมือ Rocket Lab",
            0.20, 0, 60, "{rklb_backlog_growth_yoy_pct:+0}% เทียบปีก่อน", "0% → +60%",
            "งานในมือโต = รายได้อนาคตชัดขึ้นสำหรับบริษัทอวกาศขนาดกลาง",
            "งบไตรมาส Rocket Lab", "https://investors.rocketlabusa.com/", "รายไตรมาส"),
        sig("rates", "us10y_change_3m_pp", "ดอกเบี้ยพันธบัตร 10 ปี เปลี่ยนใน 3 เดือน", "US 10Y yield 3-month change", "ทิศทางดอกเบี้ย",
            0.20, 0.75, -0.75, "{us10y_change_3m_pp:+2} จุด", "+0.75 → −0.75 (ยิ่งลดยิ่งดี)",
            "หุ้นอวกาศยังขาดทุน มูลค่าอยู่ที่กำไรอนาคต ดอกเบี้ยขึ้นจึงกดราคาแรง",
            "Yahoo Finance: ^TNX (data/market.json)", "https://finance.yahoo.com/quote/%5ETNX", "รายวัน"),
    ],
    "stocks": [{"ticker": "LMT", "name": "Lockheed Martin"}, {"ticker": "RKLB", "name": "Rocket Lab"},
               {"ticker": "ASTS", "name": "AST SpaceMobile"}],
    "rules": zone_rules({"LMT": 40, "RKLB": 35, "ASTS": 25},
                        {"LMT": ["OVERWEIGHT_DCA", 50], "RKLB": ["BUY_DCA", 30], "ASTS": ["BUY_DCA", 20]},
                        {"LMT": ["OVERWEIGHT_DCA", 45], "RKLB": ["BUY_DCA", 25], "ASTS": ["BUY_DCA", 10]}),
    "reasons": {
        "X": {"LMT": "ผู้รับเหมากลาโหมรายใหญ่ที่สุด กำไรและปันผลสม่ำเสมอ", "RKLB": "ผู้ให้บริการยิงจรวดขนาดเล็ก-กลาง รายได้โตเร็ว",
              "ASTS": "ดาวเทียมเชื่อมมือถือโดยตรง ศักยภาพสูงแต่ยังไม่มีกำไร"},
        "W": {"LMT": "เพิ่มจาก 40% เป็น 50% รายได้มาจากสัญญารัฐระยะยาว", "RKLB": "ยัง DCA ต่อ ลดจาก 35% เหลือ 30%",
              "ASTS": "ยัง DCA ต่อ ลดจาก 25% เหลือ 20% หุ้นเก็งกำไรผันผวนสูง"},
        "D": {"LMT": "คงน้ำหนักหลัก 45% อีก 20% ของงบหมวดเก็บเป็นเงินสดสำรอง", "RKLB": "ยัง DCA ต่อ 25% (ไม่หยุด ไม่ขาย)",
              "ASTS": "ยัง DCA ต่อในน้ำหนักต่ำ 10%"},
    },
    "alerts": [
        {"field": "defense_budget_score", "op": "<", "value": 3, "zone": "D", "title": "งบกลาโหมสะดุด",
         "message": "คะแนนงบกลาโหม {defense_budget_score:1}/10 (เกณฑ์แจ้งเตือน: ต่ำกว่า 3)"},
        {"field": "geopolitical_risk_index", "op": ">", "value": 200, "zone": "D", "title": "ความเสี่ยงสงครามสูง",
         "message": "ดัชนี GPR {geopolitical_risk_index:0} (เกณฑ์แจ้งเตือน: เกิน 200) กระทบตลาดโดยรวม"},
    ],
}

NEW = [HEALTH, STAPLES, TRAVEL, SPACE]


def main():
    c = json.loads(CFG.read_text())
    if "--promote" in sys.argv:
        nxt = c.get("sectors_next", [])
        keep = []
        for s in nxt:
            path = ROOT / s["data"]
            ok = path.exists() and json.loads(path.read_text()).get("readings")
            (c["sectors"].append(s) if ok else keep.append(s))
            print(("promoted " if ok else "kept ") + s["id"])
        c["sectors_next"] = keep
        if not keep:
            del c["sectors_next"]
    else:
        for s in NEW:
            s.update({"rules_origin": "draft", "rules_version": 2, "rules_note": NOTE})
            assert abs(sum(x["weight"] for x in s["signals"]) - 1) < 1e-9, s["id"]
        ids = {s["id"] for s in c["sectors"]}
        c["sectors_next"] = [s for s in NEW if s["id"] not in ids]
    CFG.write_text(json.dumps(c, ensure_ascii=False, indent=2))
    (ROOT / "app" / "assets" / "sectors.json").write_text(json.dumps(c, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
