def median: sort | if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
def mean: if length == 0 then null else add / length end;
def r2: if . == null then null else . * 100 | round / 100 end;
def pct: if . == null then "–" else "\(. * 100 | round)%" end;
def tier: if startswith("pi-") then 0 elif startswith("pipeline") then 0 elif . == "claude-sonnet" then 1 else 2 end;
def kilo: if . == null then "–" elif . >= 1000000 then "\(. / 100000 | round / 10)M" else "\(. / 1000 | round)k" end;
def usd: if . == null then "–" else "$\(. * 100 | round / 100)" end;
def row: "| " + join(" | ") + " |";

. as $raw
| ([$raw[] | select(.infra != true and .superseded == null)] | group_by([.task, .arm, .rep]) | map(sort_by(.ts) | first)) as $all
| ($order + ([$all[].task] | unique - $order)) as $tasks
| ((["claude-opus", "claude-sonnet"] | map(select(. as $a | $all | any(.arm == $a))))
   + ([$all[].arm | select(startswith("pi-"))] | unique)
   + ([$all[].arm | select(startswith("pipeline"))] | unique)
   + ([$all[].arm] | unique | map(select(test("^(claude-|pi-|pipeline)") | not)))) | unique_by(.) as $arms0
| ((["claude-opus", "claude-sonnet"] | map(select(IN($arms0[])))) + ($arms0 - ["claude-opus", "claude-sonnet"])) as $arms
| def runs($t; $a): [$all[] | select(.task == $t and .arm == $a)];
  def stats($rs): {n: ($rs | length), pass: ([$rs[] | select(.pass)] | length),
    rate: (if ($rs | length) > 0 then ([$rs[] | select(.pass)] | length) / ($rs | length) else null end),
    frac: ([$rs[].new_tests_frac] | mean | r2), wall: ([$rs[].wall_s] | median),
    cost: ([$rs[].cost_usd // 0] | add), tokens: ([$rs[] | .tokens.total // ((.tokens.in // 0) + (.tokens.out // 0) + (.tokens.cache_read // 0) + (.tokens.cache_write // 0))] | median)};
  def cell($t; $a; f): runs($t; $a) as $rs | if ($rs | length) == 0 then "–" else (stats($rs) | f) end;
  def best($t): [$arms[] | select(startswith("pipeline") | not) | . as $a | stats(runs($t; $a)) + {arm: $a, tier: ($a | tier)}
      | select(.n > 0 and .rate >= 0.5)] | sort_by(.tier, -.rate, .wall) | first;
  def jevtier: if . == "nan-flash" then 0 elif . == "claude-sonnet" then 1 elif . == "claude-opus" then 2 else null end;
  def routetier: if . == null then null elif startswith("pi ") then 0 elif startswith("claude sonnet") then 1 else 2 end;

  "# Bench results",
  "",
  "\($all | length) runs, \($tasks | length) tasks, \($arms | length) arms. Each task × arm × rep counts its first attempt that was not cut short by NAN throttling or an API error (\([$raw[] | select(.infra == true)] | length) such attempts re-run, not counted; \([$raw[] | select(.infra != true and .superseded == null)] | length - ($all | length)) later attempts of an already counted run, not counted either; \([$raw[] | select(.superseded)] | length) superseded by a harness change and re-run). Cell: passes/runs (mean fraction of the merged commit's new tests passing).",
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
  "| arm | runs | pass | new tests | median s | Claude $ | median tokens | protocol | START ok | DONE ok | stray files | out of scope | timeouts | hit output cap | runs with errors | 429s | throttled, re-run |",
  "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
  ($arms[] as $a | [$all[] | select(.arm == $a)] as $rs | stats($rs) as $s
    | [$a, "\($s.n)", "\($s.pass) (\($s.rate | pct))", "\($s.frac)", "\($s.wall)",
       (if ($a | startswith("claude-")) then ($s.cost | usd) else "–" end), ($s.tokens | kilo),
       "\([$rs[].protocol_score] | mean | r2)",
       ([$rs[] | .protocol.start] | map(if . then 1 else 0 end) | mean | pct),
       ([$rs[] | .protocol.done] | map(if . then 1 else 0 end) | mean | pct),
       ([$rs[] | select(.protocol.stray | length > 0)] | length | tostring),
       ([$rs[] | select(.protocol.out_of_scope | length > 0)] | length | tostring),
       ([$rs[] | select(.timed_out)] | length | tostring),
       ([$rs[] | select(.stop == "length")] | length | tostring),
       ([$rs[] | select(.errors | length > 0)] | length | tostring),
       ([$rs[].http429] | add | tostring),
       ([$raw[] | select(.arm == $a and .infra == true)] | length | tostring)] | row),
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
,
"",
"## Pipeline arms (route.sh + foreman.sh, ESCALATE ends the run)",
"",
"`pipeline` = foreman.sh's default ladder; `pipeline-<name>` = the ladder in `bench/ladders/<name>`. Escalated runs are not re-run on Claude: \"then on Sonnet\" is the claude-sonnet arm's pass rate on that task, and its cost is the Claude spend the escalation would add. route.sh = its pick on the pipeline brief (one Jev call, 0 Claude tokens; the run goes to foreman whatever it picks). NAN tokens = all pi sessions of the run (attempts and 429 retries). Output cap = pi sessions whose last turn ended with stopReason `length`.",
"",
([$arms[] | select(startswith("pipeline"))] as $parms
 | def prow($rs): stats($rs) as $s
     | ([$rs[] | select(.escalated)] | length) as $esc
     | {n: ($rs | length), ok: ([$rs[] | select(.pass and (.escalated | not))] | length),
        fd: ([$rs[] | select((.pass | not) and (.escalated | not) and .protocol.final == "DONE")] | length),
        killed: ([$rs[] | select(.timed_out)] | length), esc: $esc,
        eff: ([$rs[] | .task as $t | if .escalated then (stats(runs($t; "claude-sonnet")).rate // 0) elif .pass then 1 else 0 end] | add // 0),
        escost: ([$rs[] | select(.escalated) | .task as $t | stats(runs($t; "claude-sonnet")) | if .n > 0 then .cost / .n else 0 end] | add // 0),
        wall: $s.wall, tokens: ([$rs[] | .tokens.total | values] | median), att: ([$rs[].pipeline.attempts // 0] | mean | r2),
        sess: ([$rs[].pipeline.sessions // [] | length] | add // 0), cap: ([$rs[].pipeline.output_cap // 0] | add // 0),
        recorded: ([$rs[] | select(.pipeline.sessions)] | length),
        route: ([$rs[].pipeline.route // empty | sub(" [0-9.]+ "; " ")] | group_by(.) | map("\(.[0]) ×\(length)") | join(", ")),
        ladder: ([$rs[].pipeline.ladder // "default" | values] | unique | join(" / "))};
   def pcells($p): ["\($p.n)", "\($p.ok)", "\($p.fd)", "\($p.killed)", "\($p.esc) (\($p.esc / $p.n | pct))",
       "\($p.eff | r2)/\($p.n) (\($p.eff / $p.n | pct))", "\($p.wall)", ($p.tokens | kilo), "\($p.att)",
       (if $p.recorded == 0 then "–" else "\($p.cap) of \($p.sess)" + (if $p.recorded < $p.n then " (\($p.recorded) runs recorded)" else "" end) end), ($p.escost | usd)];
   if ($parms | length) == 0 then empty else
   "### Side by side",
   "",
   "| arm | ladder | runs | DONE + hidden pass | DONE, hidden fail | killed at timeout | escalated | effective pass (escalations on Sonnet) | median s | median NAN tokens | attempts (mean) | output-cap sessions | Claude $ (escalations on Sonnet) |",
   "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
   ($parms[] as $a | [$all[] | select(.arm == $a)] as $rs | prow($rs) as $p | [$a, $p.ladder] + pcells($p) | row),
   "",
   "### Per task",
   "",
   "| task | arm | runs | DONE + hidden pass | DONE, hidden fail | killed at timeout | escalated | effective pass | median s | median NAN tokens | attempts (mean) | output-cap sessions | Claude $ | route.sh |",
   "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
   ($tasks[] as $t | $parms[] as $a | runs($t; $a) as $rs | select(($rs | length) > 0) | prow($rs) as $p | [$t, $a] + pcells($p) + [$p.route] | row),
   "",
   "### Output cap per attempt model",
   "",
   "| arm | model | pi sessions | ended on output cap | turns cut by the cap |",
   "|---|---|---|---|---|",
   ($parms[] as $a | [$all[] | select(.arm == $a) | .pipeline.sessions // [] | .[]] | group_by(.model)[]
     | [$a, (.[0].model // "?"), "\(length)", "\([.[] | select(.stop == "length")] | length)", "\([.[].output_cap_turns] | add)"] | row)
   end)
