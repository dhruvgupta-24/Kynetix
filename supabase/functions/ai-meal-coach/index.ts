// ai-meal-coach — Context-injecting AI coach for nutrition guidance
//
// Responsibilities:
//   1. Auth the user
//   2. Fetch today's logged meals from day_logs (sections_json)
//   3. Fetch user profile + compute day targets (calories, protein, gym/rest)
//   4. Fetch top food memory from user_nutrition_memory
//   5. Build a full structured system prompt with all context
//   6. Call ai-chat-router internally (which handles OpenAI vs OpenRouter)
//   7. Return { message, provider_used, fallback_used, ... } to client

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SUPABASE_URL = () => Deno.env.get('SUPABASE_URL') ?? '';

// ── Nutrition target formula — mirrors NutritionTargetEngine in Flutter exactly ──
// BMR:  Mifflin-St Jeor
// TDEE: BMR × activity_multiplier (8-tier, resistance-training calibrated)
// Goal delta: percentage-based, bounded (matches Flutter _goalAdjustment)
// Protein: goal- and day-aware (training vs rest) — matches Flutter values
// Calorie cycle: scales with training frequency (matches Flutter _calorieCycle)

function computeTargets(profile: any, isGymDay: boolean): { calories: number; protein: number; label: string } {
  const w = parseFloat(profile.weight_kg ?? 70);
  const h = parseFloat(profile.height_cm ?? 175);
  const a = parseInt(profile.age ?? 22);
  const isMale = (profile.gender ?? 'Male') === 'Male';
  const goal = (profile.goal ?? 'Fat Loss').toLowerCase();

  // ── Mifflin-St Jeor BMR ──────────────────────────────────────────────────
  const bmr = isMale
    ? 10 * w + 6.25 * h - 5 * a + 5
    : 10 * w + 6.25 * h - 5 * a - 161;

  // ── 8-tier resistance-training activity multiplier (matches Flutter) ─────
  // Deliberately lower than classic Mifflin tables (which assume cardio).
  const gymDaysPerWeek = (parseInt(profile.workout_days_min ?? 4) + parseInt(profile.workout_days_max ?? 5)) / 2;
  let actMult: number;
  if      (gymDaysPerWeek <= 0.5) actMult = 1.20; // sedentary
  else if (gymDaysPerWeek <= 1.5) actMult = 1.25; // 1 day/wk
  else if (gymDaysPerWeek <= 2.5) actMult = 1.29; // 2 days/wk
  else if (gymDaysPerWeek <= 3.5) actMult = 1.33; // 3 days/wk
  else if (gymDaysPerWeek <= 4.5) actMult = 1.37; // 4 days/wk
  else if (gymDaysPerWeek <= 5.5) actMult = 1.41; // 5 days/wk
  else if (gymDaysPerWeek <= 6.5) actMult = 1.45; // 6 days/wk
  else                             actMult = 1.50; // 7 days/wk

  const tdee = bmr * actMult;

  // ── Goal calorie adjustment — percentage-based, bounded (matches Flutter) ─
  const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
  let goalDelta: number;
  if      (goal.includes('fat loss') || goal.includes('cut'))  goalDelta = -clamp(tdee * 0.22, 350, 550);
  else if (goal.includes('lean bulk'))                         goalDelta =  clamp(tdee * 0.08, 150, 250);
  else if (goal.includes('bulk'))                              goalDelta =  clamp(tdee * 0.15, 250, 450);
  else if (goal.includes('recomp'))                            goalDelta = -clamp(tdee * 0.09, 120, 250);
  else                                                          goalDelta = 0; // Maintenance

  const avgCalories = tdee + goalDelta;
  const calFloor    = bmr + 200; // absolute minimum

  // ── Calorie cycle (matches Flutter _calorieCycle) ───────────────────────
  let cycleDelta: number;
  if      (gymDaysPerWeek <= 1) cycleDelta = 70;
  else if (gymDaysPerWeek <= 3) cycleDelta = 90;
  else if (gymDaysPerWeek <= 5) cycleDelta = 105;
  else                          cycleDelta = 120;

  const calories = Math.round(Math.max(calFloor, isGymDay ? avgCalories + cycleDelta : avgCalories - cycleDelta));

  // ── Day-aware protein — matches Flutter protein switch tables ────────────
  let protein: number;
  if (goal.includes('fat loss') || goal.includes('cut')) {
    protein = isGymDay ? w * 1.95 : w * 1.75;
  } else if (goal.includes('lean bulk')) {
    protein = isGymDay ? w * 1.80 : w * 1.60;
  } else if (goal.includes('bulk')) {
    protein = isGymDay ? w * 2.00 : w * 1.70;
  } else if (goal.includes('recomp')) {
    protein = isGymDay ? w * 2.15 : w * 1.85;
  } else {
    // Maintenance — still training regularly, needs adequate protein
    protein = isGymDay ? w * 1.85 : w * 1.65;
  }

  return {
    calories: Math.round(calories),
    protein:  Math.round(protein),
    label:    isGymDay ? 'Training Day' : 'Rest Day',
  };
}

