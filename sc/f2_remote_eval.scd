if (~play.isNil or: { ~toPat.isNil } or: { ~enrich.isNil }) {
    "✗ REMOTE EVAL ABORT: DSL not loaded. ~play/~toPat/~enrich nil.".postln;
} {
    // §pat-gen the bookkeeping of a generation that is really gone. Every pooled
    // voice and every voice subgroup hangs off the pattern group, so when the
    // group goes they are all dead nodes: keeping them would have the next deploy
    // reuse a pool of corpses (the §reuse failure in f2dsl.scd — a flood of
    // «/n_mapn Node not found», and silence). It is defined FIRST because the
    // reload right below is one of the three places a generation ends, and it
    // ends it for real: /n_free on a group takes its children silently.
    ~f2PatGroupDrop = {
        topEnvironment[\f2Voices] !? { |v| v.clear };
        topEnvironment[\f2VGrp2] !? { |d| d.clear };
        topEnvironment[\f2VGroups] = nil;
    };
    // §pat-gen NEVER ASK A CLIENT-MADE NODE WHETHER IT IS PLAYING. Node:isPlaying
    // starts false and is only ever set by NodeWatcher, so the old guard here —
    // `if (~f2PatGroup.notNil and: { ~f2PatGroup.isPlaying })` — was false for
    // every group this file ever made and the reload freed nothing. Free by
    // nodeID with the error suppressed instead: the node may be gone (a reload
    // after CmdPeriod) and that is not worth a message.
    // The stamp is what tells the three cases apart, and only two of them act.
    // Same allocator: the group is ours and on this server — end it, then drop
    // what named its children. A DIFFERENT allocator: the server rebooted, so
    // those nodes are already gone AND the id now belongs to whatever the new
    // allocator has handed out — forget the generation, never free it (the rule
    // f2units §bus-gen states for a bus that outlived s.newBusAllocators). No
    // stamp at all: a group made by an engine that predates this file, on a
    // server that is still running — leave it exactly as it was, because its
    // voices are alive and the registries are the only way to reach them.
    ~f2PatGroup !? { |g|
        ~f2PatGroupAlloc !? { |a|
            if (a === s.nodeAllocator) {
                s.sendBundle(nil, [\error, 0], [\n_free, g.nodeID], [\error, 1]);
            };
            ~f2PatGroupDrop.value;
        };
    };
    // §pat-gen the group is REGISTERED now (see the drain below): a registered
    // group's isPlaying is the NodeWatcher's answer about the real node, which is
    // what tells a live group from one CmdPeriod took away. The allocator identity
    // and the creation stamp cover what the watcher cannot: a server reboot hands
    // out the same ids again, and a group whose /n_go has not landed yet is not
    // dead, it is young.
    ~f2PatGroup = Group.head(s.defaultGroup);
    ~f2PatGroup.register(true);
    ~f2PatGroupAlloc = s.nodeAllocator;
    ~f2PatGroupAt = Main.elapsedTime;
    "[f2re] ~f2PatGroup → node %".format(~f2PatGroup.nodeID).postln;

    // §layers/quant: DO NOT rewrite ~play — the DSL version already does all of it (group,
    // per-cell telemetry, melodic layers merged through Prout). Rewriting it here used to LOSE
    // the 5th argument, layers — melodySource died silently in remote mode. Keep the full
    // implementation once (guarded against a second eval of this file) and add only the scene
    // tag for /f2_branch.
    ~f2PlayDSL = ~f2PlayDSL ? ~play;
    ~play = { |key, data, dur=4, quant=4, layers|
        // §16-B: the current scene is the row's Pdef key; rand/wrand in ~toPat pick it up as
        // the sceneId for /f2_branch (the compiler may also put sceneId on the Event itself).
        topEnvironment[\f2Scene] = key;
        ~f2PlayDSL.value(key, data, dur, quant, layers);
    };

    if (~f2ContextPath.notNil) {
        "[f2re] context path: %".format(~f2ContextPath).postln;
        // Path already set, ~exportContext in f2dsl.scd uses ~f2ContextPath ?? default
    };

    ~f2Bridge = (busy: false, busyAt: 0);
    ~f2EvalQ = List.new;

    // §smooth-life THE SMOOTHERS DIE WITH THE PANIC AND NOBODY REBUILT THEM.
    // f2_modsmooth builds one \f2_msmooth synth per modulated key — VarLag from
    // the key's raw control bus onto its smoothed one, all of them in
    // ~f2SmGroup — and every consumer reads the SMOOTHED bus (~mbAt prefers
    // ~mbSm[k]). CmdPeriod frees every node on the server, so the group and all
    // of those synths are gone, while the client-side ~mbSyn/~mbSm dictionaries
    // go on holding the corpses — and ~f2FlagApply only ever builds a smoother
    // when ~mbSyn[k] is NIL, so it never rebuilt one. Measured live over the
    // real OSC paths: before the panic raw 0.25 / smoothed 0.25, then /f2_setb
    // 0.75 put both at 0.75; after CmdPeriod.run, /f2_setb 0.1 gave raw 0.1 and
    // smoothed 0.75 — every smoothed knob of the session frozen until the engine
    // was restarted, with nothing on the client to show for it (the server's own
    // log said «/n_set Node 1001 not found» and, for a key flagged afterwards,
    // «/s_new Group 1000 not found», leaving that key's smoothed bus at 0.0).
    // THE BUSES ARE KEPT AND ONLY THE NODES REBUILT: a §post static map
    // (f2dsl ~f2StaticMapAdd) is mapped ONCE onto ~mbSm[k].index, so reallocating
    // here would point every one of them at a stranger's bus.
    // AND THE REBUILT SEGMENT TAKES BACK THE KEY'S OWN LAG, not ~mbLag for
    // everybody. The core's flags are EDGE-TRIGGERED — conductor.go sends a
    // flag only when it differs from the last one it sent (rs.lastFlags,
    // fxLastFlags) and a channel gate's «smooth off» exactly ONCE per session
    // (gateFlagsSent) — so a key whose flag is 0 never hears about it again.
    // Rebuilding every segment at ~mbLag therefore does not cost one frame, it
    // costs the rest of the session: every gateSrc key (f2dsl §synth-mod maps
    // the voice's \gate onto ~mbAt of that key, which IS the smoothed bus once
    // the core's one flag 0 has built a segment for it) would come back from a
    // panic with a 1/60 s = 16.7 ms VarLag on a GATE instead of its 0.0002 s.
    // Hence ~mbFlagLast: the flag last applied per key, stamped where this file
    // already applies them (the /f2_frame handler, §9 below). A key that was
    // never flagged through a frame — the transitional /f2_setflags path, whose
    // OSCdef lives in f2_modsmooth.scd — is unknown here and keeps the old
    // behaviour, ~mbLag.
    ~mbFlagLast = ~mbFlagLast ? IdentityDictionary.new;
    ~f2SmoothRevive = {
        var sm = topEnvironment[\mbSm], syn = topEnvironment[\mbSyn];
        var rawAt = topEnvironment[\mbRawAt];
        var lastFl = topEnvironment[\mbFlagLast];
        topEnvironment[\f2SmoothDead] = false;
        if (sm.notNil and: { syn.notNil } and: { rawAt.notNil } and: { s.serverRunning }) {
            var g, n = 0;
            // the previous group first, by nodeID with the error suppressed: after a
            // panic it is already gone and that is not worth a message, but this file
            // adds a CmdPeriod hook on every reload, so a second hook would otherwise
            // build a second group over the first and leave one smoother per key
            // running with nobody holding it.
            topEnvironment[\f2SmGroup] !? { |old|
                s.sendBundle(nil, [\error, 0], [\n_free, old.nodeID], [\error, 1]);
            };
            g = Group.head(s.defaultGroup);
            g.register(true);
            topEnvironment[\f2SmGroup] = g;
            syn.clear;
            sm.keysValuesDo { |k, b|
                var raw = rawAt.value(k);
                if (b.notNil and: { raw.notNil }) {
                    var fl = (lastFl !? { |d| d[k] }) ? 1;      // unknown ⇒ smoothed, the old behaviour
                    syn.put(k, Synth(\f2_msmooth,
                        [\raw, raw.index, \out, b.index,
                         \lag, if (fl > 0.5) { topEnvironment[\mbLag] ? (1/60) } { 0.0002 }],
                        g));
                    n = n + 1;
                };
            };
            if (n > 0) { "[f2] % parameter smoothers rebuilt after the panic".format(n).postln };
        };
    };

    // §eval-drain v2 CmdPeriod (panic) clears the clocks and kills the drain routine WITHOUT
    // raising — busy stayed true forever, and every later /f2/eval from the core queued up
    // silently behind nobody: deploys never ran and the core reported «no /f2_ack for epoch N»
    // until a full restart. The hook resets busy itself.
    // §pat-gen a CmdPeriod frees every node on the server, so the pattern group,
    // its voice subgroups and every pooled voice are gone: say so here rather
    // than waiting for the watcher, and let the next deploy build a generation.
    CmdPeriod.add({ topEnvironment.use {
        ~f2Bridge.busy = false;
        ~f2PatGroup = nil;
        ~f2PatGroupDrop !? { |f| f.value };
        // §smooth-life the smoothers go with every other node, and the rebuild
        // CANNOT happen right here: CmdPeriod.run calls its hooks FIRST and
        // Server.freeAll (/g_freeAll, then initTree) only afterwards, so a group
        // made in this breath is freed a moment later. Arm it on the clock
        // instead — the clocks are cleared BEFORE the hooks run, so a schedule
        // made here survives — and mark it, so the next deploy retries the
        // rebuild if that one wake is ever lost.
        ~f2SmoothDead = true;
        SystemClock.sched(0.5, {
            topEnvironment.use { ~f2SmoothRevive !? { |f| f.value } };
            nil
        });
    } });

    OSCdef(\f2_eval, { |msg|
        var code = msg[1].asString;
        "[f2] /eval (% chars)".format(code.size).postln;
        topEnvironment.use {
            var stale;
            // §queue dense evals are QUEUED, not skipped: a skip silently lost the deploy that
            // arrived during a long interpret (a project's content boot loads a hundred
            // synthdefs over seconds) and the core waited for a /f2_ack that never came (§7.2
            // alert). One drain routine keeps arrival order; ~f2Bridge.busy = the drain is alive.
            ~f2EvalQ.add(code);
            if (~f2EvalQ.size > 1) { "[f2] eval queued (depth %)".format(~f2EvalQ.size).postln };
            // §eval-drain v2 a watchdog for ANY death of the routine the hook does not catch:
            // busyAt is stamped on every item; silence for >10s with a non-empty queue means the
            // drain is dead, so raise a new one. The interpreter is single-threaded, so there is
            // no race with a live drain: a long interpret simply defers this message's handling
            // until it finishes.
            stale = ~f2Bridge.busy and: { (Main.elapsedTime - (~f2Bridge.busyAt ? 0)) > 10 };
            if (stale) { "⚠ [f2] eval drain wedged — restarting it".postln; ~f2Bridge.busy = false };
            if (~f2Bridge.busy.not) {
                ~f2Bridge.busy = true;
                ~f2Bridge.busyAt = Main.elapsedTime;
                // §additive a deploy is ALWAYS bound to one scene (the row's Pdef key). The old
                // Pdef.all.stop + freeAll silenced EVERY parallel row on every eval — with two or
                // more scenes playing, starting one killed the rest, which is incompatible with
                // scene semantics and with the additive /f2_eval from bootstrap. Silencing
                // everything is what an explicit /f2/hush is for. The pattern group is created
                // lazily, if it does not exist yet.
                Routine({
                    topEnvironment.use {
                        // §pat-gen ONE PATTERN GROUP PER SESSION. This used to read
                        // `~f2PatGroup.isNil or: { ~f2PatGroup.isPlaying.not }`, and
                        // isPlaying is false for every group this file makes (it was
                        // never registered), so the branch fired on EVERY deploy: 41
                        // evals measured 41 groups on the server, one abandoned per
                        // deploy, plus one voice subgroup per playing pool — 17 nodes a
                        // deploy with 16 pools, which is ~480 deploys from
                        // s.options.maxNodes (8192, f2_boot.scd). Past that ceiling
                        // /g_new fails, every /s_new into the named group is rejected
                        // and sclang raises nothing: the app goes silent behind a green
                        // ack. Registered, the guard now fires only when the group is
                        // REALLY gone (CmdPeriod, a server reboot), and then the stale
                        // registries go first — freeing a group kills its children
                        // silently, and a pool of dead nodes is the §reuse failure in
                        // f2dsl.scd: a flood of «/n_mapn Node not found», and silence.
                        // §node-live and the other half of the same question: a group
                        // whose /g_new the server REFUSED (its parent gone, maxNodes
                        // reached) also reads isPlaying true for ever, because no /n_go
                        // and no /n_end will come — so this branch never fired, every
                        // deploy spawned into a group that does not exist, each refused
                        // voice was kept in its pool and mapped again on every event
                        // («/n_mapn Node N not found» once per parameter per event) and
                        // the app was silent behind a green ack. ~f2NodeLive (f2dsl)
                        // asks for the server's own confirmation once the node is past
                        // the grace; without f2dsl the old test stands.
                        if (~f2PatGroup.isNil
                            or: { ~f2PatGroupAlloc !== s.nodeAllocator }
                            or: { if (~f2NodeLive.notNil)
                                { ~f2NodeLive.(~f2PatGroup, ~f2PatGroupAt).not }
                                { ~f2PatGroup.isPlaying.not
                                    and: { (Main.elapsedTime - (~f2PatGroupAt ? 0)) > 1 } } }) {
                            ~f2PatGroupDrop !? { |f| f.value };
                            ~f2PatGroup = Group.head(s.defaultGroup);
                            ~f2PatGroup.register(true);
                            ~f2PatGroupAlloc = s.nodeAllocator;
                            ~f2PatGroupAt = Main.elapsedTime;
                            "[f2] patGroup recreated".postln;
                        };
                    };
                    0.05.wait;
                    while { topEnvironment.use { ~f2EvalQ.size > 0 } } {
                        var c;
                        topEnvironment.use {
                            c = ~f2EvalQ.removeAt(0);
                            ~f2Bridge.busyAt = Main.elapsedTime;   // §eval-drain v2 watchdog pulse
                        };
                        topEnvironment.use {
                            // §smooth-life the belt to the CmdPeriod hook's braces: if the
                            // scheduled rebuild never ran (a clock cleared under it, a server
                            // that was still down at 0.5 s), the next deploy does it — before
                            // the program, whose base-init writes values through those buses.
                            if (~f2SmoothDead == true) { ~f2SmoothRevive !? { |f| f.value } };
                            // §port-life the deploy bracket. The preamble ensures every port
                            // of the WHOLE session (the compiler walks all presets), so the
                            // names it did NOT stamp are ports the session no longer owns and
                            // the sweep at the end retires them — but only for a program that
                            // ensured at least one port, and only if it ran to the end: a
                            // half-interpreted deploy has named half its ports.
                            // §bus-ceil a pool that was dry during the LAST program may
                            // have room now (a smaller row, a server reboot): every program
                            // gets one honest attempt, and one line if it fails again.
                            ~f2ModBusRearm !? { |f| f.value };
                            ~f2PortDeployBegin !? { |f| f.value };
                            try { c.interpret; "✓ F2 eval ok".postln;
                                  ~f2PortDeployEnd !? { |f| f.value }; }
                                { |err| ("✗ F2 eval: " ++ err.errorString).postln };
                            ~f2Bridge.busyAt = Main.elapsedTime;
                        };
                        0.02.wait;   // a cooperative gap between queued evals
                    };
                    topEnvironment.use { ~f2Bridge.busy = false };
                }).play(TempoClock.default);
            };
        };
    }, '/f2/eval').permanent_(true);

    OSCdef(\f2_hush, { |msg|
        "[f2] /hush".postln;
        { topEnvironment.use { Pdef.all.do(_.stop);
            // §hush-free THE PANIC BUTTON FREED NOTHING. This was
            // `if (~f2PatGroup.notNil and: { ~f2PatGroup.isPlaying }) { freeAll }`
            // and isPlaying is a NodeWatcher guess that was false for this group
            // for the whole session (§pat-gen above): measured on a live server,
            // two gate-1 voices in the group survived /f2/hush and died the
            // instant freeAll was called by hand. So free by nodeID, error
            // suppressed — the group may already be gone and a panic must not
            // stop half way.
            ~f2PatGroup !? { |g| s.sendBundle(nil, [\error, 0], [\g_freeAll, g.nodeID], [\error, 1]) };
            // §hush-free and the POOLED voices, which is where they actually are:
            // ~play took the same dead isPlaying for an answer and spawned every
            // voice into s.defaultGroup, outside any freeAll of the pattern group.
            // The registry is the only route to those, and it is emptied — a hush
            // that left the pools behind would have the next deploy reuse a pool
            // of dead nodes (§reuse).
            ~f2Voices !? { |vs|
                vs.values.asArray.do { |pool|
                    (pool[\synths] ? []).do { |sy|
                        var nid = (sy.notNil and: { ~f2VNode.notNil }).if { ~f2VNode.(sy) };
                        nid !? { s.sendBundle(nil, [\error, 0], [\n_free, nid], [\error, 1]) };
                    };
                    pool[\post] !? { |p| ~f2FreePost !? { |f| f.value(p) } };
                };
                vs.clear;
            };
            // §scope-deck the decks (f2dsl §scope-deck) live OUTSIDE the pattern group, in
            // ~f2DeckGroup after it, so freeAll leaves them running: every deck of every row
            // goes with the voices (groups, buses, static maps, registry).
            ~f2FreeAllDecks !? { |f| f.value };
            // §loop-order freeAll killed the voice SUBGROUPS while patGroup was still alive, so
            // clear the subgroup dictionary or the next spawn would land after a dead node.
            ~f2VGroups = nil; ~f2VGrp2 !? { |d| d.clear };   // §loop-order v2 (the old key — migration)
            // §fix DO NOT free the ~mb buses: patterns of rows that were not redeployed hold
            // .asMap on specific bus indices, and free+realloc after a hush handed them someone
            // else's or a dead bus (every live parameter of the row drifted). The values simply
            // stay put; the next deploy rewrites them.
        } }.defer;
    }, '/f2/hush').permanent_(true);

    // ── ModEngine bridge (v2) ────────────────────────────────────────────────
    // v3: modulation values are written to per-key CONTROL BUSES (~mb); the event maps the
    //     synth argument onto the bus with .asMap (see the compiler) → the synth reads it at
    //     control rate CONTINUOUSLY → modulation moves EVEN a sounding note (Pdefn moved it only
    //     at the onset).
    ~mb   = ~mb ?? { IdentityDictionary.new };
    // CAREFUL: dict.put / dict[k]=v in SC returns THE DICTIONARY ITSELF, not the value. So the
    // bus is returned explicitly (otherwise ~mbAt.(k) hands back ~mb and .set/.asMap fail).
    ~mbAt = { |k|
        var b = ~mb[k];
        if (b.isNil) { b = Bus.control(s, 1); ~mb.put(k, b) };
        b
    };
    // DIAG: deploy's base-init pre-allocates a bus for every key it uses (via ~mbAt). So when
    // /f2_setb arrives with a key whose ~mb[k] is still nil, the engine is writing a bus the
    // DEPLOY never mapped — i.e. engine-key ≠ deploy-key (the "mismatch"). Log each such key
    // ONCE. On a clean SC boot ~mb starts empty, so deploy keys are present and only the mismatched
    // engine keys trip this. Compare a flagged key (e.g. ...__c4000320000) to the deploy's base-init
    // keys (e.g. ...__c320000) to read off the offset gap.
    // §parity the body is identical to the v7 handler in boot.rs (bootstrap_code): both write to
    // the ~mb buses, so the load order of the two files no longer changes /f2_setb semantics.
    // The warning fires once per key.
    ~f2SetbWarned = ~f2SetbWarned ? IdentitySet.new;
    OSCdef(\f2_setb, { |msg|
        topEnvironment.use {
            var i = 1, n = msg.size;
            while { i + 1 < n } {
                var k = msg[i].asSymbol, v = msg[i + 1];
                if (~mb[k].isNil and: { ~f2SetbWarned.includes(k).not }) {
                    ~f2SetbWarned.add(k);
                    ("⚠ [f2_setb] engine key with no deploy bus (engine≠deploy): " ++ k).postln;
                };
                // §nan-guard a NaN on the bus poisons the synth until the next write — skip it
                if (v.notNil and: { v.asFloat.isNaN.not }) { ~mbAt.(k).set(v) };
                i = i + 2;
            };
        };
    }, '/f2_setb').permanent_(true);

    // §v2-sc the SC-side variant player: deterministic rand/wrand choices come FROM THE ENGINE
    // (/f2_choice sceneKey nodeId iter idx) and are stored in ~f2Choice under the key
    // "<sceneKey>/<nodeId>/<iter>". ~toPat (rand/wrand tagged with v2Id) reads them on demand,
    // so SC plays exactly the variant the engine computed. The engine sends the choice for the
    // CURRENT and the NEXT iteration at every boundary (headroom for a whole-loop demand
    // lookahead); past iterations of a node are collected lazily right here.
    ~f2Choice = ~f2Choice ?? { Dictionary.new };
    ~f2ChoiceLog = 12;   // §diag log the first choices accepted (silence after that)
    OSCdef(\f2_choice, { |msg|
        topEnvironment.use {
            var scene = msg[1].asString, node = msg[2].asString,
                iter = msg[3].asInteger, idx = msg[4].asInteger;
            var base = scene ++ "/" ++ node ++ "/";
            ~f2Choice[(base ++ iter).asSymbol] = idx;
            ~f2Choice.removeAt((base ++ (iter - 2)).asSymbol);
            ~f2Choice.removeAt((base ++ (iter - 3)).asSymbol);
            if ((~f2ChoiceLog ? 0) > 0) {
                ~f2ChoiceLog = ~f2ChoiceLog - 1;
                ("[f2] choice← " ++ base ++ iter ++ " = " ++ idx).postln;
            };
        };
    }, '/f2_choice').permanent_(true);

    // OUT : /f2_phase cyclePhase beatAbs tempo → TS Transport (SC is master clock).
    //       Mirrors the /f2_cell telemetry NetAddr. cyclePhase is debug; TS uses beatAbs.
    //       ~f2CycleBeats (topEnvironment) = cycle length in beats (= dur); nil→4.
    ~f2PhaseAddr = ~f2PhaseAddr ?? { NetAddr("127.0.0.1", 57131) };
    // §16-B: the address of the BACKEND's OSC input (the new architecture). /f2_sync (the clock)
    // and /f2_branch (rand choices out of ~toPat) go here. Port = hub.scInPort (57121 by default).
    ~f2BackendAddr = ~f2BackendAddr ?? { NetAddr("127.0.0.1", (topEnvironment[\f2BackendPort] ? 57121)) };

    // §core the Go core (f2core) registers itself: it sends /f2/core_hello <port> from its own
    // socket, we remember the address, mirror /f2_sync there (the Tdef below), and the core's
    // deploy /f2_ack goes there too (the ack epilogue compiles `~f2CoreAddr ? ~f2BackendAddr ? …`).
    // The core's port is ephemeral — no static configuration; a repeat hello (a core restart)
    // simply overwrites the address.
    OSCdef(\f2_core_hello, { |msg, time, addr|
        topEnvironment.use {
            var port = (msg[1] ? addr.port).asInteger;
            ~f2CoreAddr = NetAddr(addr.ip, port);
            ~f2FrameSeq = -1;   // §9 a core restart resets the frame seq — start accepting again
            "[f2] core registered: %:%".format(addr.ip, port).postln;
        };
    }, '/f2/core_hello').permanent_(true);

    // §9 the core's frame protocol: /f2_frame proto seq beat flagsN [k,fl]… valsN [k,v]…
    // Application is atomic within the datagram, flags BEFORE values (the smoother's lag is
    // correct by the time the value arrives). seq is monotonic, so stale and duplicate frames
    // are dropped; a core restart is detected by /f2/core_hello (which resets ~f2FrameSeq). A
    // beat in the future (the core's lookahead, F2_SCHED_SEC) → schedAbs applies it EXACTLY on
    // the beat; otherwise immediately. Transitional: /f2_setb and /f2_setflags stay (Node A/B)
    // and go away at cutover.
    ~f2FrameSeq = ~f2FrameSeq ? -1;
    OSCdef(\f2_frame, { |msg|
        topEnvironment.use {
            var seq = msg[2].asInteger, beat = msg[3].asFloat;
            if (seq > (~f2FrameSeq ? -1)) {
                var i = 4, nf, nv, flags, vals, apply, clk = TempoClock.default;
                ~f2FrameSeq = seq;
                nf = msg[i].asInteger; i = i + 1;
                flags = Array.new(nf * 2);
                nf.do { flags.add(msg[i].asSymbol); flags.add(msg[i + 1]); i = i + 2 };
                nv = msg[i].asInteger; i = i + 1;
                vals = Array.new(nv * 2);
                nv.do { vals.add(msg[i].asSymbol); vals.add(msg[i + 1]); i = i + 2 };
                apply = {
                    topEnvironment.use {
                        if (~f2FlagApply.notNil) {
                            forBy(0, flags.size - 2, 2) { |j|
                                // §smooth-life the flag is recorded, not only applied: the core
                                // sends each one ONCE (edge-triggered, see ~f2SmoothRevive), so
                                // this record is the only place the lag of a key survives a panic.
                                ~mbFlagLast !? { |d| d.put(flags[j], flags[j + 1]) };
                                ~f2FlagApply.(flags[j], flags[j + 1]);
                            };
                        };
                        // values go to the RAW bus when modsmooth is loaded (its smoother draws
                        // the smooth one itself), otherwise to the plain ~mbAt (as /f2_setb does).
                        // §nan-guard a NaN is not written (it poisons the bus and the smoother).
                        forBy(0, vals.size - 2, 2) { |j|
                            var v = vals[j + 1];
                            if (v.notNil and: { v.asFloat.isNaN.not }) {
                                if (~mbRawAt.notNil) { ~mbRawAt.(vals[j]).set(v) } { ~mbAt.(vals[j]).set(v) };
                            };
                        };
                    };
                };
                if (beat > (clk.beats + 0.02)) { clk.schedAbs(beat, { apply.value; nil }) } { apply.value };
            };
        };
    }, '/f2_frame').permanent_(true);
    Tdef(\f2_phase, {
        var clock = TempoClock.default;
        loop {
            var beatAbs = clock.beats;
            var cb = (topEnvironment[\f2CycleBeats] ? 4).max(0.0001);
            ~f2PhaseAddr.sendMsg('/f2_phase',
                (beatAbs / cb).frac.asFloat, beatAbs.asFloat, clock.tempo.asFloat);
            // §6: the clock anchor for the backend — absolute beat + SC's wall time (seconds).
            // The backend extrapolates phase locally; serverTime is what lets it estimate tempo.
            ~f2BackendAddr.sendMsg('/f2_sync', beatAbs.asFloat, Main.elapsedTime.asFloat);
            // §core mirror the anchor into the Go core (if it registered with /f2/core_hello)
            if (~f2CoreAddr.notNil) {
                ~f2CoreAddr.sendMsg('/f2_sync', beatAbs.asFloat, Main.elapsedTime.asFloat);
            };
            // §tape global tempo bus (beats/sec): units with a \tempo control are
            // mapped onto it at spawn (see mkVoice) — smpBpm rate-scaling follows
            // live bpm changes with no respawn. Lazy alloc once the server is up.
            if (topEnvironment[\f2TempoBus].isNil and: { Server.default.serverRunning }) {
                topEnvironment[\f2TempoBus] = Bus.control(Server.default, 1);
            };
            topEnvironment[\f2TempoBus] !? { |b| b.set(clock.tempo) };
            (1/60).wait;
        };
    }).play(TempoClock.default);
    "[f2] ModEngine bridge: /f2_setb in (:%), /f2_phase out (:57131)"
        .format(NetAddr.langPort).postln;

    "".postln;
    "╔═══════════════════════════════════════╗".postln;
    "║  F2 Remote Eval v5 ACTIVE             ║".postln;
    "║  patGroup: node %".format(~f2PatGroup.nodeID).postln;
    "║  rack bus: %".format(if(~rack.notNil and:{~rack.bus.notNil and:{~rack.bus.main.notNil}}){~rack.bus.main.index}{"?"}).postln;
    "║  defs:% mods:% pal:%".format(~defs.size, ~mod.size, ~pal.size).postln;
    "╚═══════════════════════════════════════╝".postln;
};
