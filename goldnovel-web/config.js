// ============================================================
// การตั้งค่าเว็บไซต์ GoldNovel
// วิธีใช้งาน: นำค่า Project URL และ anon public key จาก Supabase
// มาวางแทนที่ช่องว่างด้านล่าง (ถ้ายังไม่ใส่ เว็บจะทำงานในโหมดทดลองให้ก่อน)
// ============================================================

window.GOLDNOVEL_CONFIG = {
  siteName: "GoldNovel",

  // 1. คัดลอกมาจาก Supabase -> Project Settings -> API
  supabaseUrl: "https://hsuknzkpnkqxbplbqfys.supabase.co",
  supabaseAnonKey: "sb_publishable_veIGFexTwkkavKdTzCProg_ickyIxZp",

  // 2. ข้อมูลรับเงินของคุณ (แสดงบนหน้าเติมเหรียญ)
  promptpayNumber: "080-9810438",
  promptpayAccountName: "นายพีรวัส วิสิฐธันยธร",
  truemoneyPhone: "080-9810438",

  // 3. โบนัสเติมเหรียญ (%) เช่น 20 หมายถึงเติม 100 ได้ 120 เหรียญ (ใส่ 0 ถ้าไม่มีโปร)
  topupBonusPercent: 10%
};