// ── Parse sections_json from day_logs into a readable meal summary ─────────────
function buildMealContext(sectionsJson: any): {
  text: string;
  totalCal: number;
  totalPro: number;
  entries: Array<{ section: string; cal: number; pro: number; foods: string[] }>;
} {
  const sectionOrder = ['breakfast', 'lunch', 'eveningSnack', 'dinner', 'lateNight'];
  const sectionLabels: Record<string, string> = {
    breakfast:    'Breakfast',
    lunch:        'Lunch',
    eveningSnack: 'Evening Snack',
    dinner:       'Dinner',
    lateNight:    'Late Night',
  };

  let totalCal = 0;
  let totalPro = 0;
  const entries: Array<{ section: string; cal: number; pro: number; foods: string[] }> = [];
  const lines: string[] = [];

  for (const key of sectionOrder) {
    const items: any[] = sectionsJson?.[key] ?? [];
    if (!items.length) continue;

    let sectionCal = 0;
    let sectionPro = 0;
    const foods: string[] = [];

    for (const item of items) {
      const cal = parseFloat(item?.result?.calories?.mid ?? item?.result?.calories?.max ?? 0);
      const pro = parseFloat(item?.result?.protein?.mid  ?? item?.result?.protein?.max  ?? 0);
      const name = (item?.result?.canonicalMeal ?? item?.rawInput ?? 'unknown meal').trim();
      sectionCal += cal;
      sectionPro += pro;
      foods.push(`${name} (~${Math.round(cal)} kcal, ${Math.round(pro)}g protein)`);
    }

    totalCal += sectionCal;
    totalPro += sectionPro;
    entries.push({ section: sectionLabels[key] ?? key, cal: sectionCal, pro: sectionPro, foods });
    lines.push(`  ${sectionLabels[key]} — ${Math.round(sectionCal)} kcal, ${Math.round(sectionPro)}g protein`);
    for (const f of foods) lines.push(`    • ${f}`);
  }

  return {
    text: lines.join('\n') || '  (no meals logged yet today)',
    totalCal: Math.round(totalCal),
    totalPro: Math.round(totalPro),
    entries,
  };
}

// ── Build food memory snippet ──────────────────────────────────────────────────
function buildFoodMemory(memoryRows: any[]): string {
  if (!memoryRows.length) return '(no food memory yet)';
  return memoryRows
    .slice(0, 30)
    .map((r: any) => {
      // calories/protein columns store PER-UNIT values (e.g. 0.65 kcal per ml).
      // Multiply by reference_quantity to get the correct serving-size total.
      const qty    = parseFloat(r.reference_quantity ?? 1);
      const calPer = parseFloat(r.calories_per_unit ?? r.calories ?? 0);
      const proPer = parseFloat(r.protein_per_unit  ?? r.protein  ?? 0);
      const cal    = Math.round(calPer * qty);
      const pro    = Math.round(proPer * qty);
      const label  = r.reference_unit ? `${qty} ${r.reference_unit}` : '1 serving';
      return `• ${r.canonical_meal}: ${cal} kcal, ${pro}g protein — for ${label}`;
    })
    .join('\n');
}

