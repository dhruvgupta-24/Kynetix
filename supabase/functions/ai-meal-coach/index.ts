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
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SUPABASE_URL = () => Deno.env.get('SUPABASE_URL') ?? '';

// ── Nutrition target formula (mirrors NutritionTargetEngine in Flutter) ────────
// BMR: Mifflin-St Jeor
// TDEE: BMR × activity_multiplier
// Fat loss:  −500 kcal/day; Lean bulk: +250; Maintenance: 0
// Calorie cycle: ±120 kcal (training vs rest)
// Protein: 1.85 g/kg avg for fat loss, 1.7 for lean bulk, 1.6 for maintenance

function computeTargets(profile: any, isGymDay: boolean): { calories: number; protein: number; label: string } {
  const w = parseFloat(profile.weight_kg ?? 70);
  const h = parseFloat(profile.height_cm ?? 175);
  const a = parseInt(profile.age ?? 22);
  const isMale = (profile.gender ?? 'Male') === 'Male';
  const goal = (profile.goal ?? 'Fat Loss').toLowerCase();

  // Mifflin-St Jeor BMR
  const bmr = isMale
    ? 10 * w + 6.25 * h - 5 * a + 5
    : 10 * w + 6.25 * h - 5 * a - 161;

  // Activity multiplier (conservative for lifting athletes)
  const gymDaysPerWeek = ((parseInt(profile.workout_days_min ?? 4) + parseInt(profile.workout_days_max ?? 5)) / 2);
  const activityMultiplier = gymDaysPerWeek >= 5 ? 1.45 : gymDaysPerWeek >= 3 ? 1.375 : 1.25;

  const tdee = bmr * activityMultiplier;

  let avgCalories: number;
  let proteinPerKg: number;
  if (goal.includes('fat loss') || goal.includes('cut')) {
    avgCalories = tdee - 500;
    proteinPerKg = 1.85;
  } else if (goal.includes('bulk') || goal.includes('gain')) {
    avgCalories = tdee + 250;
    proteinPerKg = 1.7;
  } else {
    avgCalories = tdee;
    proteinPerKg = 1.6;
  }

  const cycleDelta = 120;
  const calories = isGymDay ? avgCalories + cycleDelta : avgCalories - cycleDelta;
  const protein = w * proteinPerKg;

  return {
    calories: Math.round(calories),
    protein: Math.round(protein),
    label: isGymDay ? 'Training Day' : 'Rest Day',
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
    .slice(0, 25)
    .map((r: any) => {
      const unit = r.reference_unit ? `per ${r.reference_quantity ?? 1} ${r.reference_unit}` : '';
      return `• ${r.canonical_meal}: ~${Math.round(r.calories)} kcal, ${Math.round(r.protein)}g protein ${unit}`.trim();
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
• Rice is measured in ladles (1 ladle ≈ 130 kcal, 3g protein)
• Sabzi/dal is eaten only to finish roti/rice — not a full bowl
• Paneer is fully eaten (no plate leftover)
• Whey protein is ALREADY consumed daily — NEVER suggest "take whey" or "1 scoop whey"
• Outside food: widen calorie range, don't inflate primary estimate
• Mess context: estimate consumed, not served

═══════════════════════════════════════════════════
USER'S PERSONAL FOOD MEMORY
═══════════════════════════════════════════════════
These are foods this user has previously logged with confirmed nutrition values.
Always use these values when recommending or referencing these foods:
${foodMemory}

═══════════════════════════════════════════════════
RESPONSE RULES (non-negotiable)
═══════════════════════════════════════════════════
1. Always give EXACT quantities (e.g., "2 roti", "150g paneer", "3 egg whites", "1 ladle rice")
2. Always include calories AND protein per recommendation
3. Respect remaining targets — don't suggest more than what fits
4. Never suggest whey (it's already taken)
5. Reference today's logged meals in your reasoning
6. If user asks about food not in memory, estimate using known baselines
7. For image analysis: compare options against remaining targets and recommend the best fit
8. Keep response concise but complete — coach speak, not textbook
9. When recommending, show: food + quantity + calories + protein + remaining after

═══════════════════════════════════════════════════
REFERENCE BASELINES (use when food not in memory)
═══════════════════════════════════════════════════
1 roti (mess/home): 100 kcal, 3g protein
1 rice ladle (mess): 130 kcal, 3g protein
1 katori plain dal: 130 kcal, 6g protein
1 mess serving paneer dish: 250 kcal, 12g protein
100g paneer (restaurant): 295 kcal, 16g protein
150g tofu: 206 kcal, 22g protein
3 egg whites: 51 kcal, 11g protein
1 whole egg: 75 kcal, 6.5g protein
100g curd: 60 kcal, 3.5g protein
1 tbsp peanut butter: 95 kcal, 3.5g protein
1 medium banana: 90 kcal, 1.2g protein`;
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

    const supabaseAnon = createClient(SUPABASE_URL(), Deno.env.get('SUPABASE_ANON_KEY') ?? '');
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser(jwt);
    if (userErr || !user) {
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
    const dateKey: string = body.date_key ?? new Date().toISOString().slice(0, 10).replace(/-/g, '');

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
      supabaseAdmin.from('user_nutrition_memory').select('canonical_meal, calories, protein, reference_quantity, reference_unit, times_used').eq('user_id', user.id).order('times_used', { ascending: false }).limit(30),
    ]);

    const profile = profileRes.data;
    if (!profile) {
      return new Response(JSON.stringify({ error: 'User profile not found' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Derive gym day status ─────────────────────────────────────────────────
    const gymDayJson = dayLogRes.data?.gym_day_json;
    const isGymDay: boolean = gymDayJson?.didGym === true;

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
      profile, targetCal, targetPro, dayLabel,
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

    const messages = [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: userContent },
    ];

    // ── Call ai-chat-router ───────────────────────────────────────────────────
    const routerUrl = `${SUPABASE_URL()}/functions/v1/ai-chat-router`;
    console.log(`[ai-meal-coach] calling ai-chat-router at ${routerUrl}`);

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
