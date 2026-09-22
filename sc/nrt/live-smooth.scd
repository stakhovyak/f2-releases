(
// §smooth-life — THE PARAMETER SMOOTHERS ACROSS A PANIC, against a running
// scsynth. Sixth of the live family (live-banks.scd, live-ptrs.scd,
// live-hush.scd, live-decks.scd, live-voices.scd are the others) and, like
// them, it has to be live for one reason: every claim here is about a VALUE
// SITTING ON A SERVER BUS, and the only honest way to read that is the
// server's own answer to /c_get. A client-side `Bus:getSynchronous` is not
// available for a remote server at all, and `~mbSyn[k].notNil` — the thing the
// engine itself used as its "is there a smoother" test — is a client-side
// object that stays exactly as truthful after the node under it is gone. An
// NRT score has no CmdPeriod, no OSCdef receiving over a socket and no bus to
// ask, so none of this can be checked offline.
//
// What it pins:
//
//   §A  THE SMOOTHED BUS FOLLOWS THE RAW ONE. f2_modsmooth builds one
//       \f2_msmooth synth per modulated key — VarLag from the key's raw
//       control bus onto its smoothed one — and every consumer reads the
//       smoothed bus (~mbAt prefers ~mbSm[k]). So a value written through the
//       real /f2_setb path has to arrive on BOTH buses.
//
//   §B  AND IT STILL FOLLOWS AFTER A PANIC. CmdPeriod frees every node on the
//       server, which takes ~f2SmGroup and every smoother in it, while the
//       client-side ~mbSyn/~mbSm dictionaries are left holding the corpses.
//       Nothing in sc/ used to touch them: the only CmdPeriod hook in the
//       engine (f2_remote_eval.scd §eval-drain) swept the pattern-group
//       registries and no more. Measured on a live server before the fix, over
//       the real OSC paths: `before the panic raw 0.25 / smoothed 0.25`, after
//       `/f2_setb 0.75` both 0.75, then CmdPeriod.run and `/f2_setb 0.1` gave
//       `raw 0.10000000149012, smoothed 0.75` — the smoothed bus frozen at the
//       last value the dead VarLag ever wrote. The server's log for the same
//       run said `FAILURE IN SERVER /n_set Node 1001 not found`. Since ~mbSyn[k]
//       was not nil the smoother was never rebuilt, so EVERY smoothed knob of
//       the session stopped moving until the engine was restarted, with no
//       error anywhere on the client. That is the assertion below: write a new
//       value after the panic and the SMOOTHED bus must carry it.
//
//   §C  A KEY FLAGGED FOR THE FIRST TIME AFTER THE PANIC GETS A LIVE SMOOTHER.
//       ~f2SmGroup was created once, at load, and held forever, so after a
//       panic the group was a dead nodeID and every later /s_new into it was
//       refused by the server (`/s_new Group 1000 not found`) while the client
//       cheerfully filed the Synth object. Measured before the fix:
//       `new key: raw 0.60000002384186, smoothed 0.0`.
//
//   §D  AND THE SMOOTHED BUS KEEPS ITS INDEX. The revival must not reallocate
//       the buses: a post card, a deck param or any other §post static map is
//       mapped ONCE onto ~mbSm[k].index (f2dsl §post, ~f2StaticMapAdd), and the
//       next deploy re-maps from ~mbAt — both would be reading a stranger's bus
//       if the index moved under them.
//
//   §E  TWICE IN A ROW. A second panic is not a special case; the revival has
//       to survive being needed again.
//
//   §F  AND THE WAKE THAT NEVER ARRIVES. The rebuild cannot happen inside the
//       CmdPeriod hook — CmdPeriod.run calls its hooks first and
//       Server.freeAll/initTree only afterwards (SystemActions.sc:42-53), so a
//       group made in that breath is freed a moment later — and is armed on
//       SystemClock instead. That is ONE scheduled wake, on a clock the next
//       panic or a server reboot clears. So the engine also marks the
//       smoothers dead and the eval drain rebuilds them before the program if
//       the mark is still up. Nothing had ever run that line: here the wake is
//       dropped on purpose and a real /f2/eval is asked to do the rebuild.
//
//   §G  AND THE REBUILD KEEPS EACH KEY'S OWN LAG. The core's flags are
//       EDGE-TRIGGERED — conductor.go sends a flag only when it differs from
//       the last one it sent, and a channel gate's "smooth off" exactly once
//       per session — so a key whose flag is 0 is never told again. A revival
//       that hands every segment ~mbLag therefore does not cost one frame, it
//       costs the rest of the session, and a gateSrc key carries a VOICE GATE
//       (f2dsl §synth-mod maps \gate onto ~mbAt of that key, which is the
//       smoothed bus as soon as the core's single flag 0 has built a segment
//       for it): it would come back from a panic slewed by 1/60 s = 16.7 ms
//       instead of its 0.0002 s. Driven through the real /f2_frame path, with
//       ~mbLag widened to two seconds so the difference is a fact.
//
//   scsynth -u 57611 -a 16384 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   F2_LIVE_PORT=57611 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-smooth.scd
//
// It renders nothing and prints its own verdict. `-l 1` is not optional and
// each run wants a server of its own, for the reason live-banks.scd and
// live-hush.scd both give: a killed sclang holds its login for a moment and the
// next run is answered with "could not register, too many users".
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
// THE LOG IS A FILE, not the post window — the reason live-voices.scd gives:
// sclang buffers postln into a pipe and loses the buffer when the process is
// killed, and a run that hangs half way is exactly when the trace is wanted.
var logPath = ("F2_NRT_OUT".getenv ? "/tmp") +/+ "live-smooth.log";
var logLine = { |str|
	var f = File(logPath, "a");
	if (f.isOpen) { f.write(str ++ "\n"); f.close };
	str.postln;
};
var say = { |ok, what, val|
	logLine.("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(18) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" });
	if (ok.not) { fails = fails + 1 };
};
// THE SERVER'S OWN ANSWER for a control bus: /c_get index → /c_set index value.
// Not Bus:get (its reply goes through the same client machinery this file is
// trying not to trust) and not Bus:getSynchronous (local servers only).
var cget = { |idx|
	var c = Condition.new, res = nil, resp;
	if (idx.isNil) { nil } {
		resp = OSCFunc({ |msg| res = msg[2].asFloat; c.unhang }, '/c_set', srv.addr).oneShot;
		srv.sendMsg("/c_get", idx.asInteger);
		SystemClock.sched(4, { if (res.isNil) { resp.free; c.unhang }; nil });
		c.hang;
		res
	};
};
// THE SERVER'S OWN ANSWER for the node tree (the reader live-hush.scd uses):
// /g_queryTree with flag 0 replies [flag, rootID, nChildren, (id, nChildren |
// id, -1, defName)…] depth first; this flattens it to the list of node ids.
var tree = {
	var c = Condition.new, res = nil, resp;
	resp = OSCFunc({ |msg|
		var i = 4, ids = [], par = IdentityDictionary.new, walk;
		walk = { |n, pid|
			n.do {
				var id = msg[i].asInteger, nc = msg[i + 1].asInteger;
				i = i + 2;
				ids = ids.add(id); par[id] = pid;
				if (nc < 0) { i = i + 1 } { walk.value(nc, id) };
			};
		};
		walk.value(msg[3].asInteger, msg[2].asInteger);
		res = (ids: ids, par: par);
		c.unhang;
	}, '/g_queryTree.reply', srv.addr).oneShot;
	srv.sendMsg("/g_queryTree", 0, 0);
	SystemClock.sched(4, { if (res.isNil) { resp.free; c.unhang }; nil });
	c.hang;
	res ? (ids: [], par: IdentityDictionary.new)
};
var answer = { |f| var out = nil; try { out = f.value } { |e| out = nil }; out };
var near = { |a, b| a.notNil and: { (a - b).abs < 0.01 } };
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
Routine({
	var tries = 0, me, k1 = 'f2smProbeA', k2 = 'f2smProbeB', k3 = 'f2smProbeC';
	var k4 = 'f2smProbeD', k5 = 'f2smProbeE';
	var rawIx, smIx, smIx2, rawIx2, smIx4, smIx5, grp0, grp1, t;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		logLine.("✗ no scsynth answering on port % — start one first (see the header)".format(port));
		1.0.wait; 0.exit;
	} {
		// this server outlives any one sclang, and a fresh sclang restarts node
		// numbering at the beginning: wipe what an earlier run left behind
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;

		File.delete(logPath);
		logLine.("=== the parameter smoothers across a panic, LIVE server on port " ++ port ++ " ===");
		topEnvironment.use {
			thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
			srv.sync; 1.0.wait;
			(scDir +/+ "f2dsl.scd").load.value(scDir);
			1.0.wait;
			(scDir +/+ "f2_remote_eval.scd").load;
			1.0.wait;
			// the overlay, strictly after remote_eval — the load order f2_boot.scd uses
			(scDir +/+ "f2_modsmooth.scd").load;
			1.0.wait;
		};
		srv.sync; 0.5.wait;
		// every write below goes over the socket, exactly as the core sends it
		me = NetAddr("127.0.0.1", NetAddr.langPort);

		say.(answer.({ topEnvironment.use { ~f2FlagApply.notNil } }) == true,
			"the modsmooth overlay is loaded", nil);

		// ── §A the smoothed bus follows the raw one ───────────────────────────
		// the flag is what CREATES the smoother (lazily, modulated keys only)
		me.sendMsg('/f2_setflags', k1, 1);
		0.5.wait;
		rawIx = answer.({ topEnvironment.use { ~mbRaw[k1] !? { |b| b.index } } });
		smIx  = answer.({ topEnvironment.use { ~mbSm[k1]  !? { |b| b.index } } });
		grp0  = answer.({ topEnvironment.use { ~f2SmGroup !? { |g| g.nodeID } } });
		say.(rawIx.notNil and: { smIx.notNil }, "the key got a raw and a smoothed bus", [rawIx, smIx]);
		say.(answer.({ topEnvironment.use { ~mbAt.(k1).index } }) == smIx,
			"~mbAt hands consumers the SMOOTHED bus", answer.({ topEnvironment.use { ~mbAt.(k1).index } }));
		t = tree.value;
		say.(grp0.notNil and: { t[\ids].includes(grp0) }, "the smoother group is on the server", grp0);

		me.sendMsg('/f2_setb', k1, 0.25);
		0.5.wait;
		say.(near.(cget.(rawIx), 0.25), "raw bus carries 0.25", cget.(rawIx));
		say.(near.(cget.(smIx), 0.25), "smoothed bus carries 0.25", cget.(smIx));
		me.sendMsg('/f2_setb', k1, 0.75);
		0.5.wait;
		say.(near.(cget.(rawIx), 0.75), "raw bus carries 0.75", cget.(rawIx));
		say.(near.(cget.(smIx), 0.75), "smoothed bus follows to 0.75", cget.(smIx));

		// ── §B and it still follows after a panic ─────────────────────────────
		// the real thing: CmdPeriod.run clears the clocks, runs every hook and
		// then frees every node on the server
		CmdPeriod.run;
		2.5.wait;
		me.sendMsg('/f2_setb', k1, 0.1);
		0.8.wait;
		say.(near.(cget.(rawIx), 0.1), "after the panic the raw bus still takes a value", cget.(rawIx));
		say.(near.(cget.(smIx), 0.1),
			"and the SMOOTHED bus follows it (frozen at 0.75 before the fix)", cget.(smIx));

		// ── §D the smoothed bus kept its index ────────────────────────────────
		say.(answer.({ topEnvironment.use { ~mbSm[k1] !? { |b| b.index } } }) == smIx,
			"the smoothed bus kept its index across the panic",
			answer.({ topEnvironment.use { ~mbSm[k1] !? { |b| b.index } } }));
		say.(answer.({ topEnvironment.use { ~mbRaw[k1] !? { |b| b.index } } }) == rawIx,
			"and so did the raw one",
			answer.({ topEnvironment.use { ~mbRaw[k1] !? { |b| b.index } } }));

		// ── §C a key first flagged AFTER the panic ────────────────────────────
		me.sendMsg('/f2_setflags', k2, 1);
		0.5.wait;
		me.sendMsg('/f2_setb', k2, 0.6);
		0.8.wait;
		rawIx2 = answer.({ topEnvironment.use { ~mbRaw[k2] !? { |b| b.index } } });
		smIx2  = answer.({ topEnvironment.use { ~mbSm[k2]  !? { |b| b.index } } });
		say.(near.(cget.(rawIx2), 0.6), "a NEW key's raw bus carries 0.6", cget.(rawIx2));
		say.(near.(cget.(smIx2), 0.6),
			"and its smoother really ran (0.0 before the fix)", cget.(smIx2));
		grp1 = answer.({ topEnvironment.use { ~f2SmGroup !? { |g| g.nodeID } } });
		t = tree.value;
		say.(grp1.notNil and: { t[\ids].includes(grp1) },
			"the smoother group the engine holds is a LIVE node", grp1);
		say.(t[\par][answer.({ topEnvironment.use { ~mbSyn[k1] !? { |n| n.nodeID } } })] == grp1,
			"and the revived smoother of the first key sits in it",
			answer.({ topEnvironment.use { ~mbSyn[k1] !? { |n| n.nodeID } } }));

		// ── §E twice in a row ─────────────────────────────────────────────────
		CmdPeriod.run;
		2.5.wait;
		me.sendMsg('/f2_setflags', k3, 1);
		0.5.wait;
		me.sendMsg('/f2_setb', k1, 0.42);
		me.sendMsg('/f2_setb', k3, 0.31);
		0.8.wait;
		say.(near.(cget.(smIx), 0.42), "after a SECOND panic the old key follows again", cget.(smIx));
		say.(near.(cget.(answer.({ topEnvironment.use { ~mbSm[k3] !? { |b| b.index } } })), 0.31),
			"and a key flagged after it smooths too",
			cget.(answer.({ topEnvironment.use { ~mbSm[k3] !? { |b| b.index } } })));

		// ── §F the wake that never arrives ──────────────────────────────────
		// The rebuild cannot run inside the CmdPeriod hook (the hooks go first
		// and Server.freeAll only afterwards, SystemActions.sc:42-53), so it is
		// armed on SystemClock — and that is ONE scheduled wake, on a clock any
		// later panic or reboot clears. The engine's answer is a flag the next
		// deploy reads. That line had never been executed by anything: this
		// section loses the wake on purpose (SystemClock.clear, exactly what
		// CmdPeriod.run itself does to the clocks) and then asks a real
		// /f2/eval over the socket to do the rebuild instead.
		CmdPeriod.run;
		SystemClock.clear;                            // the armed revival goes with it
		2.5.wait;
		me.sendMsg('/f2_setb', k1, 0.55);
		0.8.wait;
		say.(near.(cget.(rawIx), 0.55), "with the wake lost the raw bus still moves", cget.(rawIx));
		say.(near.(cget.(smIx), 0.42),
			"and the smoothed one is frozen — nothing has rebuilt it yet", cget.(smIx));
		say.(answer.({ topEnvironment.use { ~f2SmoothDead } }) == true,
			"the engine knows its smoothers are dead",
			answer.({ topEnvironment.use { ~f2SmoothDead } }));
		// the retry: a real /f2/eval over the socket, exactly as the core sends one
		me.sendMsg('/f2/eval', "~f2SmProbeEvals = (~f2SmProbeEvals ? 0) + 1;");
		1.5.wait;
		say.(answer.({ topEnvironment.use { ~f2SmProbeEvals ? 0 } }) == 1,
			"the deploy really ran", answer.({ topEnvironment.use { ~f2SmProbeEvals ? 0 } }));
		me.sendMsg('/f2_setb', k1, 0.66);
		0.8.wait;
		say.(near.(cget.(smIx), 0.66),
			"and it rebuilt the smoothers on its way in", cget.(smIx));
		say.(answer.({ topEnvironment.use { ~f2SmoothDead } }) == false,
			"the flag is down again, so the next deploy does no work",
			answer.({ topEnvironment.use { ~f2SmoothDead } }));

		// ── §G the flag the rebuild must not forget ───────────────────────
		// The core's flags are EDGE-TRIGGERED: conductor.go sends one only when it
		// differs from the last it sent, and a channel gate's «smooth off» exactly
		// once per session. So a rebuild that gives every segment ~mbLag does not
		// cost one frame, it costs the session — and a gateSrc key carries a
		// VOICE GATE (f2dsl §synth-mod maps \gate onto ~mbAt of that key), which
		// would come back from a panic slewed by 1/60 s instead of its 0.0002.
		// ~mbLag is widened to two seconds first so the difference is a fact and
		// not a race: at 0.0002 the value is there within one control block, at 2 s
		// it has barely started. Both keys are driven through the REAL frame path
		// (/f2_frame proto seq beat flagsN [k,fl]… valsN [k,v]…), flag 0 for the
		// gate-like key and flag 1 for the control.
		topEnvironment.use { ~mbLag = 2.0 };
		me.sendMsg('/f2_frame', 1, 1, 0.0, 2, k4, 0, k5, 1, 2, k4, 0.2, k5, 0.2);
		3.0.wait;
		smIx4 = answer.({ topEnvironment.use { ~mbSm[k4] !? { |b| b.index } } });
		smIx5 = answer.({ topEnvironment.use { ~mbSm[k5] !? { |b| b.index } } });
		say.(near.(cget.(smIx4), 0.2), "the unsmoothed key is at 0.2", cget.(smIx4));
		say.(near.(cget.(smIx5), 0.2), "and so is the smoothed one", cget.(smIx5));
		CmdPeriod.run;
		2.5.wait;
		// exactly what the core sends next: VALUES, and no flags at all
		me.sendMsg('/f2_frame', 1, 2, 0.0, 0, 2, k4, 0.8, k5, 0.8);
		0.4.wait;
		say.(near.(cget.(smIx4), 0.8),
			"after the panic the unsmoothed key is still unsmoothed", cget.(smIx4));
		say.(answer.({ var v = cget.(smIx5); v.notNil and: { v < 0.5 } }) == true,
			"while the smoothed one is still on its way — the probe tells them apart",
			cget.(smIx5));

		srv.sendMsg("/g_freeAll", 0);
		logLine.("=== live-smooth checks failed: " ++ fails ++ " ===");
		logLine.("=== live-smooth " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===");
		1.0.wait;
		0.exit;
	};
}).play(AppClock);
)
