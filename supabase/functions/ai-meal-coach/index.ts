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
  totalCarbs: number;
  totalFat: number;
  totalFiber: number;
  totalSugar: number;
  totalSatFat: number;
  totalSodium: number;
  entries: Array<{
    section: string;
    cal: number;
    pro: number;
    carbs: number;
    fat: number;
    fiber: number;
    sugar: number;
    satFat: number;
    sodium: number;
    foods: string[];
  }>;
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
  let totalCarbs = 0;
  let totalFat = 0;
  let totalFiber = 0;
  let totalSugar = 0;
  let totalSatFat = 0;
  let totalSodium = 0;
  const entries: Array<any> = [];
  const lines: string[] = [];

  for (const key of sectionOrder) {
    const items: any[] = sectionsJson?.[key] ?? [];
    if (!items.length) continue;

    let sectionCal = 0;
    let sectionPro = 0;
    let sectionCarbs = 0;
    let sectionFat = 0;
    let sectionFiber = 0;
    let sectionSugar = 0;
    let sectionSatFat = 0;
    let sectionSodium = 0;
    const foods: string[] = [];

    for (const item of items) {
      const cal = parseFloat(item?.result?.calories?.mid ?? item?.result?.calories?.max ?? 0);
      const pro = parseFloat(item?.result?.protein?.mid  ?? item?.result?.protein?.max  ?? 0);
      const carbs = parseFloat(item?.result?.carbohydrates?.mid ?? item?.result?.carbohydrates?.max ?? 0);
      const fat = parseFloat(item?.result?.fat?.mid ?? item?.result?.fat?.max ?? 0);
      const fiber = parseFloat(item?.result?.fiber?.mid ?? item?.result?.fiber?.max ?? 0);
      const sugar = parseFloat(item?.result?.sugar?.mid ?? item?.result?.sugar?.max ?? 0);
      const satFat = parseFloat(item?.result?.saturatedFat?.mid ?? item?.result?.saturatedFat?.max ?? 0);
      const sodium = parseFloat(item?.result?.sodium?.mid ?? item?.result?.sodium?.max ?? 0);
      const score = item?.result?.mealQualityScore;
      const positive = item?.result?.mealQualityPositive;
      const improvement = item?.result?.mealQualityImprovement;

      const name = (item?.result?.canonicalMeal ?? item?.rawInput ?? 'unknown meal').trim();
      sectionCal += cal;
      sectionPro += pro;
      sectionCarbs += carbs;
      sectionFat += fat;
      sectionFiber += fiber;
      sectionSugar += sugar;
      sectionSatFat += satFat;
      sectionSodium += sodium;

      let foodDesc = `${name} (~${Math.round(cal)} kcal, ${Math.round(pro)}g protein`;
      if (carbs > 0 || fat > 0 || fiber > 0) {
        foodDesc += `, ${Math.round(carbs)}g carbs, ${Math.round(fat)}g fat, ${Math.round(fiber)}g fiber`;
      }
      foodDesc += `)`;
      if (score !== undefined && score !== null) {
        foodDesc += ` [Quality Score: ${score}/100`;
        if (positive) foodDesc += `, Positive: ${positive}`;
        if (improvement) foodDesc += `, Improvement: ${improvement}`;
        foodDesc += `]`;
      }
      foods.push(foodDesc);
    }

    totalCal += sectionCal;
    totalPro += sectionPro;
    totalCarbs += sectionCarbs;
    totalFat += sectionFat;
    totalFiber += sectionFiber;
    totalSugar += sectionSugar;
    totalSatFat += sectionSatFat;
    totalSodium += sectionSodium;

    entries.push({
      section: sectionLabels[key] ?? key,
      cal: sectionCal,
      pro: sectionPro,
      carbs: sectionCarbs,
      fat: sectionFat,
      fiber: sectionFiber,
      sugar: sectionSugar,
      satFat: sectionSatFat,
      sodium: sectionSodium,
      foods
    });

    lines.push(`  ${sectionLabels[key]} — ${Math.round(sectionCal)} kcal, ${Math.round(sectionPro)}g protein, ${Math.round(sectionFiber)}g fiber`);
    for (const f of foods) lines.push(`    • ${f}`);
  }

  return {
    text: lines.join('\n') || '  (no meals logged yet today)',
    totalCal: Math.round(totalCal),
    totalPro: Math.round(totalPro),
    totalCarbs: Math.round(totalCarbs),
    totalFat: Math.round(totalFat),
    totalFiber: Math.round(totalFiber),
    totalSugar: Math.round(totalSugar),
    totalSatFat: Math.round(totalSatFat),
    totalSodium: Math.round(totalSodium),
    entries,
  };
}

