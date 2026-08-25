# Evidence ledger

This ledger records why Ted makes a coaching decision. It is not a claim that one rule fits every person. Study populations, measurement methods, intervention lengths, and training status differ. Ted therefore stores the evidence used by each plan, reports confidence, waits for a review window, and makes bounded changes.

Last reviewed: 16 August 2026.

## Weight loss while preserving strength and muscle

A 2025 systematic review and meta-analysis found that adding resistance exercise to dietary weight loss increased fat loss, protected fat-free mass, and improved strength compared with diet alone. Body weight alone can therefore hide a useful change in body composition. [López et al., 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC12406911/)

A randomized trial in trained athletes compared slower and faster weight loss. The slower group targeted about 0.7 percent of body weight per week, gained lean body mass, and improved some strength measures, while the faster group targeted about 1.4 percent per week. The sample was small and athletic, so Ted uses a conservative range rather than treating 0.7 percent as universal. [Garthe et al., 2011](https://pubmed.ncbi.nlm.nih.gov/21558571/)

A meta-analysis of resistance training during energy restriction found that larger energy deficits impaired gains in lean mass. Its model estimated that a deficit around 500 kilocalories per day prevented lean-mass gain, but individual responses varied. Ted does not automatically prescribe a deficit larger than this and does not infer a precise deficit from incomplete meal logs. [Murphy and Koehler, 2022](https://onlinelibrary.wiley.com/doi/abs/10.1111/sms.14075)

Implementation:

- Fat-loss plans target a gradual trend from negative 0.75 to negative 0.25 percent of recorded body weight per week.
- Body recomposition considers weight trend and strength together instead of minimizing weight alone.
- Resistance training remains part of fat-loss plans when it is safe and feasible.
- A plan review changes energy by no more than 5 percent and no more than 200 kilocalories at once.

## Protein and resistance training

A large systematic review and meta-analysis found that protein supplementation improved strength and fat-free mass gains during prolonged resistance training. The modeled benefit plateaued around 1.62 grams per kilogram of body weight per day, with the upper confidence limit near 2.2 grams per kilogram. The underlying studies and participants varied considerably. [Morton et al., 2018](https://pubmed.ncbi.nlm.nih.gov/28698222/)

An updated 2025 review focused on resistance-trained adults under energy restriction and modeled a positive relationship between protein intake and fat-free mass change, while emphasizing that the result was exploratory and that the evidence remains heterogeneous. [Henselmans et al., 2025](https://openrepository.aut.ac.nz/items/1aa54baf-6885-4739-aba7-df0087c3eae8)

Implementation:

- When the person has not set a target, Ted may start from 1.6 grams per kilogram of the latest recorded body weight.
- The generated plan labels that value as an estimate, records its basis, and allows the person to override it.
- Ted never converts estimated meals into measured intake.

## Actionable meal recommendations

A small randomized crossover feeding study found higher 24-hour muscle protein synthesis when roughly 30 grams of protein was distributed across each of three meals instead of being concentrated at dinner. The study included only eight healthy adults and measured a short-term biological response, not long-term strength or muscle gain. [Mamerow et al., 2014](https://pubmed.ncbi.nlm.nih.gov/24477298/)

A systematic review of 15 studies found that a more even protein distribution was associated with higher muscle mass in some studies, but the evidence was insufficient for firm conclusions about strength or protein turnover. Ted therefore treats distribution as a practical planning aid, not an exact biological rule. [Jespersen and Agergaard, 2021](https://pubmed.ncbi.nlm.nih.gov/33550490/)

In a 12-week controlled trial, 38 healthy young men following protein-matched vegan and omnivorous diets had similar gains in leg lean mass, muscle size, and leg-press strength during resistance training. The vegan group used soy protein and the result should not be generalized to every population or plant-based diet. [Hevia-Larraín et al., 2021](https://pubmed.ncbi.nlm.nih.gov/33599941/)

A 2025 systematic review and meta-analysis of randomized trials found no pooled difference between soy and milk protein for muscle mass. Animal protein had a small pooled advantage over the non-soy plant proteins studied, while no difference was found for strength or physical performance. The range of plant proteins and whole diets remains limited. [Reynolds et al., 2025](https://pubmed.ncbi.nlm.nih.gov/39813010/)

Implementation:

- `recommend_meal` starts with the person’s recorded dietary pattern, explicitly avoided ingredients, active objective, and time available.
- When every logged meal has a protein estimate, the suggested contribution divides the recorded gap across practical remaining eating opportunities. If any meal is unquantified, Ted uses one quarter of the daily target and says that the true remaining intake is unknown.
- A suggested contribution is bounded between 20 and 45 grams for usability. This is a product bound, not a claim that this range is optimal for every person or meal.
- Vegetarian and vegan templates emphasize varied legumes and soy options. Ted presents the supporting plant-protein evidence and its population limits alongside the recommendation.
- Energy remaining is shown only when every meal logged that day has an energy estimate. Template nutrition is never stored or presented as measured intake.
- A known avoided ingredient removes incompatible templates. Every response still tells the person to check allergens and clinician-directed restrictions.

## Gaining muscle without chasing weight gain

A controlled study in resistance-trained people compared planned energy surpluses. Faster body-mass gain was more clearly associated with increased skinfold thickness than with greater muscle thickness or strength. The intervention was short and the sample was small, so Ted uses it to justify conservative rates rather than a precise optimal surplus. [Helms et al., 2023](https://openrepository.aut.ac.nz/server/api/core/bitstreams/8dd49069-b58f-47ab-a7f4-ab1e78bc7245/content)

Implementation:

- Muscle-gain plans use smaller target rates as training experience increases.
- Faster scale gain does not automatically count as better progress.
- Strength, completed training, recovery, and body-weight trend are reviewed together.

## Training effort and daily adjustment

A meta-analysis found that resistance training closer to momentary muscular failure tended to produce greater muscle growth, but the evidence did not show that every set must reach failure. [Refalo et al., 2024](https://pubmed.ncbi.nlm.nih.gov/38970765/)

A systematic review and meta-analysis found that autoregulated resistance training produced a small advantage over fixed loading for maximal strength, though methods and study quality varied. [Zourdos et al., 2022](https://pubmed.ncbi.nlm.nih.gov/35038063/)

Implementation:

- Default work sets end with about two repetitions still possible.
- Daily energy, sleep, soreness, pain, and recent completed sessions can reduce the session without rewriting the whole plan.
- Meaningful pain is not treated as ordinary soreness and places training progression on hold.

## Tracking and coaching feedback

A systematic review found that digital self-monitoring was commonly associated with weight loss, while engagement usually declined over time and study designs varied. [Patel et al., 2021](https://pubmed.ncbi.nlm.nih.gov/34192411/)

In a randomized clinical trial, adding daily automated feedback to a digital self-monitoring program did not improve weight loss compared with self-monitoring alone. More messages are not necessarily more coaching. [Burke et al., 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9297147/)

An adaptive intervention trial found that adding wireless feedback and later human coaching improved six-month weight loss relative to the control approach. This supports escalation and review rather than endless generic nudges. [Spring et al., 2024](https://jamanetwork.com/journals/jama/fullarticle/2818967)

Implementation:

- Ted keeps logging brief and useful, then summarizes the trend at a review boundary.
- A review requires at least seven check-ins by default.
- Low adherence leads to simplifying the current plan, not immediately making the prescription more aggressive.
- Ted records `needs_data`, `no_change`, `adjusted`, or `safety_hold` with low, moderate, or high confidence.

## Updating this ledger

Changing a numerical coaching rule requires:

1. Adding or updating the primary paper or systematic review here.
2. Describing the relevant population, limitation, and uncertainty.
3. Updating the planner or reviewer test that proves the bounded behavior.
4. Keeping the evidence address in `Ted.Coaching.PlanBuilder` so a stored plan remains auditable.
