"""Guide copy. Tokens: [[k:food]] kcal, [[p:food]] protein g, [[s:food]] serving label, [[f:food|text]] food link,
[[x:slug|text]] exercise link, [[t:slug|text]] tool link, [[g:slug|text]] guide link.
Every food number comes from the app's food table at build time."""

GUIDES = [
dict(slug="how-to-count-calories-in-indian-food", date="2026-10-20",
 title="How to Count Calories in Indian Food (Dal, Roti, Sabzi) | Kynetix",
 h1="How to count calories in Indian food",
 desc="A practical way to count calories in home-cooked Indian food: roti, rice, dal, sabzi and the oil you can't see. Per katori numbers, portion tricks and common mistakes.",
 answer="Count Indian food by the pieces you can see: each roti, each ladle or bowl of rice, and each katori of dal or sabzi. A plain roti is about [[k:roti]] kcal, a bowl of rice (150 g) about [[k:rice]] kcal and a katori of dal tadka about [[k:dal tadka]] kcal. Then remember the oil and ghee, which is where most home-food estimates go wrong.",
 body=[
  ("Why Indian food feels hard to count", [
   "Most calorie apps were built around packaged food and Western plates: a chicken breast, a cup of rice, a slice of bread. A home thali is different. The dal is mixed, the sabzi has an unknown amount of oil, and nobody weighs their roti.",
   "The good news is that home food is repetitive. Most people eat the same ten to fifteen dishes on rotation. Once you know roughly what each one is worth, counting takes seconds."]),
  ("Start with the carbs you can count", [
   ("ul", ["[[f:roti|One plain roti]]: about [[k:roti]] kcal and [[p:roti]] g protein. A ghee roti or a paratha is a different food; a [[f:paratha|plain paratha]] is about [[k:paratha]] kcal.",
           "[[f:rice|One bowl of cooked rice (150 g)]]: about [[k:rice]] kcal. A mess ladle holds roughly 100 g.",
           "[[f:poha|A plate of poha (200 g)]]: about [[k:poha]] kcal, most of it from the flattened rice and oil."]),
   "Counting the roti and rice correctly gets you most of the way, because they are usually half or more of the plate."]),
  ("Then the dal and sabzi, by the katori", [
   "Kynetix uses a 150 g katori. Some reference points from its food table:",
   ("table", ["Dish", "Per katori (150 g)", "Protein"], [
      ["[[f:dal|Plain home dal]]", "[[k:dal]] kcal", "[[p:dal]] g"], ["[[f:dal tadka|Dal tadka]]", "[[k:dal tadka]] kcal", "[[p:dal tadka]] g"],
      ["[[f:dal makhani|Dal makhani]]", "[[k:dal makhani]] kcal", "[[p:dal makhani]] g"], ["[[f:rajma|Rajma]]", "[[k:rajma]] kcal", "[[p:rajma]] g"],
      ["[[f:chole|Chole]]", "[[k:chole]] kcal", "[[p:chole]] g"], ["[[f:aloo gobi|Aloo gobi]]", "[[k:aloo gobi]] kcal", "[[p:aloo gobi]] g"],
      ["[[f:palak paneer|Palak paneer]]", "[[k:palak paneer]] kcal", "[[p:palak paneer]] g"], ["[[f:chicken curry|Chicken curry]]", "[[k:chicken curry]] kcal", "[[p:chicken curry]] g"]]),
   "Notice the spread: dal makhani is nearly double a plain dal, mostly because of butter and cream. The name of the dish tells you a lot."]),
  ("You rarely eat a full katori with roti", [
   "Here is the part most people get wrong. When you eat dal with roti, you don't finish a katori per roti. You eat roughly 50 g of dal with each roti, and a bit more with each ladle of rice. Kynetix sizes the curry by what you ate it with, so \"3 roti and dal\" becomes three roti plus about 150 g of dal, not three katoris.",
   "If you eat more curry than roti, say so once in Kynetix (curry first or carb first) and the portions follow you."]),
  ("The oil you can't see", [
   "A teaspoon of oil or ghee is about 45 kcal. A home sabzi can carry two or three teaspoons per serving, a restaurant one far more. Kynetix's dish values already assume a typical home amount (2 to 5% oil), so you only need to add extra when you know the food was oilier than usual: a dhaba dal, a tadka with a ladle of ghee, or a fried snack.",
   ("ul", ["Restaurant and dhaba food: assume more oil than home, often a lot more.",
           "Fried items (puri, pakode, samosa) are a separate food; a [[f:samosa|samosa]] is about [[k:samosa]] kcal.",
           "Ghee on roti or rice: add it as its own item."])]),
  ("A day, counted", [
   "Breakfast: [[f:poha|poha]] (about [[k:poha]] kcal) and chai. Lunch: three roti ([[k3:roti]] kcal), dal tadka with them and a dry sabzi. Dinner: rice with rajma and curd. Typed into Kynetix as \"3 roti, dal tadka, aloo gobi\", it lands within a sensible range in seconds. It doesn't need to be exact; it needs to be consistent, day after day."]),
  ("How Kynetix does it", [
   "You type the meal the way you'd say it: \"2 roti, 1 katori dal, aloo sabzi, curd\". Kynetix matches each dish to its food table, sizes the curry by the roti and rice, shows the result as Kyno's estimate, and remembers any correction you make. Packaged food goes through the barcode scanner instead.",
   "Browse the full [[g:..|food table]] or try the [[t:calorie-calculator|calorie calculator]] to see what you should be aiming for."]),
 ],
 faq=[("How many calories are in one roti?", "A plain roti is about [[k:roti]] kcal and [[p:roti]] g protein in Kynetix's food table. Ghee on it adds about 45 kcal per teaspoon."),
      ("How many calories are in a katori of dal?", "A 150 g katori of plain home dal is about [[k:dal]] kcal; dal tadka about [[k:dal tadka]] kcal and dal makhani about [[k:dal makhani]] kcal."),
      ("Ghar ke khane ki calories kaise count karein?", "Roti aur chawal gino, dal ya sabzi katori se, aur tel ya ghee alag se jodo. Ek roti lagbhag [[k:roti]] kcal hoti hai.")]),

dict(slug="high-protein-vegetarian-indian-diet", date="2026-10-20",
 title="High-Protein Vegetarian Indian Diet: Foods and a Sample Day | Kynetix",
 h1="High-protein vegetarian Indian diet",
 desc="How to eat 100 g or more of protein a day as an Indian vegetarian: paneer, curd, soya, dal, chana, milk and whey, with protein per serving and a sample day.",
 answer="A vegetarian can reach 100 to 140 g of protein a day on Indian food by building every meal around one dense source: paneer, soya chunks, curd or hung curd, tofu, milk or whey, then adding dal and chana on top. [[f:soya chunks|50 g of dry soya chunks]] alone is about [[p:soya chunks]] g of protein; [[f:paneer|100 g of paneer]] is about [[p:paneer]] g.",
 body=[
  ("Why dal alone won't get you there", [
   "Dal is a good food, but it is not a high-protein one by the katori. [[f:dal tadka|A katori of dal tadka]] is about [[p:dal tadka]] g protein for [[k:dal tadka]] kcal. To reach 120 g from dal you would eat around twenty katoris. Dal is the support act; the lead needs to be denser."]),
  ("The dense vegetarian sources", [
   ("table", ["Food", "Serving", "Protein", "Calories"], [
      ["[[f:soya chunks|Soya chunks]] (dry)", "[[s:soya chunks]]", "[[p:soya chunks]] g", "[[k:soya chunks]] kcal"],
      ["[[f:whey protein in water|Whey in water]]", "[[s:whey protein in water]]", "[[p:whey protein in water]] g", "[[k:whey protein in water]] kcal"],
      ["[[f:low-fat paneer|Low-fat paneer]]", "[[s:low-fat paneer]]", "[[p:low-fat paneer]] g", "[[k:low-fat paneer]] kcal"],
      ["[[f:paneer|Paneer]]", "[[s:paneer]]", "[[p:paneer]] g", "[[k:paneer]] kcal"],
      ["[[f:tofu|Firm tofu]]", "[[s:tofu]]", "[[p:tofu]] g", "[[k:tofu]] kcal"],
      ["[[f:greek yogurt|Greek yogurt]]", "[[s:greek yogurt]]", "[[p:greek yogurt]] g", "[[k:greek yogurt]] kcal"],
      ["[[f:hung curd|Hung curd]]", "[[s:hung curd]]", "[[p:hung curd]] g", "[[k:hung curd]] kcal"],
      ["[[f:skimmed milk|Skimmed milk]]", "[[s:skimmed milk]]", "[[p:skimmed milk]] g", "[[k:skimmed milk]] kcal"],
      ["[[f:sprouts chaat|Sprouts chaat]]", "[[s:sprouts chaat]]", "[[p:sprouts chaat]] g", "[[k:sprouts chaat]] kcal"],
      ["[[f:roasted chana|Roasted chana]]", "[[s:roasted chana]]", "[[p:roasted chana]] g", "[[k:roasted chana]] kcal"]]),
   "Paneer is excellent but calorie heavy because of its fat. On a cut, low-fat paneer, soya, tofu and hung curd give more protein per calorie."]),
  ("A sample 120 g day", [
   ("ul", ["Breakfast: [[f:moong dal cheela|2 moong dal cheelas]] ([[p:moong dal cheela]] g) and a glass of [[f:toned milk|toned milk]] ([[p:toned milk]] g).",
           "Lunch: 2 roti, a katori of [[f:soya curry|soya chunk curry]] ([[p:soya curry]] g) and a katori of [[f:curd|curd]] ([[p:curd]] g).",
           "Evening: [[f:roasted chana|40 g roasted chana]] ([[p:roasted chana]] g) or a scoop of whey ([[p:whey protein in water]] g).",
           "Dinner: rice or roti with [[f:paneer bhurji|paneer bhurji]] ([[p:paneer bhurji]] g) and dal ([[p:dal]] g)."]),
   "That is around 110 to 130 g depending on the snack, from ordinary Indian food. The trick is that every meal has one dense source."]),
  ("Make it easy to keep", [
   ("ul", ["Cook soya chunks in batches: boil, squeeze, freeze. They take the flavour of whatever gravy you put them in.",
           "Hang curd overnight in a cloth to double its protein per spoon.",
           "Keep roasted chana and a protein source at your desk, not just at home.",
           "Spread protein over three or four meals instead of one huge dinner."])]),
  ("What about B12 and iron?", [
   "Vegetarian diets can run low on vitamin B12 and sometimes iron. Kynetix tracks iron, calcium, B12 and a few other nutrients from its micronutrient table, so you can see the trend. If you suspect a deficiency, a blood test and a doctor beat any app."]),
  ("Find your number", [
   "Use the [[t:protein-calculator|protein calculator]]: most people who lift do well on 1.7 to 2.2 g per kg. Kynetix sets it from your weight and goal, and Kyno suggests foods that fit what's left today."]),
 ],
 faq=[("How can a vegetarian get 100 g of protein a day in India?", "Build each meal around one dense source (soya chunks, paneer, tofu, hung curd, milk or whey) and add dal or chana. 50 g of dry soya chunks alone is about [[p:soya chunks]] g."),
      ("Which Indian vegetarian food has the most protein?", "Per serving in Kynetix's table, soya chunks ([[p:soya chunks]] g per 50 g dry), whey ([[p:whey protein in water]] g per scoop) and low-fat paneer ([[p:low-fat paneer]] g per 100 g) lead."),
      ("Veg diet mein protein kaise badhayein?", "Har meal mein ek strong source rakho: paneer, soya, dahi, tofu ya whey. Saath mein dal aur chana. 100 g paneer mein lagbhag [[p:paneer]] g protein hota hai.")]),

dict(slug="protein-for-gym-beginners-india", date="2026-10-20",
 title="Protein for Gym Beginners in India: Veg, Egg and Non-Veg | Kynetix",
 h1="Protein for gym beginners in India",
 desc="How much protein a gym beginner needs, and how to get it on veg, egg or non-veg Indian food, with protein per serving from Kynetix's food table and simple meal plans.",
 answer="As a gym beginner, aim for about 1.6 to 2.0 g of protein per kg of body weight a day: around 110 to 140 g if you weigh 70 kg. Eggs ([[p:boiled eggs]] g in two), chicken ([[p:grilled chicken breast]] g in 150 g grilled breast), paneer, soya and curd make it straightforward on Indian food.",
 body=[
  ("How much you actually need", [
   "Protein needs follow your body weight and goal. Kynetix uses 1.8 g per kg on an average day for maintaining or gaining, a bit more on training days, and up to 2.2 g per kg while losing fat, on a weight capped at a BMI of 27 so extra body fat doesn't inflate the number. The [[t:protein-calculator|protein calculator]] does it for you."]),
  ("If you eat non-veg", [
   ("table", ["Food", "Serving", "Protein"], [
      ["[[f:grilled chicken breast|Grilled chicken breast]]", "[[s:grilled chicken breast]]", "[[p:grilled chicken breast]] g"],
      ["[[f:chicken curry|Chicken curry]]", "[[s:chicken curry]]", "[[p:chicken curry]] g"],
      ["[[f:fish curry|Fish curry]]", "[[s:fish curry]]", "[[p:fish curry]] g"],
      ["[[f:canned tuna in water|Canned tuna]]", "[[s:canned tuna in water]]", "[[p:canned tuna in water]] g"]]),
   "Two meals with chicken or fish and you are most of the way there."]),
  ("If you eat eggs", [
   ("ul", ["[[f:boiled eggs|2 boiled eggs]]: [[p:boiled eggs]] g protein, [[k:boiled eggs]] kcal.",
           "[[f:egg whites|4 egg whites]]: [[p:egg whites]] g protein for only [[k:egg whites]] kcal.",
           "[[f:egg bhurji|Egg bhurji (3 eggs)]]: [[p:egg bhurji]] g."]),
   "Whole eggs are fine; the yolk carries most of the vitamins. Use whites when you want more protein without the calories."]),
  ("If you are vegetarian", [
   "Paneer ([[p:paneer]] g per 100 g), soya chunks ([[p:soya chunks]] g per 50 g dry), curd, milk and whey. The [[g:high-protein-vegetarian-indian-diet|high-protein vegetarian guide]] has a full sample day."]),
  ("Do beginners need whey?", [
   "No, but it is convenient. One scoop in water is about [[p:whey protein in water]] g protein for [[k:whey protein in water]] kcal. Think of it as food, not magic: if you already hit your number from meals, you don't need it."]),
  ("The habits that matter more", [
   ("ul", ["Protein at every meal, not only at dinner.", "Consistency over perfection: close to your number most days beats perfect once a week.",
           "Train with progressive overload; protein supports muscle you're giving a reason to grow.", "Sleep. Recovery is when it happens."])]),
 ],
 faq=[("How much protein should a gym beginner eat?", "About 1.6 to 2.0 g per kg of body weight a day; for a 70 kg beginner that is roughly 110 to 140 g."),
      ("Is 2 eggs a day enough protein?", "Two boiled eggs give about [[p:boiled eggs]] g, a good start but well short of 100 g. Add other sources across the day."),
      ("Beginner ko kitna protein lena chahiye?", "Lagbhag 1.6 se 2 g per kg body weight. 70 kg ho to roz 110 se 140 g.")]),

dict(slug="roti-vs-rice-calories", date="2026-10-20",
 title="Roti vs Rice: Calories, Protein and Which Is Better | Kynetix",
 h1="Roti vs rice: calories and protein",
 desc="Roti or rice for weight loss and gym? Calories, protein, carbs and fiber per roti and per bowl from Kynetix's food table, and how portion size decides the answer.",
 answer="One plain roti is about [[k:roti]] kcal with [[p:roti]] g protein; one bowl of cooked rice (150 g) is about [[k:rice]] kcal with [[p:rice]] g protein. Per serving most people eat, two roti and one bowl of rice are close. Roti has more fiber; the bigger difference is how much of each you eat.",
 body=[
  ("The numbers", [
   ("table", ["Food", "Serving", "Calories", "Protein", "Carbs", "Fiber"], [
      ["[[f:roti|Roti]]", "[[s:roti]]", "[[k:roti]] kcal", "[[p:roti]] g", "[[c:roti]] g", "[[fb:roti]] g"],
      ["[[f:rice|White rice]]", "[[s:rice]]", "[[k:rice]] kcal", "[[p:rice]] g", "[[c:rice]] g", "[[fb:rice]] g"],
      ["[[f:brown rice|Brown rice]]", "[[s:brown rice]]", "[[k:brown rice]] kcal", "[[p:brown rice]] g", "[[c:brown rice]] g", "[[fb:brown rice]] g"],
      ["[[f:ragi roti|Ragi roti]]", "[[s:ragi roti]]", "[[k:ragi roti]] kcal", "[[p:ragi roti]] g", "[[c:ragi roti]] g", "[[fb:ragi roti]] g"]])]),
  ("So which is better?", [
   "For weight loss, neither is a villain. Calories decide fat loss, and two roti or one bowl of rice land in a similar place. Roti tends to be more filling for the calories because of its fiber, and it's easier to count because it comes in pieces. Rice is easy to over-serve: a heaped plate can be two or three bowls.",
   "For the gym, carbs fuel training. Rice before or after a session is perfectly good; many lifters prefer it because it is easy to digest."]),
  ("What actually changes the answer", [
   ("ul", ["Portion: count roti and measure rice by the bowl or ladle.", "What goes on it: ghee on roti, or a rich gravy with rice, can double the meal.",
           "The curry: rice soaks up more of a liquid dal than roti does, which Kynetix accounts for (about 85 g of dal per ladle of rice versus 50 g per roti)."])]),
  ("How to log it", [
   "Type \"3 roti and dal\" or \"1 bowl rice, rajma\" into Kynetix. It counts the roti or rice and sizes the curry to match."]),
 ],
 faq=[("Is roti better than rice for weight loss?", "Not by much. Two roti (about [[k2:roti]] kcal) and a bowl of rice (about [[k:rice]] kcal) are close; roti has more fiber and is easier to portion."),
      ("How many calories in 1 bowl of rice?", "About [[k:rice]] kcal for 150 g of cooked white rice in Kynetix's food table."),
      ("Roti ya chawal, kya better hai?", "Calories mein zyada farak nahi. 2 roti lagbhag [[k2:roti]] kcal aur 1 katori chawal lagbhag [[k:rice]] kcal. Portion zyada important hai.")]),

dict(slug="protein-in-dal-paneer-curd-eggs-soya", date="2026-10-20",
 title="Protein in Dal, Paneer, Curd, Eggs and Soya (Per Serving) | Kynetix",
 h1="How much protein in dal, paneer, curd, eggs and soya",
 desc="Protein per katori, per 100 g and per egg for dal, paneer, curd, eggs and soya chunks, from Kynetix's food table, and which ones give the most protein per calorie.",
 answer="Per serving in Kynetix's food table: a katori of dal tadka has about [[p:dal tadka]] g protein, 100 g of paneer about [[p:paneer]] g, a katori of curd about [[p:curd]] g, two boiled eggs about [[p:boiled eggs]] g and 50 g of dry soya chunks about [[p:soya chunks]] g.",
 body=[
  ("Side by side", [
   ("table", ["Food", "Serving", "Protein", "Calories", "Protein share"], [
      ["[[f:dal tadka|Dal tadka]]", "[[s:dal tadka]]", "[[p:dal tadka]] g", "[[k:dal tadka]] kcal", "[[ps:dal tadka]]%"],
      ["[[f:moong dal|Moong dal]]", "[[s:moong dal]]", "[[p:moong dal]] g", "[[k:moong dal]] kcal", "[[ps:moong dal]]%"],
      ["[[f:paneer|Paneer]]", "[[s:paneer]]", "[[p:paneer]] g", "[[k:paneer]] kcal", "[[ps:paneer]]%"],
      ["[[f:curd|Curd]]", "[[s:curd]]", "[[p:curd]] g", "[[k:curd]] kcal", "[[ps:curd]]%"],
      ["[[f:boiled eggs|Boiled eggs]]", "[[s:boiled eggs]]", "[[p:boiled eggs]] g", "[[k:boiled eggs]] kcal", "[[ps:boiled eggs]]%"],
      ["[[f:soya chunks|Soya chunks]] (dry)", "[[s:soya chunks]]", "[[p:soya chunks]] g", "[[k:soya chunks]] kcal", "[[ps:soya chunks]]%"]]),
   "Protein share is the part of the food's calories that comes from protein. Higher means more protein for the calories."]),
  ("Dal", [
   "Dal is a moderate protein food: [[f:moong dal|moong dal]] about [[p:moong dal]] g, [[f:masoor dal|masoor dal]] about [[p:masoor dal]] g and [[f:toor dal|toor dal]] about [[p:toor dal]] g per katori. It pairs well with rice or roti, and it adds fiber, but it is not enough on its own for a lifter's target."]),
  ("Paneer", [
   "Paneer is protein-rich but also fat-rich: [[k:paneer]] kcal per 100 g. [[f:low-fat paneer|Low-fat paneer]] gives [[p:low-fat paneer]] g protein for [[k:low-fat paneer]] kcal, a better deal when you're cutting."]),
  ("Curd", [
   "A katori of curd is about [[p:curd]] g. Hang it overnight and [[f:hung curd|200 g of hung curd]] reaches about [[p:hung curd]] g; [[f:greek yogurt|Greek yogurt]] about [[p:greek yogurt]] g."]),
  ("Eggs", [
   "Two boiled eggs give about [[p:boiled eggs]] g. [[f:egg whites|Four whites]] give [[p:egg whites]] g for only [[k:egg whites]] kcal."]),
  ("Soya", [
   "Soya chunks are the protein-per-rupee champion for vegetarians. Weigh them dry; 50 g dry swells into a full katori once cooked, and a katori of [[f:soya curry|soya chunk curry]] is about [[p:soya curry]] g."]),
 ],
 faq=[("How much protein is in 1 katori of dal?", "About [[p:dal]] g for plain home dal and [[p:dal tadka]] g for dal tadka, per 150 g katori in Kynetix's food table."),
      ("How much protein is in 100 g paneer?", "About [[p:paneer]] g in regular paneer and [[p:low-fat paneer]] g in low-fat paneer."),
      ("Dal mein kitna protein hota hai?", "Ek katori dal tadka mein lagbhag [[p:dal tadka]] g protein hota hai. Moong dal mein lagbhag [[p:moong dal]] g.")]),

dict(slug="beginner-gym-workout-split", date="2026-10-20",
 title="Beginner Gym Workout Split: Full Body, PPL or Bro Split? | Kynetix",
 h1="Gym workout split for beginners",
 desc="Full body, upper lower, push pull legs or bro split: which gym split suits a beginner, with sample weeks, exercises, sets and reps, and how to choose by days per week.",
 answer="If you can train three days a week, start with full body. Four days suits an upper and lower split. Five or six days suits push, pull, legs. A bro split (one muscle a day) works too, but hits each muscle only once a week, which is slower for most beginners.",
 body=[
  ("Choose by the days you can actually train", [
   ("table", ["Days a week", "Split", "Each muscle trained"], [["3", "Full body", "3 times a week"], ["4", "Upper / lower", "2 times a week"],
      ["5 to 6", "Push / pull / legs", "About 2 times a week"], ["5", "Bro split", "Once a week"]]),
   "The best split is the one you will still be doing in six months. Pick the days you can protect, not the days you hope for."]),
  ("Full body (3 days)", [
   ("ul", ["[[x:barbell-back-squat|Squat]] or [[x:leg-press|leg press]]: 3 x 6 to 10", "[[x:barbell-bench-press|Bench press]] or [[x:incline-dumbbell-press|incline dumbbell press]]: 3 x 6 to 10",
           "[[x:lat-pulldown|Lat pulldown]] or [[x:seated-cable-row|seated cable row]]: 3 x 8 to 12", "[[x:romanian-deadlift|Romanian deadlift]]: 2 x 8 to 10",
           "[[x:dumbbell-lateral-raise|Lateral raise]] and an arm move: 2 x 12 to 15"])]),
  ("Push / pull / legs", [
   ("ul", ["Push: [[x:barbell-bench-press|bench press]], [[x:barbell-overhead-press|overhead press]], [[x:incline-dumbbell-press|incline dumbbell press]], [[x:dumbbell-lateral-raise|lateral raise]], [[x:tricep-pushdown|tricep pushdown]].",
           "Pull: [[x:pull-ups|pull-ups]] or [[x:lat-pulldown|lat pulldown]], [[x:barbell-bent-over-row|bent-over row]], [[x:cable-face-pull|face pull]], [[x:barbell-biceps-curl|biceps curl]], [[x:dumbbell-hammer-curl|hammer curl]].",
           "Legs: [[x:barbell-back-squat|squat]], [[x:romanian-deadlift|Romanian deadlift]], [[x:leg-press|leg press]], [[x:lying-leg-curl|leg curl]], [[x:standing-calf-raise|calf raise]]."]),
   "Run it once (3 days) or twice (6 days) a week."]),
  ("Bro split", [
   "Chest, back, shoulders, arms, legs, one per day. It is popular in Indian gyms and it does work, especially for people who love long sessions on one muscle. The catch is frequency: each muscle grows from a session and then waits a week. If you choose it, keep the volume high and the effort honest."]),
  ("Sets, reps and rest", [
   ("ul", ["Big compound lifts: 3 to 4 sets of 5 to 10 reps, 2 to 3 minutes rest.", "Smaller moves: 2 to 3 sets of 10 to 15 reps, about 90 seconds rest.",
           "Finish most sets with one or two good reps left in the tank."])]),
  ("How Kynetix helps", [
   "Pick a split (push pull legs, upper lower, full body, bro split or your own) and Kynetix lays out the week, shows what's on today and how long it runs, and suggests the next weight on each lift from your history. Read [[g:how-to-track-progressive-overload|how to track progressive overload]] next."]),
 ],
 faq=[("What is the best workout split for beginners?", "Full body three days a week for most beginners; upper lower for four days; push pull legs for five or six."),
      ("Is bro split good for beginners?", "It works, but each muscle is trained once a week. Most beginners progress faster training each muscle twice a week."),
      ("Beginner ke liye kaunsa split best hai?", "Hafte mein 3 din ho to full body, 4 din ho to upper lower, 5 se 6 din ho to push pull legs.")]),

dict(slug="how-to-track-progressive-overload", date="2026-10-20",
 title="How to Track Progressive Overload (Sets, Reps, 1RM) | Kynetix",
 h1="How to track progressive overload",
 desc="Progressive overload explained simply: double progression, when to add weight, how to read estimated one rep max and volume, and how to log it so you actually progress.",
 answer="Progressive overload means doing a little more over time: more reps at the same weight, then more weight. The simplest way to track it is double progression: work in a rep range, add reps each session, and add the smallest weight jump once every set hits the top of the range.",
 body=[
  ("Double progression, step by step", [
   ("ul", ["Pick a rep range, for example 8 to 12.", "Choose a weight you can lift for 8 clean reps on every set.",
           "Each session, try to add a rep to some sets.", "When every set reaches 12, add the smallest jump: 2.5 kg on a barbell, the next dumbbell, the next pin.",
           "Drop back near 8 reps with the new weight and climb again."]),
   "It works because you always know exactly what to beat."]),
  ("What to write down", [
   "For every working set: the weight and the reps. That's it. Warm-up sets don't count toward your progress, so keep them separate. Notes on how a set felt help when you look back."]),
  ("Estimated one rep max", [
   "An estimated one rep max (1RM) turns any set into one comparable number. Kynetix uses the Epley formula: weight x (1 + reps / 30). 60 kg for 8 reps estimates to 76 kg. If that number rises over weeks, you're getting stronger, even if you never test a true max. Try the [[t:one-rep-max-calculator|one rep max calculator]]."]),
  ("Volume", [
   "Volume is sets x reps x weight. It is a useful check for muscle growth: rising volume on a muscle over a few weeks usually means you're doing enough. Kynetix totals it for each session and shows kilos lifted for the week."]),
  ("When progress stalls", [
   ("ul", ["Check sleep and food first. Eating below maintenance makes progress slower, especially on big lifts.",
           "Repeat the weight for another week before you change anything.", "Take a lighter week if several lifts stall at once.",
           "Swap a stuck exercise for a close variation for a few weeks."])]),
  ("How Kynetix tracks it", [
   "Log a set in a tap with weight and rep steppers, with your last set shown right there. The rest timer starts on its own. Personal records are spotted as you lift, and Kyno suggests the next weight from your own history, so double progression runs itself."]),
 ],
 faq=[("What is progressive overload?", "Gradually doing more over time: more reps at the same weight, then more weight, so your muscles keep a reason to adapt."),
      ("How do I know when to increase weight?", "When every working set reaches the top of your rep range with good form, add the smallest jump and start again near the bottom of the range."),
      ("Weight kab badhana chahiye?", "Jab har set mein rep range ka top number clean form ke saath ho jaye, tab sabse chhota jump add karo.")]),

dict(slug="cutting-and-bulking-on-indian-food", date="2026-10-20",
 title="Cutting and Bulking on Indian Food: A Practical Guide | Kynetix",
 h1="Cutting and bulking on Indian food",
 desc="How to cut or bulk on home Indian food: calorie targets, protein first, what to change on the plate, and sample swaps with numbers from Kynetix's food table.",
 answer="To cut, eat about 22% below maintenance with high protein (around 2.1 g per kg) and keep lifting heavy. To bulk, eat about 8 to 10% above maintenance with around 1.8 g per kg of protein. On Indian food, the levers are roti and rice portions, oil and ghee, and making sure every meal has a protein source.",
 body=[
  ("Set the numbers first", [
   "Find your maintenance with the [[t:calorie-calculator|calorie calculator]]. Kynetix cuts at 22% below maintenance (350 to 550 kcal), lean bulks at 8% above (150 to 250 kcal) and bulks at 10% (200 to 350 kcal). Protein comes from the [[t:protein-calculator|protein calculator]]."]),
  ("Cutting: what changes on the plate", [
   ("ul", ["Keep the roti count steady and drop one serving, or swap a bowl of rice for two roti.",
           "Choose the leaner curry: [[f:dal|plain dal]] ([[k:dal]] kcal a katori) over [[f:dal makhani|dal makhani]] ([[k:dal makhani]] kcal).",
           "Swap regular paneer ([[k:paneer]] kcal per 100 g) for [[f:low-fat paneer|low-fat paneer]] ([[k:low-fat paneer]] kcal) or [[f:tofu|tofu]].",
           "Measure the oil. Each teaspoon is about 45 kcal.", "Add a protein snack: [[f:roasted chana|roasted chana]], [[f:hung curd|hung curd]] or whey."])]),
  ("Bulking: what changes on the plate", [
   ("ul", ["Add a roti or half a bowl of rice to each meal before reaching for junk.",
           "Milk is an easy surplus: [[f:toned milk|a glass of toned milk]] is about [[k:toned milk]] kcal and [[p:toned milk]] g protein.",
           "[[f:peanuts|Peanuts]] ([[k:peanuts]] kcal per 30 g) and [[f:peanut butter|peanut butter]] add calories without a huge meal.",
           "Keep the surplus small. Bigger surpluses mostly add fat."])]),
  ("Training doesn't change", [
   "Cut or bulk, keep lifting with [[g:how-to-track-progressive-overload|progressive overload]]. On a cut, holding your strength is the win. On a bulk, adding reps and weight every few weeks tells you the surplus is doing its job."]),
  ("Training days and rest days", [
   "Kynetix gives training days a little more food than rest days (140 to 220 kcal apart), weighted so your weekly average still matches the goal. It means more fuel when you lift without overshooting the week."]),
  ("Check the trend, not the day", [
   "Weigh yourself a few mornings a week and watch the weekly average. Aim for 0.5 to 1% of body weight a week on a cut, and a slow climb on a bulk. Kynetix reads weight from Health Connect if you allow it."]),
 ],
 faq=[("How many calories should I cut to lose fat?", "Kynetix uses about 22% below maintenance, between 350 and 550 kcal a day, which usually means losing 0.5 to 1% of body weight a week."),
      ("How do I bulk on Indian food?", "Eat about 8 to 10% above maintenance: add roti or rice, milk, peanuts and an extra protein source, and keep training with progressive overload."),
      ("Cutting mein kya khana chahiye?", "Protein zyada rakho (paneer, soya, dahi, chicken, eggs), tel aur ghee naap ke, aur roti ya chawal thoda kam.")]),

dict(slug="fasting-and-training-vrat-roza-16-8", date="2026-10-20",
 title="Fasting and Gym Training: Vrat, Roza and 16:8 | Kynetix",
 h1="Fasting and training: vrat, roza and 16:8",
 desc="How to train and keep your protein during Navratri vrat, Ramadan roza or 16:8 intermittent fasting, with vrat-friendly foods and timing tips that actually work.",
 answer="You can keep training while fasting if you move your session close to a meal, keep protein high in your eating window, and lighten the load on the hardest days. During vrat, dairy, paneer, peanuts and makhana carry the protein; during roza, split protein between sehri and iftar; on 16:8, fit two or three protein-rich meals into the window.",
 body=[
  ("Navratri and Ekadashi vrat", [
   "A typical vrat skips grains and pulses, which removes dal, roti and rice. Protein then comes from dairy and nuts. Vrat-friendly foods in Kynetix's table:",
   ("table", ["Food", "Serving", "Calories", "Protein"], [
      ["[[f:paneer|Paneer]]", "[[s:paneer]]", "[[k:paneer]] kcal", "[[p:paneer]] g"], ["[[f:curd|Curd]]", "[[s:curd]]", "[[k:curd]] kcal", "[[p:curd]] g"],
      ["[[f:toned milk|Toned milk]]", "[[s:toned milk]]", "[[k:toned milk]] kcal", "[[p:toned milk]] g"],
      ["[[f:peanuts|Peanuts]]", "[[s:peanuts]]", "[[k:peanuts]] kcal", "[[p:peanuts]] g"], ["[[f:makhana|Makhana]]", "[[s:makhana]]", "[[k:makhana]] kcal", "[[p:makhana]] g"],
      ["[[f:sabudana khichdi|Sabudana khichdi]]", "[[s:sabudana khichdi]]", "[[k:sabudana khichdi]] kcal", "[[p:sabudana khichdi]] g"],
      ["[[f:kuttu roti|Kuttu roti]]", "[[s:kuttu roti]]", "[[k:kuttu roti]] kcal", "[[p:kuttu roti]] g"]]),
   "Sabudana is mostly starch and oil, so it fills calories fast but adds little protein. Pair it with curd or paneer. Kynetix marks vrat-friendly foods and Kyno keeps its suggestions inside the rules of your fast."]),
  ("Ramadan roza", [
   ("ul", ["Train shortly before iftar if you can, or an hour or two after it.", "Split protein across sehri and iftar, with a protein snack later at night.",
           "Hydrate through the evening; dehydration hurts strength more than hunger does.", "Keep the weights, cut a set or two on the hardest days."])]),
  ("16:8 intermittent fasting", [
   "16:8 is simply a 16-hour gap and an 8-hour eating window. For lifting, put the window around your session, and fit two or three meals that each carry a solid protein source. Calories still decide fat loss; fasting is just a way to arrange them."]),
  ("Safety first", [
   "If you have diabetes, take medication, are pregnant, or have a history of disordered eating, talk to a doctor before fasting and training together. Stop a session if you feel dizzy or faint."]),
  ("How Kynetix handles fasts", [
   "Kynetix has a fasting timer and knows which foods are vrat-friendly, so Kyno suggests foods that fit both your fast and your remaining protein."]),
 ],
 faq=[("Can I go to the gym during Navratri fast?", "Yes, for most healthy people. Train near a meal, keep protein from paneer, curd, milk and peanuts, and go lighter if you feel weak."),
      ("When should I work out during Ramadan?", "Shortly before iftar, or an hour or two after it, so you can eat and drink soon after training."),
      ("Vrat mein protein kaise lein?", "Paneer, dahi, doodh, moongphali aur makhana. 100 g paneer mein lagbhag [[p:paneer]] g protein.")]),

dict(slug="health-connect-setup-for-fitness-apps", date="2026-10-20",
 title="How to Set Up Health Connect for Fitness Apps on Android | Kynetix",
 h1="How to set up Health Connect for fitness apps",
 desc="What Health Connect is, how to install and set it up on Android, how to give a fitness app access to steps, weight and sleep, and how to turn access off again.",
 answer="Health Connect is Android's shared health store: apps like your step counter, smartwatch app and Kynetix read and write data there with your permission. Install or open Health Connect (built into Android 14 and later), connect your step or watch app, then allow Kynetix to read steps, weight, sleep and HRV. You can revoke access any time.",
 body=[
  ("What Health Connect is", [
   "Before Health Connect, every fitness app kept its own copy of your steps and weight. Health Connect is a single place on your phone where apps share that data, only with your permission and only the types you allow. It lives on the device."]),
  ("Get Health Connect", [
   ("ul", ["Android 14 and later: Health Connect is built in. Find it in Settings, under Security and privacy, Privacy, Health Connect (the path varies slightly by brand).",
           "Android 9 to 13: install Health Connect from the Google Play Store."])]),
  ("Connect your data sources", [
   "Open the app that counts your steps or reads your watch (for example Google Fit, Samsung Health or your watch's app) and turn on syncing to Health Connect in its settings. Weight from a smart scale app works the same way."]),
  ("Give Kynetix read access", [
   ("ul", ["In Kynetix, go to Profile and connect Health Connect.", "Android shows a permission screen. Pick the types you want to share: steps, weight, sleep and heart rate variability.",
           "That's it. Kynetix reads them; it never writes to Health Connect."]),
   "Kynetix uses steps to size your calorie target (each step above 7,000 a day adds a little), weight for your trend, and sleep and HRV for Kyno's recovery read."]),
  ("Turn it off", [
   "Open Health Connect, choose App permissions, pick Kynetix and switch off any type, or remove access entirely. Kynetix keeps working without it; your targets just won't adjust for steps."]),
  ("Privacy", [
   "Kynetix only reads what you allow and doesn't sell or share it for ads. See the [[pp|privacy policy]] for exactly what is stored."]),
 ],
 faq=[("Is Health Connect safe?", "It is Google's on-device health store, and apps can only read or write the data types you approve. You can revoke access at any time."),
      ("Does Kynetix write to Health Connect?", "No. Kynetix only reads steps, weight, sleep and HRV, and only the ones you allow."),
      ("Health Connect kahan milta hai?", "Android 14 aur naye phones mein Settings mein built-in hota hai. Purane Android par Play Store se install karo.")]),
]