function computeDailyNutritionScore(sectionsJson: any): number | null {
  const allItems: any[] = [];
  const sectionKeys = ['breakfast', 'lunch', 'eveningSnack', 'dinner', 'lateNight'];
  for (const key of sectionKeys) {
    const items = sectionsJson?.[key] ?? [];
    for (const item of items) {
      allItems.push(item);
    }
  }

  const entriesWithScore = allItems.filter(item => item?.result?.mealQualityScore !== undefined && item?.result?.mealQualityScore !== null);
  if (entriesWithScore.length === 0) return null;

  let weightedSum = 0;
  let totalCaloriesWithScore = 0;

  for (const item of entriesWithScore) {
    const score = item.result.mealQualityScore!;
    const cals = (parseFloat(item.result.calories?.min ?? 0) + parseFloat(item.result.calories?.max ?? 0)) / 2;
    weightedSum += score * cals;
    totalCaloriesWithScore += cals;
  }

  if (totalCaloriesWithScore > 0) {
    return Math.max(0, Math.min(100, Math.round(weightedSum / totalCaloriesWithScore)));
  }

  const sumScores = entriesWithScore.reduce((acc, item) => acc + item.result.mealQualityScore!, 0);
  return Math.max(0, Math.min(100, Math.round(sumScores / entriesWithScore.length)));
}

interface MemoryEntry {
  canonical_meal: string;
  calories?: number;
  protein?: number;
  calories_per_unit?: number;
  protein_per_unit?: number;
  reference_quantity?: number;
  reference_unit?: string;
  times_used: number;
  updated_at: string;
}

