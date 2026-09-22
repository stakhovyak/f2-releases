(
// §voice — THE VOICE ALLOCATOR, MODEL AGAINST ENGINE. Sixth of the live family.
//
// WHY THIS FILE EXISTS. The second rung of §voice (docs/design/SCALE.md §11) gives a
// parameter driven at preset scope one bus per (preset, param, VOICE) instead of one per
// cell, and that needs the ENGINE to know the voice — before the event, not after. Today the
// voice is chosen here, in sclang, and chosen by the WALL CLOCK: `nowT = Main.elapsedTime`
// against the per-slot `offAt` array and the per-slot `lane` array, which is client state the
// score does not contain. So moving the allocator into Go would change which voice a note
// gets in exactly the cases that depend on timing — a steal, a release tail, a `rand` branch
// — and that is audible.
//
// The decision was: measure before moving. `core/voicealloc` is a Go model of the pick in
// `sc/f2dsl.scd` — mono, the hold continuation through `endingV`, the round robin, the
// free-slot scan, §steal-x — and this file replays the SAME event sequence through the REAL
// event type on a live server and compares the slots. A divergence is then NAMED, with the
// case, the event, both slots and both timings, rather than found by ear later.
//
// The plan is a fixture written by Go (`core/voicealloc/seq_test.go` →
// `sc/nrt/testdata/allocseq.json`): each case carries its pool config, its events and the
// slots THE MODEL chose. Regenerate with
// `F2_WRITE_FIXTURES=1 go test ./voicealloc/ -run TestPlanFixture`.
//
// WHAT IS COMPARED, and why the slot is enough. The slot is read from `pool[\hidx]`, which
// `\f2voice` writes for every articulation at the moment of the pick. Everything else the
// pick decides — §steal-x, the hold continuation, the gate-off end — is a function of the
// slot and of the same inputs both sides already agree on (time, lane, dur), so a matching
// slot on a matching input is a matching decision.
//
// WHAT IT DELIBERATELY AVOIDS, because the model cannot express it and says so: a cfgSig
// change (which retires the pool and can hand §hold-retire a contIdx from the OLD one) and
// freeing the pool mid-sequence. Each case gets its own pool (its own f2def) so no state
// leaks between them.
//
// A RESPAWNED VOICE was on that list and is not any more — it is a case now (`respawn`,
// `wantRespawn` in the plan). The pick reads rr, offAt and lane, and none of them knows
// whether the slot's node is still alive; the corpse is found and rebuilt AFTER the slot has
// been chosen. So the death of a node, which the score can never know about, turns out not to
// move the slot at all. The case checks both halves: the slot the model predicted, and —
// through `pool[\bornAt]` — that a voice really was respawned, so it cannot quietly decay
// into one more round-robin case.
//
// The tempo is slow on purpose. The continuation window is 0.08 beat before the gate-off, and
// at one second to the beat that is 80 ms, which the language's scheduler does not hit
// reliably — live-voices.scd carries the same note and the same remedy. Here the beat is four
// seconds, so the window is 320 ms and every event is placed in the middle of one.
//
//   scsynth -u 57436 -a 16384 -b 4096 -l 1 -i 0 -o 2 &
//   F2_LIVE_PORT=57436 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-alloc.scd
//
// It renders nothing and prints its own verdict.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
var logPath = ("F2_NRT_OUT".getenv ? "/tmp") +/+ "live-alloc.log";
var logLine = { |str|
	var f = File(logPath, "a");
	if (f.isOpen) { f.write(str ++ "\n"); f.close };
	str.postln;
};
var say = { |ok, what, val|
	logLine.("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(14) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" });
	if (ok.not) { fails = fails + 1 };
};
var plan = File(scDir +/+ "nrt/testdata/allocseq.json", "r").readAllString.parseYAML;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
Routine({
	var tries = 0, beatDur, note, poolOf, mismatches = 0, totalEvents = 0;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		logLine.("✗ no scsynth answering on port % — start one first (see the header)".format(port));
		1.0.wait; 0.exit;
	} {
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;
		File.delete(logPath);
		logLine.("=== the voice allocator: core/voicealloc against the engine, port " ++ port ++ " ===");
		topEnvironment.use {
			thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
			srv.sync; 1.0.wait;
			(scDir +/+ "f2dsl.scd").load.value(scDir);
			1.0.wait;
			(scDir +/+ "f2_remote_eval.scd").load;
			1.0.wait;
		};
		beatDur = plan["beatDur"].asFloat;
		TempoClock.default.tempo = 1 / beatDur;
		topEnvironment.use { ~f2DebugHold = nil };

		// the same probe convention as live-voices.scd: \out \gate \amp \i_free plus an
		// envelope, so the event type takes exactly the road a real unit takes
		SynthDef(\f2allocProbe, { |out = 0, gate = 0, t_trig = 0, amp = 0.02, i_free = 2, freq = 220|
			var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.8, 0.3, 1, -4), gate, doneAction: i_free);
			Out.ar(out, SinOsc.ar(freq, 0, amp) * env ! 2);
		}).add;
		// the same graph WITHOUT an \i_free control, for the `respawn` case. A def that HAS one
		// is spawned by the pool with i_free 0 (f2dsl.scd:1948) and then lives for ever, so there
		// is nothing to rebuild; a def without one frees itself when its release ends, and the
		// pool has to find the corpse and replace it. That is how a respawn is made to HAPPEN —
		// the first draft of the case used the ordinary probe and the check reported 0 respawns.
		SynthDef(\f2allocProbeFree, { |out = 0, gate = 0, t_trig = 0, amp = 0.02, freq = 220|
			var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.8, 0.3, 1, -4), gate, doneAction: 2);
			Out.ar(out, SinOsc.ar(freq, 0, amp) * env ! 2);
		}).add;
		srv.sync; 0.5.wait;

		note = { |def, nv, artic, lane, cid, durB, selfFree = false|
			var ev = (type: \f2voice, f2def: def,
				instrument: if (selfFree) { \f2allocProbeFree } { \f2allocProbe },
				f2hasFree: selfFree.not,
				f2cfg: (voices: nv, artic: artic), f2scene: \f2alloc, f2_cid: cid,
				dur: durB, sustain: durB * 0.9, legato: 0.85, amp: 0.02, freq: 220, out: 0);
			// §lane the compiler emits f2lane only for a NON-EMPTY lane, so an empty one in
			// the plan means the key is absent — nil on this side, which is what the model's
			// empty string stands for
			if (lane.notNil and: { lane.size > 0 }) { ev[\f2lane] = lane.asSymbol };
			ev.play;
		};
		poolOf = { |def|
			var key = ("f2alloc|" ++ def.asString ++ "@"
				++ topEnvironment.use { ~f2PatGroup.nodeID }.asString).asSymbol;
			topEnvironment.use { (~f2Voices ? IdentityDictionary.new)[key] };
		};

		say.(topEnvironment.use { ~f2PatGroup.notNil and: { ~f2Voices.notNil } },
			"the engine came up with a pattern group and a registry",
			topEnvironment.use { ~f2PatGroup !? { |g| g.nodeID } });
		say.(plan["cases"].size > 0, "the plan carries cases", plan["cases"].size);

		plan["cases"].do { |c|
			var def = c["def"].asSymbol;
			var nv = c["spec"]["voices"].asInteger;
			var artic = c["spec"]["artic"].asSymbol;
			var t0 = Main.elapsedTime;
			var got = [], late = [], bad = 0, respawns = 0;
			// a case that wants a respawn needs a probe the pool does NOT keep alive
			var selfFree = c["selfFree"].notNil;
			c["events"].do { |e, i|
				var at = e["at"].asFloat;
				var dt = (t0 + at) - Main.elapsedTime;
				var pool, bornBefore;
				if (dt > 0) { dt.wait };
				late = late.add(((Main.elapsedTime - t0) - at).round(0.001));
				// the WHOLE bornAt array, because which slot the event will take is exactly what
				// is not known yet; an entry that moved across the event IS the respawn
				bornBefore = poolOf.(def) !? { |pp| (pp[\bornAt] ? []).copy };
				note.(def, nv, artic, e["lane"], 1000 + i, e["dur"].asFloat, selfFree);
				pool = poolOf.(def);
				if (bornBefore.notNil and: { (pool[\bornAt] ? []) != bornBefore }) {
					respawns = respawns + 1;
				};
				got = got.add(if (pool.isNil) { -1 } { pool[\hidx] ? -1 });
			};
			c["want"].do { |w, i|
				var want = w["idx"].asInteger;
				totalEvents = totalEvents + 1;
				if (got[i] != want) {
					bad = bad + 1;
					mismatches = mismatches + 1;
					logLine.("    ### case % event %: engine slot %, model slot % "
						"(planned t=%, late by % s)".format(
							c["name"], i, got[i], want,
							c["events"][i]["at"], late[i]));
				};
			};
			say.(bad == 0, "case " ++ c["name"] ++ ": " ++ got.asString, c["why"]);
			// the case that CLAIMS a respawn must have had one, or it is silently just another
			// round-robin case and proves nothing about a dead node
			if (c["wantRespawn"].notNil) {
				say.(respawns > 0, "case " ++ c["name"] ++ ": a dead voice was rebuilt",
					"" ++ respawns ++ " respawns");
			};
			// a fresh pool for the next case; the pools of this one are left to release
			0.6.wait;
		};

		say.(mismatches == 0,
			"every event picked the same slot on both sides",
			"" ++ (totalEvents - mismatches) ++ "/" ++ totalEvents);
		if (mismatches > 0) {
			logLine.("  NOTE: a mismatch with a large `late by` is the HARNESS drifting, not the");
			logLine.("  rules diverging — the model was given the PLANNED times. Re-run; if the");
			logLine.("  same event mismatches with a small lateness, the rules really differ.");
		};

		srv.sendMsg("/g_freeAll", 0);
		logLine.("=== live-alloc checks failed: " ++ fails ++ " ===");
		logLine.("=== live-alloc " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===");
		1.0.wait;
		0.exit;
	};
}).play(AppClock);
)
