def median: sort | if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
def mean: if length == 0 then null else add / length end;
def r2: if . == null then null else . * 100 | round / 100 end;
def pct: if . == null then "–" else "\(. * 100 | round)%" end;
def tier: if startswith("pi-") then 0 elif . == "pipeline" then 0 elif . == "claude-sonnet" then 1 else 2 end;
def kilo: if . == null then "–" elif . >= 1000000 then "\(. / 100000 | round / 10)M" else "\(. / 1000 | round)k" end;
def usd: if . == null then "–" else "$\(. * 100 | round / 100)" end;
def row: "| " + join(" | ") + " |";

. as $all
| ($order + ([$all[].task] | unique - $order)) as $tasks
| ((["claude-opus", "claude-sonnet"] | map(select(. as $a | $all | any(.arm == $a))))
   + ([$all[].arm | select(startswith("pi-"))] | unique)
   + ([$all[].arm | select(. == "pipeline")] | unique)
   + ([$all[].arm] | unique | map(select(test("^(claude-|pi-|pipeline$)") | not)))) | unique_by(.) as $arms0
| ((["claude-opus", "claude-sonnet"] | map(select(IN($arms0[])))) + ($arms0 - ["claude-opus", "claude-sonnet"])) as $arms
| def runs($t; $a): [$all[] | select(.task == $t and .arm == $a)];
  def stats($rs): {n: ($rs | length), pass: ([$rs[] | select(.pass)] | length),
    rate: (if ($rs | length) > 0 then ([$rs[] | select(.pass)] | length) / ($rs | length) else null end),
    frac: ([$rs[].new_tests_frac] | mean | r2), wall: ([$rs[].wall_s] | median),
    cost: ([$rs[].cost_usd // 0] | add), tokens: ([$rs[] | .tokens.total // ((.tokens.in // 0) + (.tokens.out // 0) + (.tokens.cache_read // 0) + (.tokens.cache_write // 0))] | median)};
  def cell($t; $a; f): runs($t; $a) as $rs | if ($rs | length) == 0 then "–" else (stats($rs) | f) end;
  def best($t): [$arms[] | select(. != "pipeline") | . as $a | stats(runs($t; $a)) + {arm: $a, tier: ($a | tier)}
      | select(.n > 0 and .rate >= 0.5)] | sort_by(.tier, -.rate, .wall) | first;
  def jevtier: if . == "nan-flash" then 0 elif . == "claude-sonnet" then 1 elif . == "claude-opus" then 2 else null end;
  def routetier: if . == null then null elif startswith("pi ") then 0 elif startswith("claude sonnet") then 1 else 2 end;

  "# Bench results",
  "",
  "\($all | length) runs, \($tasks | length) tasks, \($arms | length) arms. Cell: passes/runs (mean fraction of the merged commit's new tests passing).",
  "",
  "## Pass rate by task × arm",
  "",
  (["task"] + $arms | row),
  (["---"] + ($arms | map("---")) | row),
  ($tasks[] as $t | [$t] + ($arms | map(. as $a | cell($t; $a; "\(.pass)/\(.n) (\(.frac))"))) | row),
  "",
  "## Median wall time (s)",
  "",
  (["task"] + $arms | row),
  (["---"] + ($arms | map("---")) | row),
  ($tasks[] as $t | [$t] + ($arms | map(. as $a | cell($t; $a; "\(.wall)"))) | row),
  "",
  "## Cost per run (Claude: total USD for the task's runs; NAN: median tokens per run, quota not money)",
  "",
  (["task"] + $arms | row),
  (["---"] + ($arms | map("---")) | row),
  ($tasks[] as $t | [$t] + ($arms | map(. as $a | cell($t; $a; if ($a | startswith("claude-")) then (.cost | usd) else (.tokens | kilo) end))) | row),
  "",
  "## Per arm",
  "",
  "| arm | runs | pass | new tests | median s | Claude $ | median tokens | protocol | START ok | DONE ok | stray files | out of scope | timeouts | runs with errors | 429s |",
  "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
  ($arms[] as $a | [$all[] | select(.arm == $a)] as $rs | stats($rs) as $s
    | [$a, "\($s.n)", "\($s.pass) (\($s.rate | pct))", "\($s.frac)", "\($s.wall)",
       (if ($a | startswith("claude-")) then ($s.cost | usd) else "–" end), ($s.tokens | kilo),
       "\([$rs[].protocol_score] | mean | r2)",
       ([$rs[] | .protocol.start] | map(if . then 1 else 0 end) | mean | pct),
       ([$rs[] | .protocol.done] | map(if . then 1 else 0 end) | mean | pct),
       ([$rs[] | select(.protocol.stray | length > 0)] | length | tostring),
       ([$rs[] | select(.protocol.out_of_scope | length > 0)] | length | tostring),
       ([$rs[] | select(.timed_out)] | length | tostring),
       ([$rs[] | select(.errors | length > 0)] | length | tostring),
       ([$rs[].http429] | add | tostring)] | row),
  "",
  "## Jev pick vs best cheapest passing arm",
  "",
  "Best cheapest passing arm: the cheapest tier (NAN < Sonnet < Opus) with an arm passing at least half its runs; within the tier, the highest pass rate, then the fastest. Jev = raw answer to route.sh's question; route.sh = what cheap-mvp's router finally picks (its pre-checks and confidence threshold included).",
  "",
  "| task | best cheapest passing | Jev | route.sh | Jev tier right? |",
  "|---|---|---|---|---|",
  ($tasks[] as $t | best($t) as $b | ([$jev[] | select(.task == $t)] | last) as $j
    | [$t, (if $b then "\($b.arm) (\($b.pass)/\($b.n))" elif ([$all[] | select(.task == $t)] | length) > 0 then "none passes" else "–" end),
       (if $j.choice then "\($j.choice) \($j.confidence | r2)" else "–" end),
       ($j.route // "–"),
       (if $b == null or $j.choice == null then "–"
        elif ($j.choice | jevtier) == $b.tier then "yes"
        elif ($j.choice | jevtier) > $b.tier then "no, over-spends"
        else "no, under-routes" end)] | row),
  "",
  "## Escalation ladder, simulated from these pass rates",
  "",
  "Ladder: \($ladder | map("\(.arm)×\(.tries)") | join(" → ")). Each try passes with the arm's observed pass rate on that task (independent tries: optimistic for a model that fails the same way twice). Baseline: every task on claude-opus once.",
  "",
  "| task | P(done by NAN) | P(done) ladder | P(done) opus only | expected Claude $ ladder | Claude $ opus only |",
  "|---|---|---|---|---|---|",
  ([$tasks[] as $t
    | ([$ladder[] | . as $l | stats(runs($t; $l.arm)) + $l]) as $steps
    | (stats(runs($t; "claude-opus"))) as $op
    | (reduce $steps[] as $s ({left: 1, nan: 0, cost: 0};
        if $s.n == 0 then . else
        (if ($s.arm | startswith("claude-")) then .cost += .left * ($s.cost / $s.n) * $s.tries else . end)
        | (pow(1 - $s.rate; $s.tries)) as $miss
        | (if ($s.arm | startswith("claude-") | not) then .nan += .left * (1 - $miss) else . end)
        | .left *= $miss end)) as $sim
    | {t: $t, nan: $sim.nan, done: (1 - $sim.left), opus: $op.rate, cost: $sim.cost, opcost: (if $op.n > 0 then $op.cost / $op.n else null end)}]) as $rows
  | ($rows[] | [.t, (.nan | pct), (.done | pct), (.opus | pct), (.cost | usd), (.opcost | usd)] | row),
    ([ "**all**", ([$rows[].nan] | mean | pct), ([$rows[].done] | mean | pct), ([$rows[].opus | values] | mean | pct),
       ([$rows[].cost] | add | usd), ([$rows[].opcost | values] | add | usd)] | row)