// ── Build complete system prompt ───────────────────────────────────────────────
function buildSystemPrompt(params: {
  profile:        any;
  targetCal:      number;
  targetPro:      number;
  dayLabel:       string;
  mealContext:    string;
  totalCal:       number;
  totalPro:       number;
  remainCal:      number;
  remainPro:      number;
  foodMemory:     string;
  isGymDay:       boolean;
}): string {
  const { profile, targetCal, targetPro, dayLabel, mealContext,
          totalCal, totalPro, remainCal, remainPro, foodMemory, isGymDay } = params;

  return `You are Kynetix AI Coach — a personal nutrition coach embedded inside the Kynetix fitness app.
You already have full access to this user's data for today. Use it to give SPECIFIC, PRACTICAL advice.

═══════════════════════════════════════════════════
USER PROFILE
═══════════════════════════════════════════════════
Name: ${profile.name ?? 'User'}
Goal: ${profile.goal ?? 'Fat Loss'}
Weight: ${profile.weight_kg} kg
Height: ${profile.height_cm} cm
Age: ${profile.age}
Gender: ${profile.gender}
Gym days/week: ${profile.workout_days_min}–${profile.workout_days_max}

═══════════════════════════════════════════════════
TODAY'S TARGETS — ${dayLabel}
═══════════════════════════════════════════════════
Calorie target:  ${targetCal} kcal
Protein target:  ${targetPro} g
Day type:        ${isGymDay ? '🏋️ Training Day (higher calories)' : '😴 Rest Day (lower calories)'}

═══════════════════════════════════════════════════
TODAY'S LOGGED MEALS
═══════════════════════════════════════════════════
${mealContext}

TOTALS SO FAR:   ${totalCal} kcal consumed,  ${totalPro}g protein consumed
REMAINING:       ${remainCal} kcal left,     ${remainPro}g protein left

═══════════════════════════════════════════════════
USER'S KNOWN EATING HABITS (follow these strictly)
═══════════════════════════════════════════════════
• Prefers ROTI over rice (default to roti unless asked)
• Typically eats 2 roti per meal (standard portion)
• Rice is measured in ladles — 1 plain ladle ≈ 130 kcal; 1 ladle jeera/tadka rice ≈ 150 kcal (oil + tempering)
• Sabzi/dal is eaten only to finish roti/rice — not a full bowl
• Paneer is fully eaten (no plate leftover)
• Whey protein is ALREADY consumed daily — NEVER suggest "take whey" or "1 scoop whey"
• Outside food / restaurant: widen calorie range, lean toward upper bound
• Mess context: ALWAYS assume oil/ghee is added to vegetables, gravy, and rice. Never assume dry preparation.
• NEVER describe a mess meal with paneer, ghee rice or oily sabzi as "light" or "clean".

═══════════════════════════════════════════════════
USER'S CONFIRMED FOOD MACROS — GROUND TRUTH
═══════════════════════════════════════════════════
WARNING: These calorie and protein values have been personally confirmed by the
user in their food tracker. They OVERRIDE your training data completely.
If a food the user mentions matches (or is close to) any food listed below,
you MUST use the EXACT numbers shown below — do NOT substitute your own estimate.
${foodMemory}

═══════════════════════════════════════════════════
RESPONSE RULES (non-negotiable)
═══════════════════════════════════════════════════
1. Always give EXACT quantities (e.g., "2 roti", "150g paneer", "3 egg whites", "1 ladle rice")
2. Always include calories AND protein per recommendation
3. Respect remaining targets — don't suggest more than what fits
4. Never suggest whey (it's already taken)
5. Reference today's logged meals in your reasoning
6. If user asks about a food NOT listed in their food memory, estimate using the baselines below
7. For image analysis: compare options against remaining targets and recommend the best fit
8. Keep response concise but complete — coach speak, not textbook
9. When recommending, show: food + quantity + calories + protein + remaining after
10. MOST IMPORTANT: If a food matches the user's confirmed food macros section above, use
    those EXACT numbers. Never use a different calorie/protein estimate for a confirmed food.

═══════════════════════════════════════════════════
REFERENCE BASELINES (use when food not in memory)
═══════════════════════════════════════════════════
IMPORTANT: This user eats at a college mess. Mess food is ALWAYS cooked in oil/ghee.
Never use dry/lean estimates. When in doubt, use the upper end of the range.

1 roti / chapati (mess/tawa): 110–120 kcal, 3g protein
1 ladle plain rice (mess): 130–145 kcal, 3g protein
1 ladle jeera/tadka/pulao rice: 150–180 kcal, 3g protein (oil + tempering overhead)
1 mess compartment paneer dish (gravy/makhani/dry): 140–170 kcal, 5–7g protein per compartment
  → 1 compartment ≈ ~80–100g paneer + gravy with oil; paneer alone is 295 kcal/100g, 15g protein
  → For 3 compartments: 420–510 kcal, 15–21g protein is realistic
1 katori plain dal (mess): 120–150 kcal, 6g protein
1 katori rajma/chhole (mess): 150–180 kcal, 7–9g protein
1 mess serving sabzi (potato, mixed veg, etc.): 120–180 kcal, 2–4g protein
100g paneer (restaurant/mess, with oil): 340–370 kcal, 16–18g protein
150g tofu (firm/extra-firm): 206 kcal, 22g protein
3 egg whites: 51 kcal, 11g protein
1 whole egg: 75 kcal, 6.5g protein
100g curd: 60 kcal, 3.5g protein
1 tbsp peanut butter: 95 kcal, 3.5g protein
1 medium banana: 90 kcal, 1.2g protein

MESS FOOD RULES:
• Paneer is fat-heavy (52g fat/100g). Even "dry paneer" at mess has oil coating.
• Jeera rice / pulao always has more calories than plain rice — add 20–40 kcal/ladle.
• When estimating a meal that wasn't logged, always give a realistic range and state your assumptions.
• If a meal sounds heavy (paneer + rice + sabzi), call it out honestly. Don't say it's light or fits comfortably unless it actually does after realistic estimation.`;
}

