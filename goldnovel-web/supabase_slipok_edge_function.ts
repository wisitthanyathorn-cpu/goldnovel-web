// ============================================================
// GoldNovel — Supabase Edge Function สำหรับตรวจสลิปอัตโนมัติผ่าน SlipOK
// (ใช้เมื่อคุณสมัคร SlipOK และต้องการให้เติมเหรียญอัตโนมัติ 100%)
// ============================================================
// การตั้งค่า Environment Variables ใน Supabase Dashboard -> Edge Functions:
// - SLIPOK_BRANCH_ID = รหัสสาขาจาก SlipOK
// - SLIPOK_API_KEY   = รหัส API Key จาก SlipOK
// - SUPABASE_URL     = Project URL ของคุณ
// - SUPABASE_SERVICE_ROLE_KEY = Service Role Key จาก Project Settings -> API

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { slipUrl, userId, bonusPercent = 20 } = await req.json();
    const branchId = Deno.env.get("SLIPOK_BRANCH_ID");
    const apiKey = Deno.env.get("SLIPOK_API_KEY");

    if (!branchId || !apiKey) {
      throw new Error("ยังไม่ได้ตั้งค่า SLIPOK_BRANCH_ID หรือ SLIPOK_API_KEY");
    }

    // 1. ส่งรูปสลิปไปตรวจสอบกับ SlipOK API
    const slipRes = await fetch(`https://api.slipok.com/api/line/apikey/${branchId}`, {
      method: "POST",
      headers: {
        "x-authorization": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ url: slipUrl, log: true }),
    });

    const slipData = await slipRes.json();
    if (!slipRes.ok || !slipData?.success) {
      return new Response(
        JSON.stringify({ ok: false, message: slipData?.message || "สลิปไม่ถูกต้องหรือถูกใช้ไปแล้ว" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const amount = Number(slipData.data?.amount || 0);
    const transRef = String(slipData.data?.transRef || "");
    const coinsToAdd = Math.round(amount * (1 + Number(bonusPercent) / 100));

    // 2. บันทึกและเติมเหรียญเข้าบัญชีผู้อ่านใน Supabase
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { error: txErr } = await supabase.from("transactions").insert({
      user_id: userId,
      type: "topup",
      amount_baht: amount,
      coins_delta: coinsToAdd,
      payment_method: "auto_slipok",
      slip_url: slipUrl,
      slip_ref: transRef,
      note: `เติมเงินอัตโนมัติ ${amount} บาท (+โบนัส ${bonusPercent}%)`,
      status: "approved",
    });

    if (txErr) {
      throw new Error("สลิปนี้ถูกใช้งานไปแล้ว หรือบันทึกไม่สำเร็จ");
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("coin_balance")
      .eq("id", userId)
      .single();

    await supabase
      .from("profiles")
      .update({ coin_balance: (profile?.coin_balance || 0) + coinsToAdd })
      .eq("id", userId);

    return new Response(
      JSON.stringify({ ok: true, amount, coinsAdded: coinsToAdd }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ ok: false, message: String(err?.message || err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
