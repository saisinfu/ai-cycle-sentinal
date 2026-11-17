# ตั้งงานอัตโนมัติในบัญชี Claude ใหม่

ข้อความด้านล่างนี้ให้คัดลอกไปวางในแชตแรกของบัญชีใหม่ (ใน Claude Code บนเว็บ โดยเลือก repo `saisinfu/ai-cycle-sentinal`)

---

ช่วยรับช่วงโปรเจกต์ AI-Cycle Sentinel ต่อ:
1. อ่าน `docs/HANDOFF.md` ใน repo saisinfu/ai-cycle-sentinal ให้เข้าใจระบบทั้งหมดก่อน
2. สร้าง scheduled task 2 งาน โดยใช้ข้อความใน `docs/tasks/` เป็นคำสั่งของแต่ละงานแบบคำต่อคำ ทั้งสองงานต้องเปิดแจ้งเตือนเข้ามือถือ และอนุมัติอัตโนมัติ:
   - "AI Sentinel – morning data & news" เวลา `CRON_TZ=Asia/Bangkok 58 7 * * *` ใช้ `docs/tasks/morning.md`
   - "AI Sentinel – evening news check" เวลา `CRON_TZ=Asia/Bangkok 52 20 * * *` ใช้ `docs/tasks/evening.md`
3. ให้แน่ใจว่างานทั้งสองเขียน repo นี้ได้ (มีสิทธิ์ push) แล้วสั่งรันรอบทดสอบทันที 1 ครั้ง
4. เช็กว่ามี commit ใหม่ใน repo (`data: …` หรือ `news: … evening`) แล้วบอกผลเป็นภาษาไทย

---

เมื่อบัญชีใหม่ยืนยันว่ารอบทดสอบบันทึกสำเร็จแล้ว ค่อยลบงานเดิมในบัญชีเก่า เพื่อไม่ให้รันซ้ำสองรอบ