// ── Main handler ───────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const jwt = authHeader.replace('Bearer ', '').trim();

    // Inject JWT via global headers — Supabase Auth API verifies server-side (ES256 safe).
    // Passing jwt directly to getUser(jwt) triggers local HS256 check which fails on ES256 tokens.
    const supabaseAnon = createClient(
      SUPABASE_URL(),
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) {
      console.error(`[ai-meal-coach] Auth failed: ${userErr?.message ?? 'no user'}`);
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAdmin = createClient(
      SUPABASE_URL(),
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // ── Parse request ─────────────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const userMessage: string = body.message ?? '';
    const imageBase64: string | null = body.image_base64 ?? null;
    const streamMode: boolean = body.stream === true;
    // date_key must be YYYY-MM-DD (matches cloud_sync_service format in Flutter)
    const dateKey: string = body.date_key ?? new Date().toISOString().slice(0, 10);

    if (!userMessage.trim() && !imageBase64) {
      return new Response(JSON.stringify({ error: 'message or image_base64 required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    console.log(`[ai-meal-coach] user=${user.id} date=${dateKey} hasImage=${!!imageBase64}`);

    // ── Fetch all data in parallel ────────────────────────────────────────────
    const [profileRes, dayLogRes, memoryRes] = await Promise.all([
      supabaseAdmin.from('profiles').select('*').eq('id', user.id).maybeSingle(),
      supabaseAdmin.from('day_logs').select('sections_json, gym_day_json').eq('user_id', user.id).eq('date_key', dateKey).maybeSingle(),
      supabaseAdmin.from('user_nutrition_memory').select('canonical_meal, calories, protein, calories_per_unit, protein_per_unit, reference_quantity, reference_unit, times_used').eq('user_id', user.id).order('times_used', { ascending: false }).limit(30),
    ]);

    const profile = profileRes.data;
    if (!profile) {
      return new Response(JSON.stringify({ error: 'User profile not found' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Derive gym day status ─────────────────────────────────────────────────
    const gymDayJson = dayLogRes.data?.gym_day_json;
    // Prefer client's real-time state, fallback to DB
    const isGymDay: boolean = typeof body.is_gym_day === 'boolean'
        ? body.is_gym_day
        : gymDayJson?.didGym === true;
    
    // Also extract workout_type if provided (from flutter client)
    const workoutType: string = typeof body.workout_type === 'string' && body.workout_type.trim() !== ''
        ? body.workout_type
        : (isGymDay ? 'Training' : 'Rest');

    // ── Compute targets ───────────────────────────────────────────────────────
    const { calories: targetCal, protein: targetPro, label: dayLabel } =
      computeTargets(profile, isGymDay);

    // ── Build meal context ────────────────────────────────────────────────────
    const { text: mealContext, totalCal, totalPro } =
      buildMealContext(dayLogRes.data?.sections_json ?? {});

    const remainCal = Math.max(0, targetCal - totalCal);
    const remainPro = Math.max(0, targetPro - totalPro);

    // ── Build food memory ─────────────────────────────────────────────────────
    const foodMemory = buildFoodMemory(memoryRes.data ?? []);

    console.log(`[ai-meal-coach] targets=${targetCal}kcal/${targetPro}g consumed=${totalCal}/${totalPro} remain=${remainCal}/${remainPro}`);

    // ── Build messages for ai-chat-router ────────────────────────────────────
    const systemPrompt = buildSystemPrompt({
      profile, targetCal, targetPro, dayLabel: workoutType,
      mealContext, totalCal, totalPro,
      remainCal, remainPro, foodMemory, isGymDay,
    });

    // Construct user message content (text + optional image)
    let userContent: any;
    if (imageBase64) {
      // Vision-capable message with image
      userContent = [
        { type: 'text', text: userMessage || 'Analyze this food/menu image and advise me based on my remaining targets.' },
        { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
      ];
    } else {
      userContent = userMessage;
    }

    // Parse conversation history sent from the client (multi-turn context).
    // Each entry is { role: 'user'|'assistant', content: string }.
    // We cap at last 10 turns server-side as a safety measure.
    const rawHistory: Array<{ role: string; content: string }> = Array.isArray(body.history)
      ? body.history.slice(-10)
      : [];

    // Sanitise: only allow 'user' and 'assistant' roles, non-empty content
    const historyMessages = rawHistory
      .filter(h => (h.role === 'user' || h.role === 'assistant') && typeof h.content === 'string' && h.content.trim() !== '')
      .map(h => ({ role: h.role, content: h.content }));

    const messages = [
      { role: 'system', content: systemPrompt },
      ...historyMessages,
      { role: 'user',   content: userContent },
    ];

    // ── Call ai-chat-router ────────────────────────────────────────────────────────────
    const routerUrl = `${SUPABASE_URL()}/functions/v1/ai-chat-router`;
    console.log(`[ai-meal-coach] calling ai-chat-router stream=${streamMode}`);

    // ══════════════════════════════════════════════════
    // STREAMING PATH — pipe SSE from router back to Flutter
    // ══════════════════════════════════════════════════
    if (streamMode) {
      const routerRes = await fetch(routerUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': authHeader },
        body: JSON.stringify({ messages, stream: true }),
      });

      if (!routerRes.ok) {
        const errText = await routerRes.text();
        console.error(`[ai-meal-coach] router stream error ${routerRes.status}: ${errText.slice(0, 200)}`);
        return new Response(JSON.stringify({ error: 'AI router failed', detail: errText }), {
          status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }

      const provider = routerRes.headers.get('x-provider-used') ?? 'unknown';
      console.log(`[ai-meal-coach] piping SSE stream, provider=${provider}`);
      return new Response(routerRes.body, {
        headers: {
          ...corsHeaders,
          'Content-Type':    'text/event-stream',
          'Cache-Control':   'no-cache',
          'X-Provider-Used': provider,
        },
      });
    }

    // ══════════════════════════════════════════════════
    // NON-STREAMING PATH (unchanged)
    // ══════════════════════════════════════════════════
    const routerRes = await fetch(routerUrl, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': authHeader, // forward user's JWT
      },
      body: JSON.stringify({ messages }),
    });

    const routerRaw = await routerRes.text();
    console.log(`[ai-meal-coach] router status=${routerRes.status}`);

    if (!routerRes.ok) {
      console.error(`[ai-meal-coach] router error: ${routerRaw}`);
      return new Response(JSON.stringify({ error: 'AI router failed', detail: routerRaw }), {
        status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let routerData: any;
    try { routerData = JSON.parse(routerRaw); }
    catch (_) {
      return new Response(JSON.stringify({ error: 'Bad router response', detail: routerRaw }), {
        status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!routerData.success) {
      return new Response(JSON.stringify({
        error:         'AI provider failure',
        provider_used: routerData.provider_used ?? 'none',
        detail:        routerData,
      }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const aiResponse: string = routerData.response ?? '';

    // ── Return structured response ────────────────────────────────────────────
    console.log(`[ai-meal-coach] ✅ success provider=${routerData.provider_used} fallback=${routerData.fallback_used}`);
    return new Response(JSON.stringify({
      success:        true,
      message:        aiResponse,
      provider_used:  routerData.provider_used,
      fallback_used:  routerData.fallback_used,
      context: {
        date_key:     dateKey,
        is_gym_day:   isGymDay,
        target_cal:   targetCal,
        target_pro:   targetPro,
        consumed_cal: totalCal,
        consumed_pro: totalPro,
        remain_cal:   remainCal,
        remain_pro:   remainPro,
      },
    }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (err: any) {
    console.error(`[ai-meal-coach] Exception: ${err?.message ?? err}`);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