function getRelevantFoodMemory(memoryRows: MemoryEntry[], queryText: string): string {
  const fillerWords = new Set(['and', 'with', 'some', 'a', 'an', 'of', 'the', 'in', 'at', 'on', 'for', 'to', 'my', 'had', 'ate', 'eaten', 'having']);
  
  function tokenize(text: string): Set<string> {
    return new Set(
      text
        .toLowerCase()
        .replace(/[',.\-!?+&]/g, '')
        .split(/\s+/)
        .filter(t => t.length > 0 && !fillerWords.has(t))
    );
  }

  const queryTokens = tokenize(queryText);
  
  // If query is empty, or has no meaningful tokens, we return the top frequently/recently logged foods
  if (queryTokens.size === 0) {
    return buildDefaultMemoryList(memoryRows);
  }

  const scored: Array<{ entry: MemoryEntry; score: number }> = [];
  const now = new Date();

  for (const r of memoryRows) {
    const name = r.canonical_meal;
    const tokens = tokenize(name);
    if (tokens.size === 0) continue;

    // Jaccard similarity
    let intersectionSize = 0;
    for (const t of queryTokens) {
      if (tokens.has(t)) intersectionSize++;
    }
    
    if (intersectionSize === 0) continue; // No match

    const unionSize = queryTokens.size + tokens.size - intersectionSize;
    const similarity = intersectionSize / unionSize;

    // Exact containment bonus
    let exactBonus = 0;
    const qLower = queryText.toLowerCase();
    const nameLower = name.toLowerCase();
    if (qLower.includes(nameLower) || nameLower.includes(qLower)) {
      exactBonus = 0.3;
    }

    // Frequency bonus
    const timesUsed = r.times_used ?? 1;
    const freqBonus = Math.min(0.2, timesUsed * 0.01);

    // Recency bonus
    let recencyBonus = 0;
    if (r.updated_at) {
      const updatedDate = new Date(r.updated_at);
      const diffDays = Math.abs(now.getTime() - updatedDate.getTime()) / (1000 * 60 * 60 * 24);
      if (diffDays <= 1) recencyBonus = 0.2;
      else if (diffDays <= 7) recencyBonus = 0.1;
    }

    const score = similarity + exactBonus + freqBonus + recencyBonus;
    scored.push({ entry: r, score });
  }

  // If we found relevant matches, sort and return them
  if (scored.length > 0) {
    scored.sort((a, b) => b.score - a.score);
    const unique = new Set<string>();
    const selected: MemoryEntry[] = [];
    for (const s of scored) {
      const nameKey = s.entry.canonical_meal.toLowerCase();
      if (!unique.has(nameKey)) {
        unique.add(nameKey);
        selected.push(s.entry);
        if (selected.length >= 10) break; // return up to 10 relevant matches
      }
    }
    return formatMemoryEntries(selected);
  }

  // Fallback: no similarity overlap, return top frequent/recent
  return buildDefaultMemoryList(memoryRows);
}

function buildDefaultMemoryList(memoryRows: MemoryEntry[]): string {
  // Frequently logged (top 8 by times_used)
  const frequent = [...memoryRows]
    .sort((a, b) => (b.times_used ?? 0) - (a.times_used ?? 0));
  
  // Recently logged (top 8 by updated_at)
  const recent = [...memoryRows]
    .filter(r => r.updated_at)
    .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());

  const selected = new Set<MemoryEntry>();
  const uniqueNames = new Set<string>();

  // Add top 5 frequent
  let added = 0;
  for (const r of frequent) {
    const key = r.canonical_meal.toLowerCase();
    if (!uniqueNames.has(key)) {
      uniqueNames.add(key);
      selected.add(r);
      added++;
      if (added >= 5) break;
    }
  }

  // Add top 5 recent
  added = 0;
  for (const r of recent) {
    const key = r.canonical_meal.toLowerCase();
    if (!uniqueNames.has(key)) {
      uniqueNames.add(key);
      selected.add(r);
      added++;
      if (added >= 5) break;
    }
  }

  return formatMemoryEntries(Array.from(selected));
}

function formatMemoryEntries(entries: MemoryEntry[]): string {
  if (entries.length === 0) return '(no food memory entries found)';
  return entries.map(r => {
    const qty = parseFloat((r.reference_quantity ?? 1).toString());
    const calPer = parseFloat((r.calories_per_unit ?? r.calories ?? 0).toString());
    const proPer = parseFloat((r.protein_per_unit ?? r.protein ?? 0).toString());
    const cal = Math.round(calPer * qty);
    const pro = Math.round(proPer * qty);
    const label = r.reference_unit ? `${qty} ${r.reference_unit}` : '1 serving';
    return `• ${r.canonical_meal}: ${cal} kcal, ${pro}g protein — for ${label}`;
  }).join('\n');
}

function getDayCal(row: any): number {
  const sections = row.sections_json ?? {};
  let cal = 0;
  const sectionKeys = ['breakfast', 'lunch', 'eveningSnack', 'dinner', 'lateNight'];
  for (const key of sectionKeys) {
    const items = sections[key] ?? [];
    for (const item of items) {
      cal += parseFloat(item?.result?.calories?.mid ?? item?.result?.calories?.max ?? 0);
    }
  }
  return cal;
}

function getDayPro(row: any): number {
  const sections = row.sections_json ?? {};
  let pro = 0;
  const sectionKeys = ['breakfast', 'lunch', 'eveningSnack', 'dinner', 'lateNight'];
  for (const key of sectionKeys) {
    const items = sections[key] ?? [];
    for (const item of items) {
      pro += parseFloat(item?.result?.protein?.mid ?? item?.result?.protein?.max ?? 0);
    }
  }
  return pro;
}

function getMostFrequentFoods30Days(trendRows: any[]): string[] {
  const counts: Record<string, number> = {};
  const sectionKeys = ['breakfast', 'lunch', 'eveningSnack', 'dinner', 'lateNight'];

  for (const row of trendRows) {
    const sections = row.sections_json;
    if (!sections) continue;
    for (const key of sectionKeys) {
      const items = sections[key];
      if (Array.isArray(items)) {
        for (const item of items) {
          const name = item?.result?.canonicalMeal ?? item?.rawInput;
          if (name && typeof name === 'string') {
            const cleanName = name.trim();
            if (cleanName) {
              counts[cleanName] = (counts[cleanName] ?? 0) + 1;
            }
          }
        }
      }
    }
  }

  return Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(entry => entry[0]);
}

function deriveUserEnvironment(trendRows: any[], userMessage: string): 'Mess' | 'Home' | 'Restaurant-heavy' | 'Mixed' {
  let messCount = 0;
  let restaurantCount = 0;
  let homeCount = 0;

  const msg = userMessage.toLowerCase();
  
  if (msg.includes('mess') || msg.includes('canteen') || msg.includes('hostel') || msg.includes('hall') || msg.includes('ladle')) {
    messCount += 5;
  }
  if (msg.includes('restaurant') || msg.includes('order') || msg.includes('swiggy') || msg.includes('zomato') || msg.includes('cafe') || msg.includes('dine out')) {
    restaurantCount += 5;
  }
  if (msg.includes('home') || msg.includes('cook') || msg.includes('mom') || msg.includes('wife') || msg.includes('made at')) {
    homeCount += 5;
  }

  const sectionKeys = ['breakfast', 'lunch', 'eveningSnack', 'dinner', 'lateNight'];
  for (const row of trendRows) {
    const sections = row.sections_json;
    if (!sections) continue;
    for (const key of sectionKeys) {
      const items = sections[key];
      if (Array.isArray(items)) {
        for (const item of items) {
          const name = (item?.result?.canonicalMeal ?? item?.rawInput ?? '').toLowerCase();
          const mode = item?.result?.estimationMode ?? '';
          
          if (name.includes('mess') || name.includes('canteen') || name.includes('hostel') || name.includes('ladle')) {
            messCount++;
          }
          if (name.includes('restaurant') || name.includes('order') || name.includes('swiggy') || name.includes('zomato') || mode === 'outside_restaurant' || mode === 'outside') {
            restaurantCount++;
          }
          if (name.includes('home') || name.includes('cook') || name.includes('mom') || name.includes('made at')) {
            homeCount++;
          }
        }
      }
    }
  }

  console.log(`[deriveUserEnvironment] Scores - Mess: ${messCount}, Restaurant: ${restaurantCount}, Home: ${homeCount}`);

  if (messCount > restaurantCount && messCount > homeCount && messCount >= 2) {
    return 'Mess';
  }
  if (restaurantCount > messCount && restaurantCount > homeCount && restaurantCount >= 2) {
    return 'Restaurant-heavy';
  }
  if (homeCount > messCount && homeCount > restaurantCount && homeCount >= 2) {
    return 'Home';
  }
  
  return 'Mixed';
}

function buildUserPersonalizationBlock(profile: any, portionAnchorHint: string | null, environment: 'Mess' | 'Home' | 'Restaurant-heavy' | 'Mixed', memoryRows: MemoryEntry[]): string {
  const lines: string[] = [];

  // Goal-specific behaviour
  const goal = (profile.goal ?? 'Fat Loss').toLowerCase();
  if (goal.includes('fat loss') || goal.includes('cut')) {
    lines.push('User is in a fat loss phase — prioritize protein and fiber density over calorie density to maximize satiety.');
  } else if (goal.includes('bulk') || goal.includes('gain')) {
    lines.push('User is in a bulk phase — prioritize meeting a calorie surplus and suggest calorie-dense foods if lagging.');
  } else if (goal.includes('recomp')) {
    lines.push('User is in a recomposition phase — maintain clean nutrition and target calories precisely.');
  }

  // Portion anchor
  if (portionAnchorHint) {
    lines.push(`Eating/Portion style: ${portionAnchorHint}`);
  }

  // Environment-specific assumptions
  lines.push(`Derived eating environment: ${environment}`);
  if (environment === 'Mess') {
    lines.push('User eats in a college mess/hostel environment — assume moderate to high oil/ghee in all cooked foods. Default portion assumptions (like mess chapati or mess ladles of rice/dal) are highly relevant.');
  } else if (environment === 'Home') {
    lines.push('User eats mostly home-cooked meals — assume controlled oil/ghee usage, lean preparation styles, and standard home portions.');
  } else if (environment === 'Restaurant-heavy') {
    lines.push('User eats restaurant or ordered food frequently — assume hidden fats (cream, butter, extra oil), wider calorie ranges, and larger/denser portion sizes.');
  } else {
    lines.push('User eats in a mixed environment — do not default globally to mess or home assumptions. Tailor estimates dynamically based on the specific food mentioned (e.g. assume home-style defaults for simple home foods, and restaurant defaults for outside food).');
  }

  // Count whey usage dynamic rule
  const hasWheyInMemory = memoryRows.some((r: any) => {
    const name = (r.canonical_meal ?? '').toLowerCase();
    return name.includes('whey') || name.includes('protein powder') || name.includes('protein shake');
  });
  if (hasWheyInMemory) {
    lines.push('User already consumes whey protein regularly. Avoid recommending they add whey protein unless they specifically ask or are far behind on protein targets.');
  }

  return lines.length > 0
    ? `• ${lines.join('\n• ')}`
    : '(no user-specific habits set)';
}

function buildTrendSummary(trendRows: any[], targetCal: number, targetPro: number): string {
  if (!trendRows || trendRows.length === 0) return '(no historical data yet)';

  const last7 = trendRows.slice(0, 7);
  const last30 = trendRows;

  const avg = (arr: number[]) => arr.length > 0 ? arr.reduce((sum, v) => sum + v, 0) / arr.length : 0;

  const avgCal7 = avg(last7.map(r => getDayCal(r)));
  const avgPro7 = avg(last7.map(r => getDayPro(r)));
  const avgCal30 = avg(last30.map(r => getDayCal(r)));
  const avgPro30 = avg(last30.map(r => getDayPro(r)));

  const adherence7 = last7.filter(r => Math.abs(getDayCal(r) - targetCal) <= targetCal * 0.10).length;
  const adherence30 = last30.filter(r => Math.abs(getDayCal(r) - targetCal) <= targetCal * 0.10).length;

  const gymDays7 = last7.filter(r => r.gym_day_json?.didGym === true).length;
  const gymDays30 = last30.filter(r => r.gym_day_json?.didGym === true).length;

  const mostFrequentFoods = getMostFrequentFoods30Days(trendRows);
  const freqFoodsStr = mostFrequentFoods.length > 0
    ? mostFrequentFoods.map(f => `• ${f}`).join('\n')
    : '(no frequent foods logged yet)';

  return `
LAST 7 DAYS:
• Avg calories: ${Math.round(avgCal7)} kcal (target: ${targetCal})
• Avg protein: ${Math.round(avgPro7)} g (target: ${targetPro})
• Days within 10% of calorie target: ${adherence7}/7
• Training days: ${gymDays7}/7

LAST 30 DAYS:
• Avg calories: ${Math.round(avgCal30)} kcal
• Avg protein: ${Math.round(avgPro30)} g
• Adherence rate: ${Math.round(adherence30 / last30.length * 100)}% of days within target
• Training days: ${gymDays30}/${last30.length}

MOST FREQUENT FOODS (30 DAYS):
${freqFoodsStr}`;
}

// ── Build complete system prompt ───────────────────────────────────────────────
function buildSystemPrompt(params: {
  profile:            any;
  targetCal:          number;
  targetPro:          number;
  targetFiber:        number;
  targetCarbs:        number;
  targetFat:          number;
  dayLabel:           string;
  mealContext:        string;
  totalCal:           number;
  totalPro:           number;
  totalCarbs:         number;
  totalFat:           number;
  totalFiber:         number;
  totalSugar:         number;
  totalSatFat:        number;
  totalSodium:        number;
  remainCal:          number;
  remainPro:          number;
  foodMemory:         string;
  isGymDay:           boolean;
  isManualOverride:   boolean;
  dailyNutritionScore: number | null;
  caloriePct:         number;
  proteinPct:         number;
  fiberPct:           number;
  trendSummary:       string;
  personalizationBlock: string;
}): string {
  const { profile, targetCal, targetPro, targetFiber, targetCarbs, targetFat, dayLabel, mealContext,
          totalCal, totalPro, totalCarbs, totalFat, totalFiber, totalSugar, totalSatFat, totalSodium,
          remainCal, remainPro, foodMemory, isGymDay, isManualOverride,
          dailyNutritionScore, caloriePct, proteinPct, fiberPct, trendSummary, personalizationBlock } = params;

  // When user has manually set a calorie target for the day, tell the AI explicitly
  // so it doesn't express surprise or confusion about an unusual number.
  const overrideNote = isManualOverride
    ? ' [user-set manual override — respect this exact number]'
    : '';

  return `You are Kyno — a personal nutrition coach embedded inside the Kynetix fitness app.
You already have full access to this user's data. Use it to give SPECIFIC, PRACTICAL advice.

=====================================================
LAYER 1: GLOBAL RULES & BASELINES (COMMON TO ALL USERS)
=====================================================
Nutrition science guidelines:
- Realism over fake precision.
- Primary recommendations should represent the most likely true intake.
- When recommending, prioritize nutrient-dense, high-protein, and high-fiber foods.
- Respect remaining targets — never suggest more than what fits in the remaining budget.
- Focus on behavior modification, consistency, and safe progression.

REFERENCE BASELINES (standard Indian portion defaults):
• 1 plain tawa roti / chapati: ~80-100 kcal, 3g protein
• 1 medium bowl cooked plain white rice: ~200-210 kcal, 4g protein
• 1 katori plain dal (home style): ~100-120 kcal, 5-6g protein
• 1 katori rajma/chole (home style): ~130-150 kcal, 6-7g protein
• 1 serving dry mixed vegetable sabzi: ~90-110 kcal, 2g protein
• 100g plain raw paneer: 295 kcal, 18g protein, 22g fat
• 100g raw tofu: 135-150 kcal, 14-16g protein
• 3 egg whites: 51 kcal, 11g protein
• 1 whole egg: 75 kcal, 6.5g protein
• 100g plain curd: 60 kcal, 3.5g protein
• 1 tbsp peanut butter: 95 kcal, 3.5g protein
• 1 medium banana: 90 kcal, 1.2g protein

RESPONSE RULES:
1. Always give EXACT quantities (e.g. "2 roti", "150g paneer", "3 egg whites")
2. Always include calories AND protein per recommendation
3. Refer to today's logged meals and historical patterns in your reasoning
4. Keep responses concise, direct, and actionable (coach style, not textbook)
5. When recommending meals, present: food name + quantity + calories + protein + remaining budget after
6. Avoid referencing or suggesting whey protein if the personalization context notes they already take it regularly.

=====================================================
LAYER 2: USER PERSONALIZATION CONTEXT (DYNAMICALLY BUILT)
=====================================================
USER PROFILE:
• Name: ${profile.name ?? 'User'}
• Goal: ${profile.goal ?? 'Fat Loss'}
• Weight: ${profile.weight_kg} kg
• Height: ${profile.height_cm} cm
• Age: ${profile.age}
• Gender: ${profile.gender}
• Gym frequency: ${profile.workout_days_min}–${profile.workout_days_max} days/week

EATING HABITS & ENVIRONMENT CONTEXT:
${personalizationBlock}

HISTORICAL TRENDS:
${trendSummary}

=====================================================
LAYER 3: MEAL & CONTEXT DEFINITIONS (CURRENT SESSION)
=====================================================
TODAY'S TARGETS & ACHIEVEMENTS — ${dayLabel}${isManualOverride ? ' (Manual Override)' : ''}
• Calorie target:            ${targetCal} kcal${overrideNote} (Achievement: ${caloriePct}%)
• Protein target:            ${targetPro} g (Achievement: ${proteinPct}%)
• Fiber target:              ${targetFiber} g (Achievement: ${fiberPct}%)
• Estimated Carbs target:    ${Math.round(targetCarbs)} g
• Estimated Fat target:      ${Math.round(targetFat)} g
• Day type:                  ${isGymDay ? '🏋️ Training Day (higher calories)' : '😴 Rest Day (lower calories)'}${isManualOverride ? '\n⚠️ Note: calorie target was manually overridden by user.' : ''}

TODAY'S NUTRITION TOTALS & QUALITY SCORE:
• Daily Nutrition Quality Score: ${dailyNutritionScore !== null ? `${dailyNutritionScore} / 100` : 'No score computed yet (need meal entries)'}
• Calories consumed:  ${totalCal} kcal (Target: ${targetCal} kcal, Remaining: ${remainCal} kcal)
• Protein consumed:   ${totalPro} g (Target: ${targetPro} g, Remaining: ${remainPro} g)
• Fiber consumed:     ${totalFiber} g (Target: ${targetFiber} g, Remaining: ${Math.max(0, targetFiber - totalFiber).toFixed(1)} g)
• Carbs consumed:     ${totalCarbs} g (Target: ${Math.round(targetCarbs)} g)
• Fat consumed:       ${totalFat} g (Target: ${Math.round(targetFat)} g)
• Sugar consumed:     ${totalSugar} g
• Saturated Fat:      ${totalSatFat} g
• Sodium consumed:    ${totalSodium} mg

TODAY'S LOGGED MEALS:
${mealContext}

USER'S CONFIRMED FOOD MACROS (HIGHEST PRIORITY):
WARNING: The following values represent ground truth confirmed by the user. If they ask about or log any food matching these entries, you MUST use these exact calorie and protein numbers.
${foodMemory}
`;;
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
    const imagesBase64: string[] = Array.isArray(body.images_base64)
      ? body.images_base64
      : (imageBase64 ? [imageBase64] : []);
    const streamMode: boolean = body.stream === true;
    // date_key must be YYYY-MM-DD (matches cloud_sync_service format in Flutter)
    const dateKey: string = body.date_key ?? new Date().toISOString().slice(0, 10);

    console.log(`[ai-meal-coach] (4/7) Request received: userMessage="${userMessage}", imagesCount=${imagesBase64.length}, streamMode=${streamMode}`);
    if (imagesBase64.length > 0) {
      console.log(`[ai-meal-coach] images base64 lengths: ${imagesBase64.map(s => s.length)}`);
    }

    if (!userMessage.trim() && imagesBase64.length === 0) {
      return new Response(JSON.stringify({ error: 'message or images_base64 required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    console.log(`[ai-meal-coach] user=${user.id} date=${dateKey} hasImages=${imagesBase64.length}`);

    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const thirtyDaysAgoStr = thirtyDaysAgo.toISOString().slice(0, 10);

    // ── Fetch all data in parallel ────────────────────────────────────────────
    const [profileRes, dayLogRes, memoryRes, trendRes] = await Promise.all([
      supabaseAdmin.from('profiles').select('*').eq('id', user.id).maybeSingle(),
      supabaseAdmin.from('day_logs').select('sections_json, gym_day_json').eq('user_id', user.id).eq('date_key', dateKey).maybeSingle(),
      supabaseAdmin.from('user_nutrition_memory').select('canonical_meal, calories, protein, calories_per_unit, protein_per_unit, reference_quantity, reference_unit, times_used, updated_at').eq('user_id', user.id).order('times_used', { ascending: false }).limit(100),
      supabaseAdmin.from('day_logs').select('date_key, sections_json, gym_day_json').eq('user_id', user.id).gte('date_key', thirtyDaysAgoStr).order('date_key', { ascending: false }).limit(30),
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

    // ── Manual calorie override ───────────────────────────────────────────────
    // Priority (same pattern as isGymDay):
    //   1. body.target_calories_override — client real-time (highest truth)
    //   2. gymDayJson?.targetCaloriesOverride — persisted DB value
    //   3. null — use formula from computeTargets()
    const bodyOverride = typeof body.target_calories_override === 'number' && body.target_calories_override > 0
        ? body.target_calories_override as number
        : null;
    const dbOverride = typeof gymDayJson?.targetCaloriesOverride === 'number' && gymDayJson.targetCaloriesOverride > 0
        ? gymDayJson.targetCaloriesOverride as number
        : null;
    const caloriesOverride: number | null = bodyOverride ?? dbOverride;

    // ── Compute targets ───────────────────────────────────────────────────────
    const { calories: computedCal, protein: targetPro, label: dayLabel } =
      computeTargets(profile, isGymDay);

    // Apply override: user-set calorie target takes precedence over formula.
    // Protein is never overridden — it stays formula-computed for the day type.
    const isManualOverride = caloriesOverride !== null;
    const targetCal = isManualOverride ? Math.round(caloriesOverride!) : computedCal;
    console.log(`[ai-meal-coach] calorieTarget=${targetCal}${isManualOverride ? ' (MANUAL OVERRIDE, original='+computedCal+')' : ' (formula)'}  protein=${targetPro}`);

    // ── Build meal context ────────────────────────────────────────────────────
    const {
      text: mealContext,
      totalCal,
      totalPro,
      totalCarbs,
      totalFat,
      totalFiber,
      totalSugar,
      totalSatFat,
      totalSodium
    } = buildMealContext(dayLogRes.data?.sections_json ?? {});

    const remainCal = Math.max(0, targetCal - totalCal);
    const remainPro = Math.max(0, targetPro - totalPro);

    // ── Build food memory ─────────────────────────────────────────────────────
    const foodMemory = getRelevantFoodMemory(memoryRes.data ?? [], userMessage);

    // ── Calculate daily nutrition score ───────────────────────────────────────
    const dailyNutritionScore = computeDailyNutritionScore(dayLogRes.data?.sections_json ?? {});

    // ── Calculate target achievement percentages ──────────────────────────────
    const caloriePct = targetCal > 0 ? Math.round((totalCal / targetCal) * 100) : 0;
    const proteinPct = targetPro > 0 ? Math.round((totalPro / targetPro) * 100) : 0;
    const targetFiber = 30.0;
    const fiberPct = targetFiber > 0 ? Math.round((totalFiber / targetFiber) * 100) : 0;

    // ── Calculate remaining carbs/fat targets ─────────────────────────────────
    const remainingCal = Math.max(0, targetCal - targetPro * 4);
    const targetFat = remainingCal * 0.35 / 9;
    const targetCarbs = remainingCal * 0.65 / 4;

    console.log(`[ai-meal-coach] targets=${targetCal}kcal/${targetPro}g consumed=${totalCal}/${totalPro} remain=${remainCal}/${remainPro}`);

    // ── Build trend summary & personalization block ──────────────────────────
    const trendRows = trendRes.data ?? [];
    const derivedEnv = deriveUserEnvironment(trendRows, userMessage);
    const personalizationBlock = buildUserPersonalizationBlock(profile, body.portion_anchor_hint ?? null, derivedEnv, memoryRes.data ?? []);
    const trendSummary = buildTrendSummary(trendRows, targetCal, targetPro);

    // ── Build messages for ai-chat-router ────────────────────────────────────
    const systemPrompt = buildSystemPrompt({
      profile,
      targetCal,
      targetPro,
      targetFiber,
      targetCarbs,
      targetFat,
      dayLabel: workoutType,
      mealContext,
      totalCal,
      totalPro,
      totalCarbs,
      totalFat,
      totalFiber,
      totalSugar,
      totalSatFat,
      totalSodium,
      remainCal,
      remainPro,
      foodMemory,
      isGymDay,
      isManualOverride,
      dailyNutritionScore,
      caloriePct,
      proteinPct,
      fiberPct,
      trendSummary,
      personalizationBlock,
    });

    // Construct user message content (text + optional images)
    let userContent: any;
    if (imagesBase64.length > 0) {
      userContent = [
        { type: 'text', text: userMessage || 'Analyze this food/menu image and advise me based on my remaining targets.' }
      ];
      for (const img of imagesBase64) {
        userContent.push({
          type: 'image_url',
          image_url: { url: `data:image/jpeg;base64,${img}` }
        });
      }
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

      const provider   = routerRes.headers.get('x-provider-used') ?? 'unknown';
      const modelUsed  = routerRes.headers.get('x-model-used')    ?? 'unknown';
      console.log(`[ai-meal-coach] piping SSE stream, provider=${provider} model=${modelUsed}`);
      return new Response(routerRes.body, {
        headers: {
          ...corsHeaders,
          'Content-Type':    'text/event-stream',
          'Cache-Control':   'no-cache',
          'X-Provider-Used': provider,
          'X-Model-Used':    modelUsed,
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
    console.log(`[ai-meal-coach] ✅ success provider=${routerData.provider_used} model=${routerData.model_used} fallback=${routerData.fallback_used}`);
    return new Response(JSON.stringify({
      success:        true,
      message:        aiResponse,
      provider_used:  routerData.provider_used,
      model_used:     routerData.model_used ?? null,
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
        consumed_fiber: totalFiber,
        consumed_carbs: totalCarbs,
        consumed_fat: totalFat,
        daily_score:   dailyNutritionScore,
        calorie_pct:   caloriePct,
        protein_pct:   proteinPct,
        fiber_pct:     fiberPct,
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
