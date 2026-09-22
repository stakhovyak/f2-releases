// f2units.scd — §synth-mod: the built-in modular synth units and their ports.
//
// Concept: sc/SYNTH-MODULES.md. A module is a PRESET whose instrument is a unit:
// cells, voices/artic (reatk/legato/hold), win/win-tail and the modulators all come
// from the preset for free; the unit only has to keep to the convention:
//   • the controls \out \gate \t_trig \amp \i_free (+ env atk/dec/sus/rel/curve);
//   • a gated envelope WITHOUT doneAction:2 (the \f2voice pool owns its life);
//   • re-attack is t_trig (a Trig is added to gate);
//   • everything into a port or the out goes through LeakDC → Sanitize (a NaN is
//     not passed on to the neighbours);
//   • port inputs are InFeedback (cycles are legal at the price of one block of
//     delay), an unconnected input is index −1 → the signal is muted by the
//     multiplier (idx >= 0);
//   • §cards every PROCESSOR also declares `chainIn = -1` — the strip's stage
//     bus, read with In.ar (same cycle, no delay: its writers sit earlier in
//     the voice group) and SUMMED into the unit's primary port (carIn / srcIn /
//     exIn) before ~f2CondIn; -1 = not in a strip (silent term). Secondary
//     ports (modIn, kerIn, trigIn) stay external ports.
//   • §cards PASS-THROUGH: inside a strip (chainIn >= 0) a processor is an
//     insert effect (user decision: like FX in Bitwig) — its own ADSR must NOT
//     shape the stream, the source cards' envelopes already did. Every
//     processor keeps its EnvGen (with doneAction i_free — port/stack/legacy
//     use is unchanged) and right after it selects
//       `var env = Select.kr(chainIn >= 0, [envG, 1]);`
//     (stutU treats its dry-path gate `open` the same way); the SendReply
//     gating may use the selected env.
//   • §cards OUTPUT NODE: the bare preset `amp` is the PRESET level, applied
//     by \f2chainOut — a tiny gain node \f2voice spawns LAST in the strip's
//     voice group after the final stage; each card's own level is `id.amp`.
//     \f2chainOut declares gate/t_trig/freq so the group broadcasts stay
//     harmless.
//   • Units with structural menus register a GENERATOR in ~f2UnitGen;
//     ~f2UnitDef builds/caches the SynthDef variant `unit__k_v__…` (see
//     §cards registry below).
//   • §poly polysynthU (docs/design/POLYSYNTH.md) is the first generator
//     unit: saw wavetable bank ~f2PolyTables (12 mip levels, allocated at
//     load), opts v1 / v2 = unison lanes per oscillator, menu + knob schema
//     ~f2UnitOpts / ~f2UnitSpecs exported as ctx.unitOpts / ctx.unitSpecs.
//   • §smp samplerU (docs/design/SAMPLER.md) is the second one: one signed
//     phase engine (window / loops / freeze / cell re-anchor) feeding one of
//     the five play modes — Repitch, Cycles, Textures, Spectral and Fragments,
//     all built. Its `sample` opt is a RESOURCE opt (~f2UnitOptsRes): no graph
//     variant, \f2voice resolves it to `buf` at spawn, with the four §6
//     analysis buffers beside it. Grain window bank ~f2SmpWins (16 morph
//     windows); Spectral's own artefacts are ~f2SmpFftNull (an analysis of
//     silence per `qual`, which a voice reads while its file's own is still
//     being recorded) and the per-file ~f2SmpFftBufAt / ~f2SmpOnsetBufAt.
//   • §pm polymerU (docs/design/POLYMER.md) is the third: three slot menus
//     (osc / filt / env) choose the whole oscillator, the whole filter and the
//     whole envelope, so a variant builds ONE of each and every variant
//     declares the same 77 live controls (§1.9 + the §flt union). Eight of the
//     nine oscillators, all eleven filters and six of the seven envelopes are
//     built; `scrawl` and `segments` need the curve editor (§6.8) and fall back
//     with one warning each. The sub, the two crossfades, `pm` and `subSync`
//     are fixed hardware and sit on every variant (§1.3). `curve` is a RESOURCE
//     opt, as samplerU's `sample` is.
//   • §flt the FILTER slot and the FEG are ONE block on polysynthU and
//     polymerU (~f2FltSlot / ~f2Feg, the union of both contracts): the model
//     is the structural opt `filt` on both cards — `poly` (Polysynth's own
//     core) and `ld` are built, the nine other Bitwig models are FILTER.md §3 — and
//     the cutoff bus feeding the slot stays each unit's own law.
//
// PORTS (§4 of the concept, polyphony as «clone the graph per voice»):
//   ~f2Ports[\name] = (bus: Bus.audio(s, 32), wv: writing voices 1..16)
//   voice k's slot is the stereo pair bus.index + 2k;
//   writer k writes slot (k % 16); reader k reads slot (k % wv) — the pairs
//   carrier[k] ⇄ mod[k] are deterministic, and a hold stick keeps them stable.
//   ~f2PortEnsure is called by the compiler (the deploy preamble, wv = the writer's
//   voices); the lazy ~f2PortAt covers a reader that spawns early (wv defaults to 16).
(
topEnvironment.use {

// §port-sum reboot / hot swap: earlier entries point at buses from BEFORE
// s.newBusAllocators (dead or someone else's indices) — so the registry is cleared and
// the old commit nodes silenced; the deploy recreates the ports fresh (the voices
// respawn from the deploy preamble anyway). §bus-gen AND THE BUSES, not only the commit
// nodes. A port holds two of them, 32 channels each (W and R: 16 stereo pairs), and the
// registry was thrown away right here — without a .free those 64 channels went nowhere on EVERY
// reload of f2units, not only the first. They are freed under the allocator stamp (see
// ~f2StackBusRel in f2dsl): an entry that outlived a server reboot points at indices from
// a previous life, and handing those to the new allocator would be a gift of someone else's
// live block — such an entry is simply forgotten.
(~f2Ports ? IdentityDictionary.new).do { |e|
	e[\commit] !? { |c| try { c.free } };
	if (e[\alloc] === s.audioBusAllocator) {
		e[\rbus] !? { |b| if (b !== e[\bus]) { try { b.free } } };
		e[\bus]  !? { |b| try { b.free } };
	};
};
~f2Ports = IdentityDictionary.new;
// §port-life and the entries already RETIRED but not yet freed (the park list of
// ~f2PortRetire): a reload throws the registry away, and a parked entry is off
// that registry already, so without this its 64 channels would be the one leak
// the rest of this block exists to stop. The scheduled drain that would have
// freed them is dropped with the list — it only ever frees what is still in it.
(~f2PortsParked ? []).do { |e|
	e[\commit] !? { |c| try { c.free } };
	if (e[\alloc] === s.audioBusAllocator) {
		e[\rbus] !? { |b| if (b !== e[\bus]) { try { b.free } } };
		e[\bus]  !? { |b| try { b.free } };
	};
};
~f2PortsParked = [];

// ── §sc-deps THE OPTIONAL EXTENSION PACK, REACHED BY NAME ─────────────────
//
// Four of the UGens this file plays are not in SuperCollider's core class
// library: `SVF` (the Blackrain state-variable filter, four of the eleven
// filter models) and `PV_RecordBuf` / `PV_BufRd` / `PV_XFade` (the sampler's
// spectral mode). They ship in sc3-plugins, which the owner of a machine may
// or may not have installed.
//
// WHY THEY ARE NOT NAMED LITERALLY. sclang resolves a class name at COMPILE
// time, not when the branch runs. A literal `SVF.ar(…)` inside a graph nobody builds
// still costs the WHOLE FILE: without the pack this file raised thirteen
// "Class not defined" errors and compiled to nil, so the engine had no units
// at all — not one synth, not one processor — while the runtime capability
// check below sat there promising a graceful fallback it could never deliver.
// A runtime `if` cannot guard a compile-time reference. A name can: a symbol
// is data, `asClass` answers nil when the class is absent, and the file
// compiles on a stock install either way.
//
// WHAT DEGRADES WITHOUT THE PACK: the four filter models that need `SVF` are
// dropped from ~f2FltBuilt (a card that asks for one is told once and gets
// the unit's default model, the ~f2FltResolve path that already exists for a
// value with no arm), and the sampler's spectral mode falls back to Warp1
// (~f2SmpPV, below). Everything else is core and plays as it always did.
//
// THE CHECK THAT KEEPS IT TRUE: sc/nrt/extdeps.scd fails if any class named
// literally in sc/*.scd is outside the core library of the SuperCollider that
// runs it, and the front's own suite pins the same thing against the
// committed list sc/nrt/core-classes.txt — so a new literal `SVF.ar` cannot
// walk back in unnoticed.
~f2ExtNeeds = (
	svf: #[\SVF],                                    // filter models sk / svf / fizz / ripple
	pv:  #[\PV_RecordBuf, \PV_BufRd, \PV_XFade]       // the sampler's spectral analysis and playback
);
// The models each capability carries. Read by the ~f2FltBuilt filter below and
// by the offline check, so a fifth model reaching for SVF is one line here.
~f2ExtFltModels = (svf: #[\sk, \svf, \fizz, \ripple]);
~f2ExtHas = { |cap| (topEnvironment[\f2ExtNeeds][cap.asSymbol] ? #[]).every { |k| k.asClass.notNil } };
~f2ExtMissing = ~f2ExtNeeds.keys.asArray.sort.select { |cap| ~f2ExtHas.(cap).not };
// The call itself: `~f2Ext.(\SVF, \ar, [args])`. performList and not a literal
// — that is the whole point — and an Error rather than silence if it is ever
// reached without the class, which cannot happen while the capability gates
// above hold: a build failure is caught by ~f2UnitDef and falls back to the
// base def with a warning, whereas a silent substitution would be a filter
// nobody picked.
~f2Ext = { |name, sel, args|
	var cls = name.asClass;
	if (cls.isNil) {
		Error("~f2Ext: % is not installed (sc3-plugins) — this graph must not have been built; "
			"~f2ExtHas / ~f2FltBuilt are what decide that".format(name)).throw;
	};
	cls.performList(sel, args)
};
// The two spellings the sites need, so a call site reads like the UGen it is.
~f2Svf = { |...args| topEnvironment[\f2Ext].(\SVF, \ar, args) };
~f2PvRecordBuf = { |...args| topEnvironment[\f2Ext].(\PV_RecordBuf, \new, args) };
~f2PvBufRd = { |...args| topEnvironment[\f2Ext].(\PV_BufRd, \new, args) };
~f2PvXFade = { |...args| topEnvironment[\f2Ext].(\PV_XFade, \new, args) };
if (~f2ExtMissing.size > 0) {
	("⚠ [f2 deps] sc3-plugins capabilities missing: % — the engine loads, and what they carry does not: %".format(
		~f2ExtMissing,
		~f2ExtMissing.collect { |cap|
			(topEnvironment[\f2ExtNeeds][cap]).asString ++ if (cap == \svf) { " (filter models sk svf fizz ripple)" } { " (sampler spectral → Warp1)" }
		})).postln;
};
// §cards/§stack the STAGE / route bus registry (~f2StackBusAt in f2dsl) is
// reset the same way: its buses were allocated before s.newBusAllocators too,
// so a stale entry could overlap a fresh port bus. Every pool respawns on its
// first trigger after this load (~f2UnitsVer in the fingerprint) and
// re-allocates its stage bus.
// §bus-gen the allocator stamp (see ~f2StackBusRel in f2dsl): an entry that outlived a
// server reboot must not be freed — its index already belongs to someone else.
(~f2StackBus ? IdentityDictionary.new).do { |e|
	if (e[\alloc].isNil or: { e[\alloc] === s.audioBusAllocator }) {
		e[\bus] !? { |b| try { b.free } };
	};
};
~f2StackBus = IdentityDictionary.new;

// IMPORTANT (the dynamic ~ scope): these functions are called both from deploy evals and
// from Event:play (\f2voice mkVoice), where currentEnvironment is THE EVENT ITSELF — a
// bare ~reference there quietly yields nil (nil.value(...) → nil, and then e[\bus] fails).
// So the bodies never touch ~: the registry and the neighbouring functions are reached
// through topEnvironment explicitly (the same rule as top.use in \f2voice).
// §port-sum THE PORT IS DOUBLE-BUFFERED. scsynth bus semantics: the first Out.ar of a
// cycle OVERWRITES the bus (lazy clearing), and a reader's InFeedback sees the PARTIAL
// sum as of its own position in the node tree. With several writers on one slot the
// reader heard only those EARLIER than it in the tree — «the loudest one survives, the
// rest vanish» — and the picture jumped on every redeploy, because the order changed.
// Now: writers → the W bus; a commit node at the TAIL of the tree carries the cycle's
// FULL sum W→R (ReplaceOut); readers read R (InFeedback = the previous cycle's full sum,
// INDEPENDENT of node order). Every cross-module loop gets exactly one block of delay —
// uniformly and reproducibly.
// IMPORTANT: commit does not only copy W→R, it also ZEROES W. Without that the bus holds
// the last block once the writers fall silent (a rest, voices freed on a deploy, a voice
// not born yet) — and commit would drive that block into R FOREVER: readers would get a
// frozen signal instead of silence («the sound sticks»).
SynthDef(\f2portCommit, { |w = 0, r = 0|
	var sig = In.ar(w, 32);
	ReplaceOut.ar(r, sig);
	ReplaceOut.ar(w, DC.ar(0) ! 32);
}).add;
// §port-sum THE EMERGENCY SWITCH: `~f2PortSum = false;` + a redeploy → readers read W
// directly again (the old behaviour, node order matters again).
~f2PortSum = ~f2PortSum ? true;
~f2PortCommitG = {
	var g = topEnvironment[\f2PortCG];
	// §node-live (f2dsl ~f2NodeLive) isPlaying alone also believed a group whose
	// /g_new the server refused — it reads true for ever, the commit node was
	// never rebuilt and every port stayed silent. Without f2dsl the old test
	// stands, which is the behaviour this file had on its own.
	var live = topEnvironment[\f2NodeLive];
	var ok = if (live.notNil) { live.(g, topEnvironment[\f2PortCGAt]) } { g.notNil and: { g.isPlaying } };
	if (ok.not) {
		g = Group.tail(s.defaultGroup);
		g.register(true);
		topEnvironment[\f2PortCG] = g;
		topEnvironment[\f2PortCGAt] = Main.elapsedTime;
	};
	g
};
// §port-life THE NAME THAT STOPS BEING DEPLOYED. The compiler walks the WHOLE
// session's preset list and emits one `~f2PortEnsure.(\name, wv);` per port on
// EVERY deploy of EVERY row (src/lib/compiler.ts §synth-mod, core/compiler
// mirror), so the names in one deploy preamble ARE the ports the session still
// owns. Nothing ever removed the others: renaming a port ten times left ten
// entries, and each entry holds two 32-channel buses (W and R) plus a commit
// node. Measured live: a fresh 32-channel bus landed at index 6 with an empty
// registry, at 646 after ten names, and three further deploys naming only the
// tenth left all ten entries and the watermark exactly where it was — 64
// channels of s.options.numAudioBusChannels (16384, f2_boot.scd) gone per
// rename for the rest of the session. Past that ceiling ~f2PortEnsure's own
// §port-nil path bypasses the port and the audio simply stops arriving.
// So a deploy is now BRACKETED (~f2PortDeployBegin / ~f2PortDeployEnd, called
// by the eval drain in f2_remote_eval.scd): every ensure stamps the epoch, and
// at the end of the deploy the entries that were not stamped are retired.
// TWO RULES KEEP THAT SAFE. (a) The sweep runs only for a deploy that ensured
// at least ONE port — /f2/eval also carries a project's content boot, a hundred
// SynthDefs naming no port at all, and reading that as «the session has no
// ports any more» would free every live port in the middle of a set. (b) The
// buses are PARKED, not freed on the spot: a voice of the removed preset may
// still be playing out its release into that W bus, and handing the index to
// the next allocation under it is the fault live-decks.scd measures at 0.4345
// of someone else's signal. Same shape as ~f2StackBusRetire in f2dsl (§bus-park,
// §park-eps): each entry carries its own due time on Main.elapsedTime, any later
// retirement drains whatever has matured, and the drain re-arms itself while
// anything is still parked — so one lost wake costs nothing.
~f2PortsParked = ~f2PortsParked ? [];
~f2PortEpoch = ~f2PortEpoch ? 0;
~f2PortTouched = false;
// §bus-gen freeing a port entry, under the allocator stamp: an entry that
// outlived s.newBusAllocators points at indices from a previous life and
// handing those back to the new allocator would be a gift of someone else's
// live block — such an entry is forgotten, not freed. The commit node goes with
// the buses, not before them: while the pair is parked it still carries W→R for
// whatever is releasing into it.
~f2PortRel = { |e|
	if (e.notNil) {
		e[\commit] !? { |c| try { c.free } };
		e[\commit] = nil;
		if (e[\alloc] === s.audioBusAllocator) {
			e[\rbus] !? { |b| if (b !== e[\bus]) { try { b.free } } };
			e[\bus]  !? { |b| try { b.free } };
		};
		e[\bus] = nil; e[\rbus] = nil;
	};
};
~f2PortRetire = { |e, delay = 0.5|
	var drain;
	if (e.notNil) {
		e[\due] = Main.elapsedTime + delay;
		topEnvironment[\f2PortsParked] = (topEnvironment[\f2PortsParked] ? []).add(e);
	};
	drain = {
		var now = Main.elapsedTime, keep = [];
		(topEnvironment[\f2PortsParked] ? []).do { |o|
			// §park-eps the 0.01 tolerance and the re-arm are f2dsl's, for f2dsl's
			// reason: the due time is PHYSICAL while the wake lands at the calling
			// thread's LOGICAL seconds, and a caller inside `c.interpret` of a whole
			// deploy program lags by however long that interpret took.
			if ((o[\due] ? 0) <= (now + 0.01)) {
				topEnvironment[\f2PortRel].value(o);
			} {
				keep = keep.add(o);
			};
		};
		topEnvironment[\f2PortsParked] = keep;
		if (keep.size > 0) {
			SystemClock.sched((keep.collect { |o| o[\due] ? 0 }.minItem - now).max(0.01), drain);
		};
		nil
	};
	SystemClock.sched(delay, drain);
};
~f2PortDeployBegin = {
	topEnvironment[\f2PortEpoch] = (topEnvironment[\f2PortEpoch] ? 0) + 1;
	topEnvironment[\f2PortTouched] = false;
};
~f2PortDeployEnd = {
	var dict = topEnvironment[\f2Ports];
	var epoch = topEnvironment[\f2PortEpoch] ? 0;
	// §bus-park «after the voices, plus a tenth» — the same denominator
	// ~f2StackBusAfterBeats gives the stage buses, because the voices that read
	// this port are freed on the same two clocks.
	var delay = (topEnvironment[\f2StackBusAfterBeats] !? { |f| f.value(0.4) }) ? 0.5;
	if (dict.notNil and: { topEnvironment[\f2PortTouched] == true }) {
		dict.keys.asArray.do { |k|
			var e = dict[k];
			if (e.notNil and: { (e[\seen] ? -1) != epoch }) {
				("[f2 port] % retired — no deploy names it any more".format(k)).postln;
				dict.removeAt(k);
				topEnvironment[\f2PortRetire].value(e, delay);
			};
		};
	};
	topEnvironment[\f2PortTouched] = false;
};
~f2PortEnsure = { |name, writerV = 16|
	var dict = topEnvironment[\f2Ports];
	var key = name.asSymbol;
	var e = dict[key];
	// §bus-gen an entry that outlived s.newBusAllocators (a server reboot with sclang still
	// alive) holds indices from the previous life: using them is writing into a stranger's
	// bus, silently. Forget it whole and build it again; freeing it is out for the same reason.
	if (e.notNil and: { e[\alloc] !== s.audioBusAllocator }) {
		("⚠ [f2 port] % outlived a server reboot — its buses are reallocated".format(key)).postln;
		dict.removeAt(key);
		e = nil;
	};
	// §port-nil AN EMPTY — OR MERELY FRAGMENTED — ALLOCATOR RETURNS NIL, and this
	// used to write the nil entry into ~f2Ports and then read `.index` off it two
	// lines down: «Message 'index' not understood», raised out of the MIDDLE of
	// the deploy program, which the compiler emits as one parenthesised
	// expression — so ~f2FreeSceneVoices, ~f2DeckSync and ~play never ran, the
	// row's old voices kept their gates and the row never started. Worse, the
	// wreck stayed cached and the reuse branch only ever retried `rbus`, so every
	// later deploy of EVERY row threw at the same line for the rest of the
	// session (the port preamble is built over all the presets). Measured: with
	// the 32-channel class starved, ~f2StackBusAt (8 ch) and ~f2DeckBuild (4 ch)
	// both still allocated happily — so this does not need an exhausted pool,
	// only a fragmented one. Refuse the way those two already refuse: say it out
	// loud, cache nothing, return nil.
	if (e.isNil) {
		var b = Bus.audio(s, 32), rb = Bus.audio(s, 32);
		if (b.isNil or: { rb.isNil }) {
			b !? { |x| x.free }; rb !? { |x| x.free };
			("✗ f2: cannot allocate a port bus (32 ch) for % — the server's audio bus pool is exhausted; raise s.options.numAudioBusChannels and reboot the server. The port is bypassed.").format(key).postln;
		} {
			e = (bus: b, rbus: rb, wv: writerV.asInteger.clip(1, 16),
				alloc: s.audioBusAllocator);
			dict[key] = e;
		};
	} {
		e[\wv] = writerV.asInteger.clip(1, 16);
		// §port-nil the W bus is retried here too. Only `rbus` ever was, so an
		// entry that had lost its W stayed broken for the session.
		if (e[\bus].isNil) { e[\bus] = Bus.audio(s, 32) };
		if (e[\rbus].isNil) { e[\rbus] = Bus.audio(s, 32) };
		if (e[\bus].isNil or: { e[\rbus].isNil }) {
			// The half-entry STAYS, and so does whichever bus it still holds:
			// a live W bus has voices writing it, and handing that index back to
			// the allocator under them is the §deck-retire fault in another
			// place. Refuse for now; the next deploy retries both halves and the
			// port comes back whole the moment the pool does.
			e = nil;
			("✗ f2: cannot re-allocate the port bus (32 ch) for % — the server's audio bus pool is exhausted; raise s.options.numAudioBusChannels and reboot the server. The port is bypassed.").format(key).postln;
		};
	};
	if (e.isNil) { nil } {
		// §port-life the stamp the sweep reads: this name was named by THIS deploy,
		// and this deploy named at least one port (so the sweep may run at all).
		e[\seen] = topEnvironment[\f2PortEpoch] ? 0;
		topEnvironment[\f2PortTouched] = true;
		// §port-sum the commit node is recreated ON EVERY DEPLOY, unconditionally: if the node
		// died (a server reboot, CmdPeriod, someone else's freeAll) R would freeze forever —
		// readers silent or holding the last block, and the only «fix» was a reboot. A deploy now
		// always restores the path. Two nodes per port is cheap.
		e[\commit] !? { |c| try { c.free } };
		e[\commit] = nil;
		if (topEnvironment[\f2PortSum] == false) {
			// the switch: readers go back to W (the old behaviour). Otherwise the previous R bus
			// lost its last reference right here — 32 channels per toggle.
			e[\rbus] !? { |b| if (b !== e[\bus]) { try { b.free } } };
			e[\rbus] = e[\bus];
		} {
			// §port-nil back from switched-off, and the re-allocation can fail too:
			// keep R on W rather than on nil, which is the old behaviour and not
			// silence (the same fallback ~f2PortInSlot takes).
			if (e[\rbus] === e[\bus]) { e[\rbus] = Bus.audio(s, 32) ? e[\bus] };
			e[\commit] = Synth(\f2portCommit,
				[\w, e[\bus].index, \r, e[\rbus].index],
				topEnvironment[\f2PortCommitG].value, \addToTail);
			e[\commit].register(true);
		};
		("[f2 port] % w=% r=% wv=% commit=%".format(key, e[\bus].index,
			e[\rbus].index, e[\wv], e[\commit].notNil)).postln;
		e
	}
};

// a reader that spawns before the writer's deploy preamble: the port is ensured with
// the default wv (16, the ceiling — every reader voice gets its own pair); the writer's
// deploy then sets the real wv, and the reader's fingerprint (§port-wv in f2dsl) respawns it.
~f2PortAt = { |name|
	topEnvironment[\f2Ports][name.asSymbol] ?? {
		topEnvironment[\f2PortEnsure].value(name, 16)
	}
};

// the WRITER's slot: voice k → stereo pair k % 16 (the W bus)
// §port-nil NIL when the port has no bus (the allocator refused it above). These
// two are called from inside a voice spawn, so `.index` of nil killed the note
// as well as the deploy; the callers in f2dsl read a nil slot as «no port on
// this input/output» and keep the direct out.
~f2PortOutSlot = { |name, vi = 0|
	var e = topEnvironment[\f2PortAt].value(name);
	if (e.notNil and: { e[\bus].notNil }) {
		e[\bus].index + (2 * (vi.asInteger % 16))
	} { nil }
};

// the READER's slot: voice k → stereo pair k % wv on the R BUS (§port-sum: the previous
// cycle's full sum through commit — independent of node order). The fallback to W is an
// old boot without commit (degrade to the previous behaviour, not to silence).
~f2PortInSlot = { |name, vi = 0|
	var e = topEnvironment[\f2PortAt].value(name);
	var b = e !? { e[\rbus] ? e[\bus] };
	if (b.notNil) {
		b.index + (2 * (vi.asInteger % ((e[\wv] ? 16).max(1))))
	} { nil }
};

// §loop-cond THE LOOP CONDITIONER on a port input: gain → OnePole(damp) → tanh saturation
// (sat — dry/wet). It stabilises feedback recursion: inGain <1 damps regeneration (the loop
// decays instead of exploding), inDamp kills the highs in the loop (which is where the
// aliased screech of FM feedback collects), inSat gives a soft amplitude ceiling (so the
// chaos stays musical). The defaults are TRANSPARENT (1/0/0 → y = x byte for byte): existing
// saves do not change. One triple of knobs per unit, acting on ALL of its port inputs; the
// knobs are modulatable like any parameter (the ~mbAt buses), so a modulator can drive the
// regeneration itself.
~f2CondIn = { |sig, gain = 1, damp = 0, sat = 0|
	var y = OnePole.ar(sig * gain, damp.clip(0, 0.97));
	(y * (1 - sat)) + (y.tanh * sat)
};

// §cards STAGE INPUT of a processor card. A strip voice is one Group with one
// Synth per card in strip order; a stage is a private stereo bus slot that the
// cards BEFORE this one have already written this cycle (Out.ar sums — layers).
// In.ar therefore returns the same-cycle sum of every earlier node: no block
// delay (unlike the InFeedback port inputs, which exist for legal loops — a
// strip has none). idx = -1 (not in a strip, or a synth card) reads bus 0 but
// is muted by the (idx >= 0) factor, so the term is exactly zero. Each
// processor sums this into its primary port before ~f2CondIn.
~f2ChainIn = { |idx| In.ar(idx.max(0), 2) * (idx >= 0) };

// §cards OUTPUT NODE of a strip voice (spawned LAST in the voice group by
// \f2voice mkVoice): reads the FINAL stage slot (private, like every other
// stage) and writes the preset's resolved out scaled by the PRESET level — the
// bare `amp` of a strip preset (each card's own level is `id.amp`). The 5 ms
// lag keeps amp mods click-free. gate / t_trig / freq are declared only so the
// voice-group broadcasts (n_set / n_map on the group) stay harmless.
SynthDef(\f2chainOut, { |in = 0, out = 0, amp = 1, gate = 1, t_trig = 0, freq = 440|
	Out.ar(out, In.ar(in, 2) * amp.lag(0.005));
}).add;

// §unit-eq A BASIC THREE-BAND EQ on the output of EVERY non-oscillator unit.
// Why: processors, resonators and noises collect rubbish at both edges of the spectrum (the
// rumble of port loops at the bottom, the aliased screech of a folder or shifter at the top)
// — and until now the only cure was an external fx on a bus, i.e. a node and a bus of their
// own just to «take the bottom out». The split is COMPLEMENTARY: mid = input − low − high, so
// at 1/1/1 the bands add back up to the INPUT (to within a few ULP of the addition — nothing
// audible changes and existing saves sound as they sounded), and the crossovers have neither
// a dip nor a bump, as three independent filters would.
//   eqLo/eqMid/eqHi — band gains 0..4 (0 = the band is cut, 1 = as it was);
//   eqLoF/eqHiF     — the split points; eqHiF is always held above eqLoF (otherwise the
//                     bands overlap and the middle goes negative).
// The knobs are modulatable like any parameter (the ~mbAt buses): eqHi under an LFO is a
// wah, eqLo at 0 on a cell is a high-pass played as rhythm.
~f2Eq3 = { |sig, lo = 1, mid = 1, hi = 1, loF = 200, hiF = 3000|
	var fL = loF.clip(30, 2000);
	var fH = hiF.clip(500, 16000).max(fL * 1.5);
	var b1 = LPF.ar(sig, fL);
	var b3 = HPF.ar(sig, fH);
	var b2 = sig - b1 - b3;
	(b1 * lo.clip(0, 4)) + (b2 * mid.clip(0, 4)) + (b3 * hi.clip(0, 4))
};

// §units-ver monotonically bumped on every shipped change to the unit defs.
// f2dsl mixes it into the voice-pool fingerprint (|u): after a units reload,
// pools rebuilt on the first trigger — no node keeps playing a STALE def
// (replaced the file, but old voices still sound like the old build).
~f2UnitsVer = 50;

// ── §cards: legacy sources + SynthDef VARIANT registry ────────────────────
// Sound-source units retired from the card menus (Polysynth / Polymer /
// Sampler take their place). Their defs stay loaded so old saves keep
// sounding; the UI hides them (mirror of LEGACY_UNITS in src/lib/chain.ts).
// grainU is NOT legacy: it stays a first-class «Tape» card (tape motor /
// slicer workflow — no Sampler counterpart yet).
~f2LegacyUnits = #[\fmOscU, \pmOscU, \chaosU, \stochU, \noiseU, \subU, \padU, \chipU, \harmU];

// ── §cut units removed OUTRIGHT in v49 ────────────────────────────────────
// LEGACY and CUT are opposite decisions. A legacy def stays loaded and an old
// save keeps sounding; a cut def is gone, and a save that used one CANNOT
// play. The failure mode we refuse is the silent one: \f2voice skips a card it
// has no SynthDef for, the stage that card was to write is never written, and
// every card after it reads an empty bus — so the preset goes quiet from that
// point on and the strip LOOKS like it is merely bypassed. One line per
// (preset × unit), naming the unit, the preset and where the work goes now, is
// the difference between «this save is from before the cut» and an evening
// spent hunting a dead bus. The value is the successor a card is rebuilt on.
//   amU     → vocU: both take carIn × modIn, both let one signal shape another.
//   envcaU  → none: it was an ADSR-as-VCA on a foreign source, and no survivor
//             reproduces it; tranU on the same source is the nearest honest
//             rewrite (transient gain rather than a gate, but it is a level
//             shaper driven by this preset's cells).
//   onsetU  → scatU: trigIn + threshold detects the same hits and fires grains
//             off them. NOT covered: onsetU was the only live unit that
//             published a TRIGGER on /f2_chan (`SendReply` of Trig.kr, not env),
//             which is what `gateSrc sc:<preset>` gated other modules from.
//             scatU's detector publishes nothing — that recipe is gone with it.
~f2UnitsCut = (
	amU:    "vocU (carIn × modIn — the same two-input family)",
	envcaU: "tranU on the same source (an ADSR-as-VCA has no direct successor)",
	onsetU: "scatU (trigIn + threshold; its sc:<preset> trigger telemetry is gone)"
);
// The one line every resolver posts, ONCE per (preset × unit). `preset` and
// `where` come from the caller because only \f2voice knows which preset and
// which card asked — ~f2UnitDef sees a bare symbol.
~f2UnitGoneMsg = { |unit, preset, where|
	var cut = (topEnvironment[\f2UnitsCut] ? ())[unit.asSymbol];
	var who = (preset ? "?").asString ++ (where !? { |w| " card " ++ w.asString } ? "");
	if (cut.notNil) {
		"⚠ [f2 unit] % asks for %, CUT in f2units v% — it will NOT play. Rebuild the card on %; everything the card fed is silent until you do.".format(
			who, unit, (topEnvironment[\f2UnitsVer] ? 0), cut)
	} {
		"⚠ [f2 unit] % asks for % — no SynthDef of that name is loaded (units file out of date, or a build that failed?). The card is skipped and everything it fed is silent.".format(
			who, unit)
	}
};
// Post it once per (preset × unit), through the units file's own warn-once set
// so a strip that retriggers at 120 bpm says it a single time.
~f2UnitGone = { |unit, preset, where|
	topEnvironment[\f2UnitWarnOnce].value(
		("unitgone_" ++ (preset ? "?").asString ++ "_" ++ unit.asString).asSymbol,
		topEnvironment[\f2UnitGoneMsg].value(unit, preset, where));
	nil
};

// Structural menus of a card (UnitCard.opts: oscillator shape, filter model,
// sampler mode, unison count…) select a SynthDef VARIANT instead of a live
// Select.ar over every alternative. A unit with menus registers a GENERATOR:
//   ~f2UnitGen[\polysynthU] = { |opts, name| SynthDef(name, { … }) };
// opts is the Event / Dictionary from cfg (symbol keys, symbol values, e.g.
// (mode: 'so_ft', q: '2p')); `name` is the variant name the registry expects
// back. Every variant MUST declare the same control set as the base unit
// (unused args are simply ignored) — the card's knobs stay stable, and the
// base def's SynthDesc stands in for the union when a variant is absent.
// Generators survive a units reload (`?`); the build cache does NOT (a reload
// rebuilds every variant once with the fresh generator — the same reason
// ~f2UnitsVer respawns the pools). Bodies read the registry via
// topEnvironment: they are called from Event:play (\f2voice) too.
~f2UnitGen = ~f2UnitGen ? IdentityDictionary.new;
// Build cache: variant name → the def name SynthDescLib holds for it (normally
// the same symbol; a generator may name its def differently — a variant is
// resolved through this map FIRST, so a name mismatch never rebuilds it on
// every event), \building while a build is in flight (the base def sounds
// meanwhile), \failed when the generator raised or returned no SynthDef
// (warned once, not retried until the next f2units load).
~f2UnitBuilt = IdentityDictionary.new;
~f2UnitWarned = IdentitySet.new;          // one warning per (unit/variant) key
~f2UnitWarnOnce = { |key, msg|
	var seen = topEnvironment[\f2UnitWarned];
	if (seen.isNil) { seen = IdentitySet.new; topEnvironment[\f2UnitWarned] = seen };
	if (seen.includes(key.asSymbol).not) { seen.add(key.asSymbol); msg.postln };
	nil
};
// §smp RESOURCE opts (SAMPLER.md §1.0): opts that change no graph — the sample
// itself and the analysis parameters. They ride in the card's opts so they land
// in cfg[\chain] and in the pool fingerprint, but \f2voice turns them into
// BUFFERS at spawn instead of into a SynthDef variant, so they must not enter
// the variant name. A unit lists its resource keys here; everything else is a
// graph opt. (samplerU's later stages fill the analysis buffers — the keys are
// registered now so a saved card carrying them never builds a bogus variant.)
~f2UnitOptsRes = ~f2UnitOptsRes ? IdentityDictionary.new;
~f2UnitOptsRes[\samplerU] = #[\sample, \slicing, \slices, \beatLen, \onsetSens, \pitchSens,
	\bpm, \cuts, \curve];
// §conv-ir convU's sample mode reads the SAME idiom: the impulse response file
// and the end-trim name a prepared BUFFER, not a graph. Both variants declare
// `irBuf`, so neither changes shape when they move — and they must not enter
// the variant name, or every IR and every trim would build its own SynthDef.
~f2UnitOptsRes[\convU] = #[\irSample, \irLen];

// The two schema tables the front reads (ctx.unitOpts / ctx.unitSpecs). They are
// filled unit by unit, and the first filler is convU below — well before the
// three big generators — so the dictionaries are created HERE, at the top, and
// the `?` guard at the polysynth's own block keeps them across a units reload.
~f2UnitOpts = ~f2UnitOpts ? IdentityDictionary.new;
~f2UnitSpecs = ~f2UnitSpecs ? IdentityDictionary.new;

// Variant name: unit ++ "__" ++ sorted opts as "k_v" joined by "__"; every
// character outside [A-Za-z0-9_] becomes "_" (a SynthDef name is one symbol).
//   ~f2UnitVariantName.(\convU, (ir: 'sample')) → convU__ir_sample
// Three keys never reach the name: a RESOURCE opt of this unit (~f2UnitOptsRes —
// no graph difference at all); `freeze` under `env: shot`, because a one-shot
// has no frozen head and the generator normalises it away (SAMPLER.md §1.0) —
// the two spellings of that one graph must not build two defs; and `env` at the
// unit's own DEFAULT model (~f2UnitOpts[unit].env.def — samplerU's old spelling
// `gated` counts as its `ahdsr`). The sampler's rename forces that one: a
// hand-edited save carrying `env: gated` must land on the base def `samplerU`,
// not build a `samplerU__env_gated` (ENVELOPE.md §4.2 — the front rewrites a
// save on load, this is the belt and braces), and once one unit drops its
// default `env` all three do, so `(v1: 4, v2: 1, env: adsr)` and `(v1: 4, v2: 1)`
// are ONE def on every unit (§4.7). `filt: poly` spelled out is deliberately
// NOT dropped — the store drops a default opt, and that rule is tested as is.
// The keys that reach the name, sorted, after the three exclusions above. Split
// out of ~f2UnitVariantName so the collision tripwire below can ask the SAME
// question — which opts does this name actually depend on — without repeating
// the filter and drifting from it.
~f2UnitVariantKeys = { |unit, opts|
	var o = opts ? ();
	var res = ((topEnvironment[\f2UnitOptsRes] ? IdentityDictionary.new)[unit.asSymbol] ? #[]);
	var envV = ((o[\env] ? o["env"]) ? '').asSymbol;
	var envDef = ((((topEnvironment[\f2UnitOpts] ? ())[unit.asSymbol] ? ())[\env] ? ())[\def] ? '').asSymbol;
	var shot = envV == 'shot';
	var envIsDef = (envV == envDef) or: { envV == 'gated' and: { envDef == 'ahdsr' } };
	o.keys.asArray.collect(_.asString).sort.reject { |k|
		res.includesEqual(k.asSymbol) or: { shot and: { k == "freeze" } } or: { envIsDef and: { k == "env" } }
	}
};
~f2UnitVariantName = { |unit, opts|
	var san = { |x| x.asString.collect { |ch| if (ch.isAlphaNum or: { ch == $_ }) { ch } { $_ } } };
	var o = opts ? ();
	var keys = topEnvironment[\f2UnitVariantKeys].value(unit, opts);
	if (keys.isEmpty) { unit.asSymbol } {
		(unit.asString ++ "__" ++ keys.collect { |k|
			san.(k) ++ "_" ++ san.((o[k.asSymbol] ? o[k]) ? "")
		}.join("__")).asSymbol
	}
};
// Resolve (unit, opts) → the SynthDef NAME to spawn. nil/empty opts → the
// unit itself. A variant built by THIS load is answered from ~f2UnitBuilt; a
// desc left in SynthDescLib by a previous load is rebuilt once with the fresh
// generator (the same reason ~f2UnitsVer respawns the pools) and reused as is
// only when the unit has no generator (a hand-registered variant).
// The generator runs inside topEnvironment.use (bare ~f2CondIn / ~f2ChainIn
// in its body must resolve — \f2voice calls this from Event:play, where the
// current environment is the event) and inside try.
// WHERE the build happens matters. From a Routine (the deploy preamble via
// ~f2UnitEnsure) the variant is built, added and the server's ack awaited
// (s.sync) right here — the def exists before the first trigger. From
// Event:play (\f2voice — not a Routine, so no sync is possible, and a graph
// build inside the event thread is a CPU spike on a note) the build is
// kicked ASYNCHRONOUSLY on SystemClock and the BASE unit name is returned for
// this call: the pool spawns the base def, the fingerprint gains "@variant"
// once the def is confirmed, and the pool respawns on its next trigger.
// No generator → warn once and fall back to the base def (the strip keeps
// sounding, the menu just has no effect).
~f2UnitDef = { |unit, opts|
	var u = unit.asSymbol;
	var lib = SynthDescLib.global;
	var gens = topEnvironment[\f2UnitGen];
	var built = topEnvironment[\f2UnitBuilt];
	var warn = topEnvironment[\f2UnitWarnOnce];
	var name, gen, st, build, nm;
	if (built.isNil) { built = IdentityDictionary.new; topEnvironment[\f2UnitBuilt] = built };
	// §smp opts that all filter out of the variant name (a Sampler card carrying
	// only resource opts, or `freeze` inside a Shot variant) resolve to the BASE
	// def: same graph, no second build and no "@variant" in the fingerprint.
	name = if (opts.isNil or: { opts.size == 0 }) { u } {
		topEnvironment[\f2UnitVariantName].value(u, opts)
	};
	if (name == u) { u } {
		st = built[name];
		gen = gens !? { gens[u] };
		// one build: → the resolved def name, or nil (failure cached as \failed, warned once)
		build = {
			try {
				var def = topEnvironment.use { gen.value(opts, name) };
				var dn;
				if (def.isKindOf(SynthDef)) {
					dn = def.name.asSymbol;
					if (dn != name) {
						("⚠ [f2 unit] generator for % named its variant % (expected %) — using %"
							.format(u, dn, name, dn)).postln;
					};
					def.add;
					if (lib.at(dn).isNil) { def.asSynthDesc(\global, true) };   // belt and braces
					("[f2 unit] variant % built".format(dn)).postln;
					dn
				} {
					built[name] = \failed;
					warn.value(name, "⚠ [f2 unit] generator for % returned no SynthDef for % — base def used (until the next f2units load)".format(u, name));
					nil
				}
			} { |err|
				built[name] = \failed;
				warn.value(name, "⚠ [f2 unit] variant % build failed: % — base def used (until the next f2units load)".format(name, err.errorString));
				nil
			}
		};
		case
		{ st.notNil and: { st != \building } and: { st != \failed } } { st }   // built by this load
		{ st == \failed or: { st == \building } } { u }                       // no variant def (yet): the base sounds
		{ gen.isNil } {
			if (lib.at(name).notNil) { built[name] = name; name } {           // hand-registered variant
				warn.value(name, "⚠ [f2 unit] % has no variant generator (~f2UnitGen) — opts % ignored, base def used".format(u, name));
				u
			}
		}
		{ thisThread.isKindOf(Routine) } {
			built[name] = \building;
			nm = build.value;
			if (nm.notNil) {
				if (s.serverRunning) { try { s.sync } };   // on the server before the first trigger
				built[name] = nm;
				nm
			} { u }
		}
		{
			built[name] = \building;
			{
				var dn = build.value;
				if (dn.notNil) {
					if (s.serverRunning) { try { s.sync } };
					built[name] = dn;   // only now does \f2voice resolve to the variant
				};
			}.fork(SystemClock);
			u
		};
	}
};
// §name-collide THE NAME IS THE BUILD-CACHE KEY, AND IT IS NOT INJECTIVE. The
// name is «unit __ sorted k_v joined by __» with every character outside
// [A-Za-z0-9_] replaced by _, so two different opt sets can spell one name: a
// value carrying the joiner ((a: 1, b: 2) and (a: '1__b_2') both give
// fooU__a_1__b_2), and a value whose sanitisation is another's literal spelling
// ('a.b' and 'a b' and 'a_b' all give fooU__filt_a_b). Whichever set is built
// first then answers every later spawn of the other, silently: the card shows
// the user's pick and the voice sounds like the other setting. NOT REACHABLE
// TODAY — every shipped GRAPH opt enumerates bare alnum tokens, and the one
// family that does not (samplerU.beatLen, '1/1'…'1/16d') is a resource opt and
// never enters the name. So this does not re-encode the name: renaming every
// variant would move every save's fingerprint and every expectation in
// build.scd to close a hole nobody can reach. It watches instead, on the DEPLOY
// path only — once per card per deploy, nothing on the note path — and says so
// the first time a name is asked for with opts that are not the ones it was
// built from. Only the keys that REACH the name are compared: a resource opt
// (a different sample on the same variant) is a legitimate difference.
// sc/nrt/variant-name.scd holds the tripwire that fires when the schema itself
// gains a graph opt whose values are not bare alnum.
~f2UnitOptSig = { |unit, opts|
	var o = opts ? ();
	topEnvironment[\f2UnitVariantKeys].value(unit, o).collect { |k|
		k ++ "=" ++ ((o[k.asSymbol] ? o[k]) ? "").asString
	}.join(",")
};
// Deploy-preamble entry (compiled code, before ~play):
//   ~f2UnitEnsure.(\samplerU, (env: 'shot', sample: 'kick'));
// Runs inside a Routine: the variant is built, added and the server's ack
// awaited (s.sync inside ~f2UnitDef) like the port ensures do — the def
// exists before the first trigger. A build kicked asynchronously by an
// earlier event (\f2voice fired before this deploy) is awaited rather than
// duplicated. Returns the resolved def name (the base unit when the variant
// is unavailable).
// §cut it is also the FIRST place a save built on a removed unit is seen: the
// preamble runs before the first note, so the line lands ahead of the silence
// instead of alongside it. `preset` is optional — the compiler passes the
// preset name where it has one; \f2voice names it again at spawn for a card
// whose opts are empty and which therefore reaches no ensure at all.
~f2UnitEnsure = { |unit, opts, preset|
	var built = topEnvironment[\f2UnitBuilt];
	var gone = SynthDescLib.global.at(unit.asSymbol).isNil;
	var name = unit.asSymbol, vn, waited = 0;
	if (gone) {
		topEnvironment[\f2UnitGone].value(unit, preset ? "a preset", nil);
	} {
		if (opts.notNil and: { opts.size > 0 }) {
			var seen = topEnvironment[\f2UnitOptSeen];
			var vnm = topEnvironment[\f2UnitVariantName].value(unit, opts);
			var sig = topEnvironment[\f2UnitOptSig].value(unit, opts);
			if (seen.isNil) { seen = IdentityDictionary.new; topEnvironment[\f2UnitOptSeen] = seen };
			if (vnm != unit.asSymbol) {
				if (seen[vnm].isNil) { seen[vnm] = sig } {
					if (seen[vnm] != sig) {
						topEnvironment[\f2UnitWarnOnce].value(("collide_" ++ vnm).asSymbol,
							"⚠ [f2 unit] the variant name % is not unique: it was built from (%) and is now asked for with (%) — the FIRST build is what sounds".format(vnm, seen[vnm], sig));
					};
				};
			};
		};
		name = topEnvironment[\f2UnitDef].value(unit, opts);
		if (thisThread.isKindOf(Routine) and: { built.notNil } and: { opts.notNil } and: { opts.size > 0 }) {
			vn = topEnvironment[\f2UnitVariantName].value(unit, opts);
			while { built[vn] == \building and: { waited < 3 } } { 0.05.wait; waited = waited + 0.05 };
			if (built[vn] == \building) { built.removeAt(vn) };   // stuck build: the next call retries
			name = topEnvironment[\f2UnitDef].value(unit, opts);
		};
	};
	name
};

// §flat-grain COLA window for grainU grEnv=1: flat top with sin² edges (1/11
// of the window — matches the ×1.1 grain-duration overlap exactly, so at duty
// 1 complementary edges sum to one). A REAL server buffer allocated here at
// load time (f2units loads inside waitForBoot, server is up); its bufnum is
// baked into \grainU as a constant. The first attempt used LocalBuf+SetBuf as
// GrainBuf's envbufnum — grains came out silent; a plain server buffer is the
// reliable path. sclang restart clears ~f2FlatWin, so a fresh boot re-allocs.
~f2FlatWin = ~f2FlatWin ?? {
	var n = 512, f = 47, b;
	// The alloc must be caught, not tested for nil: Buffer.loadCollection goes
	// through Buffer.alloc → Server:nextBufferNumber, which THROWS ("No more
	// buffer numbers") when the allocator is full — it can never hand back nil,
	// so the `b.isNil` branch below was unreachable. And a throw here aborts the
	// whole file: :52…:2646 is ONE expression, so every unit under it — the two
	// newest, polysynthU and samplerU, last — is simply never defined, and
	// f2_boot's bare `p.load` swallows the error without a word.
	b = try {
		Buffer.loadCollection(s, Array.fill(n, { |i|
			var r = 1.0;
			if (i < f) { r = (1 - cos(pi * (i / f))) * 0.5 };
			if (i >= (n - f)) { r = (1 - cos(pi * ((n - 1 - i) / f))) * 0.5 };
			r
		}));
	} { |e|
		("⚠ [f2] flat-grain window alloc failed: " ++ e.errorString).postln; nil
	};
	// Warn and carry on: only grainU's window is degraded, and the next load
	// re-tries (the nil is not cached).
	if (b.isNil) {
		"⚠ [f2] flat-grain window buffer failed to allocate — grainU falls back to buffer 0".postln;
		nil
	} {
		("✓ f2 flat-grain window → buf " ++ b.bufnum).postln;
		b
	}
};

// §poly SAW WAVETABLE BANK for polysynthU (POLYSYNTH.md §2): 12 contiguous
// server buffers (Buffer.allocConsecutive — one bufnum range, so a lane picks
// its mip level as `base + level`, a kr offset Osc re-reads every block).
// Level L covers [27.5·2^L, 55·2^L) Hz and holds the harmonics 1/k that stay
// below SR/2 for the TOP of the band (L = 0 → 436 partials at 48 kHz, L = 8+
// → a sine), normalised, in wavetable format (4096 frames = 2048 points).
// Allocated once per f2units load like ~f2FlatWin (the server is up; the
// base bufnum is baked into the polysynthU defs built below, and the build
// cache is reset on every load, so variants pick the fresh bank up too). A
// reload frees the previous bank once the replacement is in hand — unless the
// server was rebooted in between: its buffer allocator is then a fresh object
// and the old bufnums may already belong to samples, so they are left alone.
~f2PolyTables = {
	var n = 12, sr = (s.sampleRate ? 48000), bufs;
	// The previous bank, and it only counts if THIS allocator handed it out: after
	// a server reboot the allocator is a fresh object and those bufnums may already
	// belong to samples, so they are neither reused nor freed.
	var old = topEnvironment[\f2PolyTables];
	if (old.notNil and: { old[\alloc] !== s.bufferAllocator }) { old = nil };
	// Buffer.allocConsecutive → Server:nextBufferNumber THROWS ("No block of %
	// consecutive buffer numbers is available") instead of returning nil, so the
	// guard below only ever runs if the throw is caught here — see ~f2FlatWin.
	bufs = try { Buffer.allocConsecutive(n, s, 4096) } { |e|
		("⚠ [f2] poly saw tables alloc failed: " ++ e.errorString).postln; nil
	};
	if (bufs.isNil or: { bufs.isEmpty } or: { bufs.first.isNil }) {
		"⚠ [f2] poly saw tables failed to allocate — the previous bank is kept (reload f2units once buffers are free)".postln;
		old        // nil on a first load; on a reload the bank that still works
	} {
		// Only NOW is the old bank retired. Freeing it first — what this used to do
		// — meant a failed replacement left ~f2PolyTables pointing at bufnums that
		// no longer exist, and polysynthU bakes the base bufnum into the SynthDef as
		// a CONSTANT: every voice then read dead buffers and the card was silent for
		// the rest of the session while its node stayed alive and gated.
		old !? { |o| (o[\bufs] ? []).do { |b| try { b.free } } };
		bufs.do { |b, l|
			var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
			b.sine1(Array.fill(h, { |k| 1 / (k + 1) }), true, true, true);
		};
		("✓ f2 poly saw tables → bufs %…% (% levels @ % Hz)".format(
			bufs.first.bufnum, bufs.last.bufnum, n, sr)).postln;
		(base: bufs.first.bufnum, n: n, bufs: bufs, alloc: s.bufferAllocator)
	}
}.value;

// §pm TRIANGLE + HALF-SINE BANKS for polymerU (POLYMER.md §2.1): two more
// 12-level mip banks in ONE contiguous range beside the saw bank — levels 0…11
// the geometric triangle (odd harmonics, 1/k², alternating sign), levels 12…23
// the half-sine (the half-wave rectified sine, its fundamental at ½ and its even
// partials 2/(π(1−4n²)), without the DC term a rectifier leaves, which would
// only reach the blocker). Level L holds the partials that stay below SR/2 for
// the TOP of its band, exactly as the saw bank cuts them, so the three banks
// agree on what `lvl` means and Union's three reads of one phasor share it.
// Both are SINE-phased like the saw bank (0 at phase 0, the triangle's peak at
// ¼): that is what makes the three fundamentals add in phase in Union, and it
// is why Triangle's fold reads the table at tri/4 (§2.2: fold2(x, 1) IS a
// triangle function of x — for this phasing, exactly T(x/4)). A mip bank and
// not `abs(SinOsc)` for the half-sine (§2.4): the rectifier's corners alias.
// The partial list per level is exported so the offline checks can rebuild
// the same tables inside a score (~f2SmpWinShape, same reason).
~f2PolymerTablePartials = { |kind, l, sr = 48000|
	var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
	var fr = [], am = [], ph = [];
	if (kind == \tri) {
		// not `-1 ** i`: sclang's pow keeps the sign of its base ((-1) ** 2 is -1)
		(1, 3 .. h).do { |k, i| fr = fr.add(k); am = am.add((1 - (2 * (i % 2))) / (k * k)); ph = ph.add(0) };
	} {
		fr = [1]; am = [0.5]; ph = [0];
		(2, 4 .. h).do { |k| var m = k / 2;
			fr = fr.add(k); am = am.add(2 / (pi * (1 - (4 * m * m)))); ph = ph.add(0.5pi) };
	};
	[fr, am, ph]
};
// Allocated once per f2units load with the saw bank's invariants: the alloc
// inside `try` (Server:nextBufferNumber THROWS, it never returns nil, and a
// throw here would abandon every unit below — polymerU is the last), the old
// bank freed only AFTER the new one is in hand (the base bufnum is baked into
// every polymerU def as a constant, so a failed replacement must leave the
// bank the defs were built on alive), and `alloc` stamped so a bank from before
// a server reboot is neither reused nor freed. The half-sine bank is `base + n`.
~f2PolymerTables = {
	var n = 12, sr = (s.sampleRate ? 48000), bufs;
	var old = topEnvironment[\f2PolymerTables];
	if (old.notNil and: { old[\alloc] !== s.bufferAllocator }) { old = nil };
	bufs = try { Buffer.allocConsecutive(n * 2, s, 4096) } { |e|
		("⚠ [f2] polymer tri/half-sine tables alloc failed: " ++ e.errorString).postln; nil
	};
	if (bufs.isNil or: { bufs.isEmpty } or: { bufs.first.isNil }) {
		"⚠ [f2] polymer tri/half-sine tables failed to allocate — the previous bank is kept (reload f2units once buffers are free)".postln;
		old
	} {
		old !? { |o| (o[\bufs] ? []).do { |b| try { b.free } } };
		bufs.do { |b, i|
			var p = topEnvironment[\f2PolymerTablePartials].value(if (i < n) { \tri } { \half }, i % n, sr);
			b.sine3(p[0], p[1], p[2], true, true, true);
		};
		("✓ f2 polymer tri + half-sine tables → bufs %…% (2 × % levels @ % Hz)".format(
			bufs.first.bufnum, bufs.last.bufnum, n, sr)).postln;
		(base: bufs.first.bufnum, n: n, bufs: bufs, alloc: s.bufferAllocator)
	}
}.value;

// §smp GRAIN WINDOW BANK for samplerU (SAMPLER.md §1.5 / §3). The release
// notes describe Grain Envelope as a continuous curve MORPH, not a menu, so
// `grainEnv` stays a LIVE control and simply picks a bufnum inside one
// contiguous range: 16 windows, index = base + round(grainEnv · 15).
//   window  0 — the quick-attack pluck (F2's choice for the 0 end, §8 b);
//   window  4 — exactly the flat COLA window grainU uses (~f2FlatWin);
//   window 15 — a full Hann: open and soft at both ends.
// Between them the sin² edges widen (the exponent is DERIVED so that index 4
// lands on 47/512 — the flat window's edge — instead of being tuned by hand)
// and the pluck's downward tilt fades out by index 4. The shape function is
// exported so the offline checks can rebuild the same table inside a score.
~f2SmpWinShape = { |i, n = 16, len = 512|
	var eLo = 0.002, eHi = 0.5, eFlat = 47 / 512;
	var ex  = ((eFlat - eLo) / (eHi - eLo)).log / (4 / (n - 1)).log;
	var f   = i / (n - 1);
	var e   = eLo + ((f ** ex) * (eHi - eLo));      // sin² edge, 0.002 … 0.5 of the window
	var k   = (1 - (i / 4)).max(0) * 2;             // pluck tilt, gone from index 4 up
	Array.fill(len, { |j|
		var x = j / (len - 1);
		var r = 1.0;
		if (x < e) { r = (1 - cos(pi * (x / e))) * 0.5 };
		if (x > (1 - e)) { r = (1 - cos(pi * ((1 - x) / e))) * 0.5 };
		r * ((1 - x) ** k)
	})
};
// Allocated once per f2units load, exactly like ~f2PolyTables (the base bufnum
// is baked into the samplerU defs built below, and the build cache is reset on
// every load, so variants pick the fresh bank up too). Filled with /b_setn
// rather than Buffer.loadCollection: no temp file and no server round trip, so
// the bank also exists in the offline rig.
// The fill rides on /b_alloc's COMPLETION MESSAGE, and it must. /b_alloc is an
// ASYNCHRONOUS command — scsynth hands it to its non-realtime thread — while
// /b_setn is executed immediately on the realtime thread. Sent as two plain
// messages back to back, the fill therefore reaches a buffer that does not exist
// yet and the server DROPS IT WITHOUT A WORD: the whole 16-window bank stayed
// zero on a live server, and GrainBuf with an all-zero envelope outputs exactly
// zero — every samplerU grain path (Textures, and grainEnv on any mode) was
// silent. Offline this never showed, because an NRT score executes /b_alloc and
// /b_setn in timestamp order on one thread. A completion message is executed by
// the server the moment the allocation itself is done, so the order is the
// server's to keep and no s.sync (⇒ no Routine) is needed here.
~f2SmpWins = {
	var n = 16, len = 512, bufs;
	var old = topEnvironment[\f2SmpWins];              // ~f2PolyTables, same rules
	if (old.notNil and: { old[\alloc] !== s.bufferAllocator }) { old = nil };
	bufs = try {
		Buffer.allocConsecutive(n, s, len, 1, { |bf, i|
			bf.setnMsg(0, topEnvironment[\f2SmpWinShape].value(i, n, len))
		})
	} { |e|
		("⚠ [f2] smp grain windows alloc failed: " ++ e.errorString).postln; nil
	};
	if (bufs.isNil or: { bufs.isEmpty } or: { bufs.first.isNil }) {
		"⚠ [f2] smp grain windows failed to allocate — the previous bank is kept (samplerU falls back to the built-in Hann)".postln;
		old
	} {
		old !? { |o| (o[\bufs] ? []).do { |b| try { b.free } } };
		("✓ f2 smp grain windows → bufs %…% (% windows, flat COLA at %)".format(
			bufs.first.bufnum, bufs.last.bufnum, n, bufs[4].bufnum)).postln;
		(base: bufs.first.bufnum, n: n, bufs: bufs, alloc: s.bufferAllocator)
	}
}.value;

// ── §smp SLICE TABLE AND SLICING ANALYSIS (SAMPLER.md §1.0 / §6) ───────────
// The slice grid reaches the graph as ONE buffer, `[n, b0 … bn]`: the count in
// the header, then n+1 ascending boundaries in 0…1 of the sample. Every slicing
// mode produces that one shape, so the SynthDef has a SINGLE code path whatever
// computed the boundaries, `slice` stays a live control (the count is read from
// the header every block) and a re-analysis REFILLS THE SAME BUFFER — the
// bufnum never changes, so a note already sounding picks the new grid up
// without a respawn.
//
// The five modes of the `slicing` opt (§1.0): `div` and `beats` are arithmetic
// — `div` needs nothing at all, `beats` needs the file tempo; `onsets` and
// `pitch` read the offline pass below; `manual` starts blank. Every mode merges
// the card's manual markers on top ([RN]: manual and computed slices coexist).
//
// WHERE THE WORK HAPPENS (§6): never on the audio path. ONE NRT scsynth pass
// per FILE — Onsets, Pitch and an amplitude follower recorded at control rate
// into a buffer, written out and read back by sclang — kicked off the event
// thread at the first spawn that needs it. The sensitivity filters are applied to that one
// raw result afterwards, so moving `onsetSens` / `pitchSens` re-slices in sclang
// alone: no render, no new buffer, no respawn, nothing for the voice pool to
// fight with.
~f2SmpSliceMax = 64;                 // `slice` is a 0…63 control ⇒ 64 usable slices
// §1.0 the `cuts` RESOURCE opt — the card's own manual boundaries, on their way
// to the table. They ride in an opt VALUE, which becomes a SuperCollider symbol
// and a word of the compiled session text, so the encoding may use nothing the
// compiler's sanitiser rewrites ([A-Za-z0-9_]): ten-thousandths of the file
// joined by "_", `1250_5000` = 0.125 and 0.5. One ten-thousandth is finer than
// the half-pixel the card merges two boundaries at, and every boundary is
// INTERIOR (0 and 1 are the ends ~f2SmpSeal adds), so each is at most 4 digits.
~f2SmpCutScale = 10000;
// one manual boundary per slice the table can hold: past ~f2SmpSliceMax the
// seal drops them anyway, and the value stays a legible ≤ 314 characters.
~f2SmpCutMax = 63;
~f2SmpCuts = { |raw|
	var s = (raw ? "").asString;
	var scale = (topEnvironment[\f2SmpCutScale] ? 10000);
	if (s.isEmpty) { [] } {
		s.split($_).collect { |t|
			// a token that is not a plain integer is dropped, never guessed at
			if (t.isEmpty or: { t.every { |c| c.isDecDigit }.not }) { -1 } { t.asInteger / scale }
		}.select { |x| (x > 0) and: { x < 1 } }.sort.keep(topEnvironment[\f2SmpCutMax] ? 63)
	}
};
// `beatLen` (§1.0) in BEATS — 1/4 is the beat itself, `t` triplet, `d` dotted
~f2SmpBeatLen = IdentityDictionary[
	'1/1' -> 4, '1/2' -> 2, '1/4' -> 1, '1/8' -> 0.5, '1/16' -> 0.25, '1/32' -> 0.125,
	'1/4t' -> (2/3), '1/8t' -> (1/3), '1/16t' -> (1/6), '1/32t' -> (1/12),
	'1/4d' -> 1.5, '1/8d' -> 0.75, '1/16d' -> 0.375
];

// interior boundaries → the sealed table [0, … , 1]: sorted, clipped, deduped
// (two boundaries less than one FRAME apart are one boundary) and capped at
// ~f2SmpSliceMax slices. The first and the last boundary are always exactly the
// ends of the sample: the table covers the whole file and the blue Slicing
// markers stretch it in the graph (§1.8).
~f2SmpSeal = { |interior, frames, nMax|
	var gap = if ((frames ? 0) > 64) { 1 / frames } { 1e-6 };
	var cap = (nMax ? 64).clip(1, 4096);
	var acc = [0.0];
	((interior ? []).collect(_.asFloat).select { |x|
		x.isNaN.not and: { x > 0 } and: { x < 1 }
	}.sort).do { |x|
		if ((x - acc.last) > gap and: { acc.size < cap }) { acc = acc.add(x) };
	};
	if ((1.0 - acc.last) <= gap and: { acc.size > 1 }) { acc = acc.drop(-1) };
	acc.add(1.0)
};

// Onset slicing (§1.0). [RN] «Onset Sensitivity default 100 % (all onsets),
// lower removes weaker onsets» — so the percentage is read as a floor on an
// onset's STRENGTH relative to the strongest one in the file: 100 % keeps
// everything, 50 % keeps the onsets at least half as loud as the loudest, 0 %
// keeps the loudest alone. The detector itself runs once, at full sensitivity;
// this is a filter over its result, which is why moving the knob is free.
~f2SmpOnsetBounds = { |raw, sens, nMax|
	var pairs = ((raw !? { raw[\onsets] }) ? []);
	var top = if (pairs.isEmpty) { 0 } { pairs.maxItem { |e| e[1] }[1] };
	var cut = top * (1 - ((sens ? 100).clip(0, 100) / 100));
	var keep = pairs.select { |e| e[1] >= cut };
	// past the cap the sensitivity ordering decides which survive
	if (keep.size > ((nMax ? 64) - 1)) {
		keep = keep.sort { |a, b| a[1] > b[1] }.keep((nMax ? 64) - 1);
	};
	keep.collect(_[0])
};

// Pitch slicing (§1.0). [RN] «cuts at detected pitch changes; Pitch Sensitivity
// default 70 %, lower gives fewer slices» — F2 reads the percentage as the size
// of the step that counts as a change: 100 % cuts at a quarter tone, 70 % at
// ~1.7 semitones, 0 % only at a tritone (`~`, §8 b). A step has to HOLD for
// three hops to become a boundary, so a glide gives one cut per threshold
// crossed instead of fifty, and a single bad frame gives none.
~f2SmpPitchBounds = { |raw, sens|
	var hz  = ((raw !? { raw[\pitchHz] }) ? []);
	var ok  = ((raw !? { raw[\pitchOk] }) ? []);
	var amp = ((raw !? { raw[\amp] }) ? []);
	var flr = ((raw !? { raw[\ampPeak] }) ? 0) * 0.08;   // no pitch out of a decay tail
	var hop = ((raw !? { raw[\hop] }) ? 0);              // one control frame, in 0…1
	var lag = ((raw !? { raw[\pitchLag] }) ? 0);         // the tracker's own delay, in 0…1
	var thr = 0.25 + (5.75 * (1 - ((sens ? 70).clip(0, 100) / 100)));
	var minGap = ((raw !? { raw[\minGap] }) ? 0);        // 40 ms, in 0…1
	var ref = nil, cand = nil, run = 0, runAt = 0, out = [], last = -1;
	hz.do { |f, i|
		if (((ok[i] ? 0) > 0.5) and: { f > 20 } and: { (amp[i] ? 1) > flr }) {
			if (ref.isNil) {
				// the initial lock needs three frames that agree within a semitone:
				// Pitch reports its own init frequency for a frame or two before it
				// has material to track, and that must never become the reference
				if (cand.notNil and: { (12 * log2(f / cand)).abs < 1 }) {
					run = run + 1;
					if (run >= 3) { ref = f; run = 0 };
				} { cand = f; run = 1 };
			} {
				if ((12 * log2(f / ref)).abs > thr) {
					if (run == 0) { runAt = i };
					run = run + 1;
					if (run >= 3) {
						// back by the tracker's delay: it cannot report a new pitch before
						// two periods of its lowest frequency have gone by, and the CUT
						// belongs where the material changed, not where the tracker noticed
						var pos = ((runAt * hop) - lag).max(0);
						if (pos > (last + minGap)) { out = out.add(pos); last = pos };
						ref = f; run = 0;
					};
				} { run = 0 };
			};
		} { run = 0 };
	};
	out
};

// §4 THE PITCH CURVE the graph reads (`pAt`, SAMPLER.md §2): Hz per frame, so
// frame i is the detected pitch at i/(N−1) of the WHOLE file. Unvoiced hops —
// and hops under the amplitude floor, where the tracker reports the decay tail
// of the last note — HOLD the previous pitch, and the head of the curve is
// back-filled with the first detected one: `pAt(0)` is what the Repitch speed
// compensation divides by, and the opening hops of a file are an attack the
// tracker cannot pitch. Resampled to at most ~f2SmpPitchMax frames — the raw
// pass hops every 64 samples (≈ 1.5 ms), which is ~20 000 frames for half a
// minute of audio, far past what one /b_alloc completion message can carry, and
// far finer than a root reference needs. nil when the file has no detected
// pitch at all: the card then keeps pitchBuf −1 and an `analyzed` root falls
// back to the manual one (§6).
~f2SmpPitchMax = 1024;
~f2SmpPitchCurve = { |raw|
	var hz  = ((raw !? { raw[\pitchHz] }) ? []);
	var ok  = ((raw !? { raw[\pitchOk] }) ? []);
	var amp = ((raw !? { raw[\amp] }) ? []);
	var flr = ((raw !? { raw[\ampPeak] }) ? 0) * 0.08;
	var cap = (topEnvironment[\f2SmpPitchMax] ? 1024).clip(16, 8192);
	var last = 0, first = nil, held;
	if (hz.size < 2) { nil } {
		held = hz.collect { |f, i|
			if (((ok[i] ? 0) > 0.5) and: { f > 20 } and: { (amp[i] ? 1) > flr }) {
				last = f;
				if (first.isNil) { first = f };
				f
			} { last };
		};
		if (first.isNil) { nil } {
			// back-fill the silent head, then thin the curve onto the buffer grid
			held = held.collect { |f| if (f > 20) { f } { first } };
			if (held.size <= cap) { held } {
				Array.fill(cap, { |i| held[((i / (cap - 1)) * (held.size - 1)).round.asInteger] })
			};
		};
	};
};
// §4 ONE pitch buffer per FILE (the curve describes a file, nothing else), so
// every analysis entry of that sample — one per slicing setting, and `cuts`
// mints a fresh one on every marker drag — shares it. Reset with the units: a
// bufnum from a previous load means nothing to a re-allocated server. The fill
// travels as /b_alloc's COMPLETION message, never as a /b_setn straight after
// it: the allocation is queued on the non-realtime thread while a following
// /b_setn is executed immediately on the realtime one, and the server drops it
// (measured — the grain-window bank and the slice tables both read back as all
// zeros on a live server, see ~f2SmpWins).
~f2SmpPitchBufs !? { |old| old.do { |b| try { b.free } } };
~f2SmpPitchBufs = IdentityDictionary.new;
~f2SmpPitchBufAt = { |path, raw|
	var d = topEnvironment[\f2SmpPitchBufs];
	var key = (path ? "-").asSymbol;
	var b = d[key];
	if (b.notNil) { b } {
		var curve = topEnvironment[\f2SmpPitchCurve].(raw);
		if (curve.isNil) { nil } {
			try {
				b = Buffer.alloc(s, curve.size, 1, { |bf| bf.setnMsg(0, curve) });
				d[key] = b;
				("✓ [f2 smp] pitch curve % → buf % (% frames, % … % Hz)".format(
					key, b.bufnum, curve.size, curve.minItem.round(0.1),
					curve.maxItem.round(0.1))).postln;
				b
			} { |e|
				topEnvironment[\f2UnitWarnOnce].(("smp_pitchbuf_" ++ key).asSymbol,
					"⚠ [f2 smp] the pitch curve of % could not be allocated: % — the analyzed root falls back to the manual one".format(key, e.errorString));
				nil
			};
		};
	};
};

// ── §smp SPECTRAL ARTEFACTS (SAMPLER.md §6, §1.7) ─────────────────────────
// Spectral is the one mode that reads all four §6 buffers, and two of them
// exist for it alone. They are built here, beside the pitch curve, for the same
// reason it is: they describe a FILE, not a card — the onset table is per
// (sample, onsetSens) and the FFT frames per (sample, qual) — so every card
// asking for the same pair reads the same buffer and pays for it once.

// §3 the availability check, ONCE at load. PV_RecordBuf writes the frames and
// PV_BufRd plays them back; neither is in the core, and nor are the crossfade
// and the diffuser the arm mixes with. The contract spells the check
// `\PV_PlayBuf.asClass.notNil` — one class standing for the whole sc3-plugins
// PV set — and what is checked here is the classes this graph INSTANTIATES, so
// a half-installed extension cannot pass the check and then fail to compile a
// def at the first note. False ⇒ the spectral variant is the Warp1 fallback of
// §2, which needs nothing but `buf`, and the reduced-capability warning is
// posted once (CARDS.md §12).
~f2SmpPVNeeds = #[\PV_RecordBuf, \PV_BufRd, \PV_XFade, \PV_Diffuser, \PV_BrickWall,
	\PV_MagSmear, \PV_MagMul, \PV_MagDiv, \PV_BinShift, \PV_Add, \PV_Copy];
~f2SmpPV = ~f2SmpPVNeeds.every { |k| k.asClass.notNil };
if (~f2SmpPV.not) {
	("⚠ [f2 smp] sc3-plugins is missing % — play: spectral falls back to Warp1 (no formants, no REHARM, no phase dispersion, no Preserve Onsets)".format(
		~f2SmpPVNeeds.reject { |k| k.asClass.notNil })).postln;
};

// §1.0 `qual` → FFT size and OVERLAP FACTOR. [RN] names only Low / Medium /
// High / Ultra; the four pairs are F2's (`~`, §8 b). The hop is the overlap's
// reciprocal and it is what the two sides have to agree on — PV_RecordBuf
// writes it into the analysis buffer's header, so PV_BufRd cannot disagree.
~f2SmpQual = IdentityDictionary[
	'low'    -> #[1024, 2],
	'medium' -> #[2048, 4],
	'high'   -> #[4096, 4],
	'ultra'  -> #[4096, 8]
];
// WINDOW TYPE 0 = sine, on the analysis AND on the resynthesis. It is not a
// free choice: the two windows multiply, so sine·sine is Hann — and Hann sums
// to a CONSTANT at every overlap in the table above. Hann on both sides
// (wintype 1) would square to Hann², which at the ×2 overlap `qual: low` uses
// ripples ±33 % at the frame rate: a 94 Hz buzz on every sustained note, at the
// one quality setting chosen for costing least.
~f2SmpFftWin = 0;
// …and the constant the overlap sums to, divided back out, so `qual` changes
// the RESOLUTION and never the LEVEL. MEASURED per (size, overlap) on a steady
// tone read at speed 1, not derived: the PV_RecordBuf → PV_BufRd round trip
// carries a scaling of its own, so the arithmetic overlap sum is not the
// number. Without it the four settings stand up to 15.7 dB apart and the
// quality menu is a volume knob.
~f2SmpFftGain = IdentityDictionary[
	'low'    -> 2.220,      // measured 0.450 ×
	'medium' -> 0.799,      // measured 1.252 ×
	'high'   -> 0.801,      // measured 1.248 ×
	'ultra'  -> 0.365       // measured 2.740 ×
];
~f2SmpFftOf = { |qual|
	var k = (qual ? 'medium').asSymbol;
	var q = ((topEnvironment[\f2SmpQual] ? IdentityDictionary.new)[k] ? #[2048, 4]);
	(nfft: q[0], ovl: q[1], hop: q[1].reciprocal,
		wintype: (topEnvironment[\f2SmpFftWin] ? 0),
		gain: (((topEnvironment[\f2SmpFftGain] ? IdentityDictionary.new)[k]) ? 1.0),
		// the magnitude smear the formant stage estimates the spectral envelope
		// with: NFFT/256 bins is a fixed ±190 Hz at 48 kHz whatever the window
		// size, so the envelope is the same curve at every `qual` instead of
		// tracking the harmonics at 4096 and missing them at 1024 (`~`, §8 b)
		smear: (q[0] / 256).max(1).asInteger)
};

// §6 `fftBuf`, the analysis of the file at this quality. calcPVRecSize rounds
// the file UP to a whole number of windows, so the buffer is up to one window
// longer than the material — the arm divides that padding back out, or the
// head would run into analysed silence before the file ended.
~f2SmpFftRecSize = { |dur, qual, sr|
	var f = topEnvironment[\f2SmpFftOf].(qual);
	(dur ? 1).max(0.001).calcPVRecSize(f[\nfft], f[\hop], sr ? 48000)
};
// The recorder, ONE DEF PER QUAL: NFFT is a LocalBuf size and the hop is a
// window argument, both instantiation arguments, so neither can be an arg. The
// pass is exactly the file (PlayBuf frees the node at its end) and it is
// silent — the FFT chain has to be pulled by something that reaches an Out,
// and DC.ar(0) added to the hardware bus is the cheapest nothing there is.
~f2SmpFftRecDef = { |qual|
	var f = topEnvironment[\f2SmpFftOf].(qual);
	SynthDef(("f2SmpFftRec_" ++ qual).asSymbol, { |buf = 0, fftBuf = 1|
		var in = PlayBuf.ar(1, buf, BufRateScale.kr(buf), 1, 0, 0, 2);
		topEnvironment[\f2PvRecordBuf].(FFT(LocalBuf(f[\nfft], 1), in, f[\hop], f[\wintype]),
			fftBuf, 0, 1, 0, f[\hop], f[\wintype]);
		Out.ar(0, DC.ar(0));
	})
};
// …and the analysis of SILENCE, four windows of it, one per qual. This is a
// CORRECTNESS requirement, not an optimisation: §6 lets a spectral voice be
// spawned with `fftBuf = -1` (the record pass is keyed on the sample and runs
// on demand, so the first note of a fresh file arrives before it), and
// PV_BufRd pointed at a bufnum that is NOT an analysis takes the server down —
// measured, an NRT render stopped writing at the exact block such a voice
// started, mid-score, with nothing on the console. In a live session that is
// the whole audio engine, not one silent note. So the variant carries the
// bufnum of a real, empty analysis as a build constant (as ~f2SmpWins' base is
// one), reads that instead, and gates its output to digital silence — which is
// what §6 asks the pending note to be.
~f2SmpFftNullSize = { |qual, sr|
	var f = topEnvironment[\f2SmpFftOf].(qual);
	(((f[\nfft] * 4) / (sr ? 48000)).calcPVRecSize(f[\nfft], f[\hop], sr ? 48000))
};
~f2SmpFftNullDef = { |qual|
	var f = topEnvironment[\f2SmpFftOf].(qual);
	SynthDef(("f2SmpFftNull_" ++ qual).asSymbol, { |fftBuf = 1|
		Line.kr(1, 1, (f[\nfft] * 4) / SampleRate.ir, doneAction: 2);
		topEnvironment[\f2PvRecordBuf].(FFT(LocalBuf(f[\nfft], 1), DC.ar(0), f[\hop], f[\wintype]),
			fftBuf, 0, 1, 0, f[\hop], f[\wintype]);
		Out.ar(0, DC.ar(0));
	})
};
// The two defs per qual, built and sent once. They are ordinary library defs so
// the offline rig can /d_recv them into a score, exactly as it does the unit
// defs (sc/nrt/sweep.scd records both there — an NRT render has no load-time
// server to have done it already).
~f2SmpFftDefs = IdentityDictionary.new;
if (~f2SmpPV) {
	~f2SmpQual.keys.asArray.sort.do { |q|
		var rec = topEnvironment[\f2SmpFftRecDef].(q);
		var nul = topEnvironment[\f2SmpFftNullDef].(q);
		~f2SmpFftDefs[q] = (rec: rec, null: nul);
		try { rec.add; nul.add } { |e|
			("⚠ [f2 smp] the % analysis defs could not be added: %".format(q, e.errorString)).postln;
		};
	};
};
// The null analyses themselves: allocated and RECORDED at load, before any
// spectral def can be built, because the bufnum is baked into the variant.
// Three asynchronous commands in a row, and the order is the whole point: the
// /b_alloc is queued on the server's non-realtime thread while a /d_recv or a
// /s_new sent straight after it is executed on the realtime one, so the fill
// would reach a buffer that does not exist and the synth a def that has not
// landed (the lesson ~f2SmpWins is written from). Chaining them as COMPLETION
// messages — alloc → d_recv → s_new — hands the ordering to the server.
~f2SmpFftNullBufs !? { |old| old.do { |b| try { b.free } } };
~f2SmpFftNullBufs = IdentityDictionary.new;
~f2SmpFftNull = {
	var out = IdentityDictionary.new;
	if (~f2SmpPV) {
		var sr = (s.tryPerform(\sampleRate) ? 48000);
		~f2SmpQual.keys.asArray.sort.do { |q|
			try {
				var d = topEnvironment[\f2SmpFftDefs][q][\null];
				var b = Buffer.alloc(s, topEnvironment[\f2SmpFftNullSize].(q, sr).asInteger, 1,
					{ |bf| ['/d_recv', d.asBytes,
						['/s_new', d.name, s.nextNodeID, 0, 0, 'fftBuf', bf.bufnum]] });
				topEnvironment[\f2SmpFftNullBufs][q] = b;
				out[q] = b.bufnum;
			} { |e|
				("⚠ [f2 smp] the % null analysis could not be allocated: % — spectral falls back to Warp1 there".format(q, e.errorString)).postln;
			};
		};
		("✓ f2 smp spectral: null analyses → bufs %".format(
			out.keys.asArray.sort.collect { |k| k -> out[k] })).postln;
	};
	out
}.value;

// §6 the per-file record pass. One buffer per (sample, qual), kicked at the
// first spawn that needs it and `-1` until it has landed — a spectral voice
// spawned in that window stays silent for the note and posts the warning once,
// which is §6's own rule and not an error. It runs on the LIVE server (an FFT
// of the whole file is one PV_RecordBuf pass in real time; the Go-core pass of
// the other three artefacts has no FFT to give) and the node frees itself when
// PlayBuf reaches the end of the file, so there is nothing to collect.
~f2SmpFftBufs !? { |old| old.do { |e| e[\bufObj] !? { |b| try { b.free } } } };
~f2SmpFftBufs = IdentityDictionary.new;
~f2SmpFftBufAt = { |path, qual, dur, sbufnum|
	var d = topEnvironment[\f2SmpFftBufs];
	var q = (qual ? 'medium').asSymbol;
	var key = ((path ? "-").asString ++ "|" ++ q).asSymbol;
	var e = d[key];
	case
		// topEnvironment, not `~`: this runs from \f2voice inside an Event, where
		// currentEnvironment is that Event and every `~name` of the library reads
		// back nil
		{ (topEnvironment[\f2SmpPV] ? false).not or: { path.isNil } or: { sbufnum.isNil } } { -1 }
		{ e.notNil } { if (e[\state] == \ready) { e[\bufnum] } { -1 } }
		{ true } {
			var len = (dur ? 1).max(0.001);
			e = (state: \pending, bufnum: -1);
			d[key] = e;
			try {
				var def = topEnvironment[\f2SmpFftDefs][q][\rec];
				var size = topEnvironment[\f2SmpFftRecSize].(len, q,
					(s.tryPerform(\sampleRate) ? 48000)).asInteger;
				var b = Buffer.alloc(s, size, 1, { |bf|
					['/d_recv', def.asBytes,
						['/s_new', def.name, s.nextNodeID, 0, 0,
							'buf', sbufnum, 'fftBuf', bf.bufnum]]
				});
				e[\bufObj] = b;
				// the pass is the file played once, so it is DONE a file later.
				// A margin of 0.3 s covers the three asynchronous commands above;
				// reading a half-written analysis is not an error (the unwritten
				// frames are silence), but it would be an audibly truncated note.
				SystemClock.sched(len + 0.3, {
					e[\bufnum] = b.bufnum; e[\state] = \ready;
					("✓ [f2 smp] fft % @ % → buf % (% floats, % s)".format(
						(path ? "-").asString.basename, q, b.bufnum, size,
						len.round(0.01))).postln;
					nil
				});
			} { |e2|
				e[\state] = \failed;
				topEnvironment[\f2UnitWarnOnce].(("smp_fftbuf_" ++ key).asSymbol,
					"⚠ [f2 smp] the % analysis of % could not be allocated: % — the spectral voice stays silent".format(q, key, e2.errorString));
			};
			-1
		}
};

// §6 / §1.7 `onsetBuf`, the one onset table that serves BOTH consumers.
// `slicing: onsets` filters the raw pass in sclang and needs no buffer at all;
// Preserve Onsets asks the same table a different question — «is the head near
// a transient right now» — and the head is a POSITION, not an index: it jumps
// at every cell re-anchor, it reverses, and under `freeze` it stands still. So
// the buffer carries both shapes. First the §6 LIST BLOCK, `[n, p0 … p62]` at a
// FIXED size, which is what a boundary reader wants; then a dense PROXIMITY
// CURVE over 0…1 of the file — 1 at an onset, falling to 0 over
// ~f2SmpOnsetWin seconds of material. The curve is ONE BufRd at the head and it
// is right in the first block after a jump, where scanning the list costs up to
// 64 BufRd per block and a walking index desynchronises for as many blocks as
// the jump was wide. The list block is fixed-size on purpose: the curve's
// offset is then a build constant, where a live `n` would slide the whole curve
// under the reader every time a re-analysis refilled the header.
~f2SmpOnsetProx = 1024;          // samples of the dense curve
~f2SmpOnsetWin  = 0.030;         // s of material one onset holds the read at natural speed (`~`)
~f2SmpOnsetTau  = 0.25;          // s the time debt that buys takes to bleed off (`~`)
~f2SmpOnsetHdr  = { (topEnvironment[\f2SmpSliceMax] ? 64) + 1 };
~f2SmpOnsetData = { |onsets, dur|
	var hdr  = topEnvironment[\f2SmpOnsetHdr].value;
	var nP   = (topEnvironment[\f2SmpOnsetProx] ? 1024);
	var win  = (topEnvironment[\f2SmpOnsetWin] ? 0.03);
	var keep = (onsets ? []).select { |x| (x >= 0) and: { x <= 1 } }.sort.keep(hdr - 1);
	var list = ([keep.size] ++ keep ++ Array.fill(hdr - 1 - keep.size, 0)).keep(hdr);
	// the curve is the distance SINCE the last onset in window units, 1 → 0, so
	// a head that lands anywhere inside a transient reads how far into it it is
	var span = (win / (dur ? 1).max(0.001)).clip(1 / nP, 1);
	var prox = Array.fill(nP, { |i|
		var x = i / (nP - 1);
		var last = -1e9;
		keep.do { |p| if (p <= x) { last = max(last, p) } };
		(1 - ((x - last) / span)).clip(0, 1)
	});
	(list ++ prox).collect(_.asFloat)
};
// One buffer per (sample, onsetSens) — the sensitivity is a resource opt and
// filtering is free, so two cards at two sensitivities are two tables and the
// same sensitivity is always the same buffer.
~f2SmpOnsetBufs !? { |old| old.do { |b| try { b.free } } };
~f2SmpOnsetBufs = IdentityDictionary.new;
~f2SmpOnsetBufAt = { |path, sens, raw, dur|
	var d = topEnvironment[\f2SmpOnsetBufs];
	var key = ((path ? "-").asString ++ "|" ++ (sens ? 100)).asSymbol;
	var b = d[key];
	if (b.notNil) { b } {
		var ons = topEnvironment[\f2SmpOnsetBounds].(raw, sens,
			(topEnvironment[\f2SmpSliceMax] ? 64) + 1);
		var data = topEnvironment[\f2SmpOnsetData].(ons, dur);
		try {
			b = Buffer.alloc(s, data.size, 1, { |bf| bf.setnMsg(0, data) });
			d[key] = b;
			("✓ [f2 smp] onsets % → buf % (% onsets)".format(key, b.bufnum, ons.size)).postln;
			b
		} { |e|
			topEnvironment[\f2UnitWarnOnce].(("smp_onsetbuf_" ++ key).asSymbol,
				"⚠ [f2 smp] the onset table of % could not be allocated: % — Preserve Onsets behaves as off".format(key, e.errorString));
			nil
		};
	};
};

// §1.7 the `harmQuant: KEY` grid. Eight modes (the list is F2's, `~`, §8 b)
// flattened into one 96-entry table — index = scale·12 + pitch class, value =
// the nearest degree of that scale — so the snap is one Select.kr over
// constants and costs nothing per block. No global key: [RN] takes the scale
// either from the project Key Signature or from Local Key / Local Scale, and
// F2 has no engine-side key signature at all, so the card's own pair is the
// only source (§1.7).
~f2SmpScales = #[
	[0, 2, 4, 5, 7, 9, 11],         // MAJ
	[0, 2, 3, 5, 7, 8, 10],         // MIN
	[0, 2, 3, 5, 7, 9, 10],         // DOR
	[0, 1, 3, 5, 7, 8, 10],         // PHR
	[0, 2, 4, 6, 7, 9, 11],         // LYD
	[0, 2, 4, 5, 7, 9, 10],         // MIX
	[0, 1, 3, 5, 6, 8, 10],         // LOC
	[0, 2, 4, 7, 9]                 // PENT
];
~f2SmpScaleTab = ~f2SmpScales.collect { |sc|
	// the octave is a degree of every mode, so a pitch class just under it snaps
	// UP instead of falling back to the root eleven semitones away
	Array.fill(12, { |pc| (sc ++ [12]).minItem { |d| (d - pc).abs } })
}.flat;

// mode + parameters + the raw pass + the card's manual markers → the boundary
// list. `par`: (slices:, beats:, bpm:, dur:, frames:, onsetSens:, pitchSens:).
// A mode whose analysis has not landed yet falls back to the divisions grid —
// correct arithmetic, just not onset-aligned (§6), and the card marks it
// provisional.
~f2SmpSliceTable = { |mode, par, raw, manual|
	var m = (mode ? 'div').asSymbol;
	var p = par ? ();
	var nMax = (topEnvironment[\f2SmpSliceMax] ? 64);
	var frames = ((p[\frames] ? 0)).asInteger;
	var dur = ((p[\dur] ? 1)).max(0.001);
	var ready = raw.notNil and: { (raw[\state] ? \ready) == \ready };
	var interior;
	interior = case
		{ (m == 'onsets') and: { ready } } {
			topEnvironment[\f2SmpOnsetBounds].(raw, p[\onsetSens], nMax)
		}
		{ (m == 'pitch') and: { ready } } {
			topEnvironment[\f2SmpPitchBounds].(raw, p[\pitchSens])
		}
		{ m == 'manual' } { [] }                        // [RN] starts blank
		{ (m == 'beats') and: { (p[\bpm] ? 0) > 0 } } {
			// [RN] «uses and displays the detected BPM of the file»
			var step = ((p[\beats] ? 0.25).max(0.001) * 60 / (p[\bpm]).clip(20, 300)) / dur;
			var n = (1 / step.max(1e-6)).ceil.asInteger.clip(1, nMax * 4);
			Array.fill(n - 1, { |i| (i + 1) * step })
		}
		{ true } {
			// `div`, and the provisional grid of every mode still waiting (§6)
			var n = (p[\slices] ? 8).asInteger.clip(1, nMax);
			Array.fill(n - 1, { |i| (i + 1) / n })
		};
	topEnvironment[\f2SmpSeal].(interior ++ (manual ? []), frames, nMax)
};

// The offline pass itself (§6): a private NRT scsynth render over the file, so
// nothing of this touches the running server's audio path (CARDS.md §12).
// Onsets and Pitch are the same UGens sc/nrt/analyze.scd proved offline; they
// are recorded at CONTROL rate (one frame per block — 1.45 ms at 44.1 kHz), so
// the analysis file is a few thousand frames whatever the sample's length.
//   ch 0  onset trigger      ch 2  pitch confidence
//   ch 1  detected pitch     ch 3  amplitude — the onset STRENGTH the
//                                   sensitivity filter ranks by, and what puts
//                                   the boundary back ON the transient
~f2SmpAnalysisDir = ~f2SmpAnalysisDir ? (Platform.defaultTempDir +/+ "f2smpan");
// The detector runs at its most permissive: a 0.15 rcomplex threshold finds
// every transient of a dense sixteenth grid, and `onsetSens` prunes that ONE
// result afterwards ([RN]'s 100 % = all onsets). The tracker runs fast and
// short-medianed (400 Hz, 3 frames) so a pitch step is reported ~30 ms after it
// happens instead of ~60 — the rest is compensated by ~f2SmpPitchMinHz below.
~f2SmpPitchMinHz = 60;
~f2SmpAnalyzeDef = SynthDef(\f2SmpAnalyze, { |buf = 0, dst = 1|
	var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf), doneAction: 0);
	var ons = Onsets.kr(FFT(LocalBuf(512), sig), 0.15, \rcomplex);
	var pch = Pitch.kr(sig, minFreq: topEnvironment[\f2SmpPitchMinHz], execFreq: 400,
		median: 3, ampThreshold: 0.02);
	RecordBuf.kr([ons, pch[0], pch[1], Amplitude.kr(sig, 0.001, 0.05)], dst, loop: 0);
});
// The onset detector reports at the FFT hop that saw the transient, up to a
// window late. The amplitude channel puts it back: walk the envelope backwards
// from the reported frame while it is still above a fifth of the hit's peak —
// a slice has to START on the transient, not just after it.
~f2SmpOnsetRefine = { |amp, i, n|
	var hi = (i + 8).min(n - 1);
	var peak = 0, j = i;
	((i - 1).max(0)..hi).do { |q| if (amp[q] > peak) { peak = amp[q] } };
	while { (j > 0) and: { amp[j - 1] > (peak * 0.2) } and: { (i - j) < 16 } } { j = j - 1 };
	[j, peak]
};
// Onset spacing → the file tempo ([RN] Automatic BPM Detection). The median
// gap is whatever subdivision the material runs on, so the implied rate is
// folded by octaves into a musical range — 0.125 s between hits is 480, which
// folds to 120 (`~`: [RN] states the feature, not the method, §8 b).
~f2SmpDetectBpm = { |onsets, dur|
	var t = (onsets ? []).collect { |e| e[0] * dur };
	var gaps = if (t.size > 3) { (1..(t.size - 1)).collect { |i| t[i] - t[i - 1] } } { [] };
	var med, bpm = 120;
	if (gaps.size > 2) {
		med = gaps.sort[(gaps.size / 2).asInteger];
		if (med > 0.001) {
			bpm = 60 / med;
			while { bpm > 160 } { bpm = bpm / 2 };
			while { bpm < 60 } { bpm = bpm * 2 };
		};
	};
	bpm.clip(20, 300)
};
// path → (onsets: [[pos, strength]…], pitchHz:, pitchOk:, bpm:, avgHz:, dur:,
// frames:, hop:, minGap:), handed to `done`. nil on any failure — the caller
// keeps the provisional divisions grid and the card never goes silent (§6).
~f2SmpAnalyzeFile = { |path, done|
	var dir = topEnvironment[\f2SmpAnalysisDir].asString;
	var sf = SoundFile.openRead(path.asString);
	var act = done ? { };
	if (sf.isNil) {
		topEnvironment[\f2UnitWarnOnce].(("smp_an_open_" ++ path).asSymbol,
			"⚠ [f2 smp] the slicing analysis cannot open % — the divisions grid stands".format(path));
		act.value(nil);
	} {
		var sr = sf.sampleRate.asInteger.max(1);
		var frames = sf.numFrames.asInteger.max(1);
		var dur = frames / sr;
		var blk = 64;
		var nCtl = (frames / blk).ceil.asInteger + 4;
		var stem = "f2smpan_" ++ (path.asString.basename.splitext.first.select { |c|
			c.isAlphaNum }) ++ "_" ++ UniqueID.next;
		var anP = dir +/+ (stem ++ ".wav");
		var oscP = dir +/+ (stem ++ ".osc");
		var rndP = dir +/+ (stem ++ "-nrt.wav");
		var score;
		sf.close;
		File.mkdir(dir);
		// one message per bundle time: a def and a file read in one bundle add up
		// past what the NRT reader takes in one go (the note in sc/nrt/README.md)
		score = Score([
			[0.0,  ['/d_recv', topEnvironment[\f2SmpAnalyzeDef].asBytes]],
			[0.001, ['/b_allocReadChannel', 0, path.asString, 0, 0, 0]],   // MONO, as ~loadSamples
			[0.002, ['/b_alloc', 1, nCtl, 4]],
			[0.01, ['/s_new', 'f2SmpAnalyze', 1000, 0, 0, 'buf', 0, 'dst', 1]],
			[dur + 0.05, ['/b_write', 1, anP, "wav", "float"]],
			[dur + 0.10, [0]]
		]);
		score.recordNRT(oscP, rndP, nil, sr, "WAV", "int16",
			options: ServerOptions.new.numOutputBusChannels_(1).numInputBusChannels_(0)
				.blockSize_(blk).sampleRate_(sr),
			action: {
				var res = nil;
				try {
					var af = SoundFile.openRead(anP);
					if (af.notNil) {
						var n = af.numFrames.asInteger;
						var d = FloatArray.newClear(n * 4);
						var amp = FloatArray.newClear(n);
						var hz = FloatArray.newClear(n);
						var ok = FloatArray.newClear(n);
						var ons = [], seen = -1, conf;
						af.readData(d); af.close;
						n.do { |i|
							hz[i] = d[(i * 4) + 1]; ok[i] = d[(i * 4) + 2]; amp[i] = d[(i * 4) + 3];
						};
						n.do { |i|
							if (d[i * 4] > 0) {
								var r = topEnvironment[\f2SmpOnsetRefine].(amp, i, n);
								if (r[0] > seen) {
									seen = r[0];
									ons = ons.add([(r[0] * blk / frames).clip(0, 1), r[1]]);
								};
							};
						};
						conf = (0..(n - 1)).select { |i| (ok[i] > 0.5) and: { hz[i] > 20 } }
							.collect { |i| hz[i] };
						res = (
							state: \ready, dur: dur, frames: frames, sr: sr, hop: blk / frames,
							minGap: (0.04 / dur).min(0.25),
							// two periods of the lowest tracked frequency: what the pitch
							// tracker has to hear before it can report a change at all
							pitchLag: ((2 / topEnvironment[\f2SmpPitchMinHz]) / dur).min(0.2),
							amp: amp, ampPeak: if (n > 0) { amp.maxItem } { 0 },
							onsets: ons, pitchHz: hz, pitchOk: ok,
							avgHz: if (conf.isEmpty) { 0 } { conf.sort[(conf.size / 2).asInteger] },
							bpm: topEnvironment[\f2SmpDetectBpm].(ons, dur)
						);
					};
				} { |e| ("⚠ [f2 smp] the slicing analysis of % failed: %".format(path, e.errorString)).postln };
				[anP, oscP, rndP].do { |f| try { File.delete(f) } };
				if (res.notNil) {
					("✓ [f2 smp] analysed % — % onsets, % bpm, avg % Hz".format(
						path.asString.basename, res[\onsets].size, res[\bpm].round(0.1),
						res[\avgHz].round(0.1))).postln;
				};
				act.value(res);
			});
	};
};

// ── the resource entry (§6) ────────────────────────────────────────────────
// One entry per analysis KEY = the file plus every resource opt that changes
// the grid. The entry owns the slice-table buffer for the life of the sample:
// re-analysis rewrites it in place, so a bufnum handed to a voice stays valid.
// A units reload gets fresh buffers (the allocator may have been reset); the
// raw passes survive it — they describe FILES, not the server.
~f2SmpAnalysis !? { |old| old.do { |e| e[\bufObj] !? { |b| try { b.free } } } };
~f2SmpAnalysis = IdentityDictionary.new;
~f2SmpRaw      = ~f2SmpRaw ? IdentityDictionary.new;      // path → the offline pass
// The cache is BOUNDED, least-recently-used first. Every entry owns one server
// buffer and the key carries the live-editable resource opts — `cuts` above all
// — so ONE drag of a slice marker mints a fresh key on every pointer move.
// Unbounded, ordinary editing walks the server's buffer allocator to its end;
// the next f2units load then cannot allocate the wavetable banks polysynthU and
// samplerU depend on, and those two units go silent. The tail is the most
// recently touched entry, so a grid a sounding voice is reading stays in.
~f2SmpAnalysisMax = 48;
~f2SmpAnalysisLRU = [];
~f2SmpAnalysisTouch = { |key|
	var cache = topEnvironment[\f2SmpAnalysis] ? IdentityDictionary.new;
	var max   = (topEnvironment[\f2SmpAnalysisMax] ? 48).max(1);
	var lru   = (topEnvironment[\f2SmpAnalysisLRU] ? []).reject { |k| k == key } ++ [key];
	while { lru.size > max } {
		var drop = lru.removeAt(0);
		cache[drop] !? { |e| e[\bufObj] !? { |b| try { b.free } } };
		cache.removeAt(drop);
	};
	topEnvironment[\f2SmpAnalysisLRU] = lru;
	nil
};
// ~loadSamples calls this when the sample buffers themselves are replaced
~f2SmpForget = {
	(topEnvironment[\f2SmpAnalysis] ? IdentityDictionary.new).do { |e|
		e[\bufObj] !? { |b| try { b.free } };
	};
	// §4 the pitch curves go with them: they are keyed on the FILE, and the
	// buffers behind those files are what is being replaced
	(topEnvironment[\f2SmpPitchBufs] ? IdentityDictionary.new).do { |b| try { b.free } };
	topEnvironment[\f2SmpPitchBufs] = IdentityDictionary.new;
	// §6 and so do the two spectral artefacts, keyed on the same file: the onset
	// table per (sample, onsetSens) and the FFT frames per (sample, qual). They
	// are the biggest buffers the unit owns — a 10 s sample at `ultra` is
	// 15.7 MB — so a reload that forgot them would leak a file's worth of
	// analysis every time the watcher fired
	(topEnvironment[\f2SmpOnsetBufs] ? IdentityDictionary.new).do { |b| try { b.free } };
	topEnvironment[\f2SmpOnsetBufs] = IdentityDictionary.new;
	(topEnvironment[\f2SmpFftBufs] ? IdentityDictionary.new).do { |e|
		e[\bufObj] !? { |b| try { b.free } };
	};
	topEnvironment[\f2SmpFftBufs] = IdentityDictionary.new;
	topEnvironment[\f2SmpAnalysis] = IdentityDictionary.new;
	topEnvironment[\f2SmpAnalysisLRU] = [];
	topEnvironment[\f2SmpRaw] = IdentityDictionary.new;
	nil
};
// §6 the analysis is ASYNCHRONOUS — it is kicked at the first spawn that needs
// the file and lands seconds later, long after the context the front is holding
// was exported. So a landed pass re-exports the context: `ctx.sampleAnalysis`
// then carries the onsets, the pitch cuts and the detected tempo, and the next
// context refresh on the front replaces the provisional grid with the real one.
// Coalesced: several files landing together cost ONE export, off the event
// thread, and a missing ~exportContext (an f2units loaded on its own, the NRT
// checks) is simply nothing to do.
~f2SmpPublish = {
	if ((topEnvironment[\f2SmpCtxDue] ? false).not) {
		topEnvironment[\f2SmpCtxDue] = true;
		SystemClock.sched(0.3, {
			topEnvironment[\f2SmpCtxDue] = false;
			topEnvironment[\exportContext] !? { |f|
				try { f.value } { |e|
					("⚠ [f2 smp] the context re-export after an analysis failed: %"
						.format(e.errorString)).postln;
				};
			};
			nil
		});
	};
	nil
};
// (re)compute the entry's table and push it into ITS buffer: [n, b0 … bn]
~f2SmpFill = { |ent, raw|
	var bounds = topEnvironment[\f2SmpSliceTable].(ent[\slicing], (
		slices: ent[\slices], beats: ent[\beats], dur: ent[\dur], frames: ent[\frames],
		onsetSens: ent[\onsetSens], pitchSens: ent[\pitchSens],
		bpm: if (ent[\bpmMode] == 'manual') { ent[\manBpm] } { (raw !? { raw[\bpm] }) ? 0 }
	), raw, ent[\manual]);
	ent[\bounds] = bounds;
	ent[\n] = bounds.size - 1;
	ent[\bpm] = if (ent[\bpmMode] == 'manual') { ent[\manBpm] } { ((raw !? { raw[\bpm] }) ? 120) };
	ent[\avgHz] = ((raw !? { raw[\avgHz] }) ? 0);
	// the table as the graph reads it, kept on the entry: ~f2SmpRes hands the
	// FIRST one to /b_alloc as a completion message (the buffer does not exist
	// yet at that point), every later re-analysis writes it straight in
	ent[\table] = ([bounds.size - 1] ++ bounds).collect(_.asFloat);
	ent[\bufObj] !? { |b| b.setn(0, ent[\table]) };
	ent
};
// kick (or join) the offline pass this entry is waiting for
~f2SmpKick = { |ent|
	var path = ent[\path];
	var raws = topEnvironment[\f2SmpRaw];
	var r = if (path.isNil) { nil } { raws[path.asSymbol] };
	if (path.isNil) { ent[\state] = \failed } {
		case
			{ r.notNil and: { r[\state] == \ready } } {
				topEnvironment[\f2SmpFill].(ent, r); ent[\state] = \ready;
			}
			{ r.notNil and: { r[\state] == \pending } } { r[\waiting] = r[\waiting].add(ent) }
			{ r.notNil and: { r[\state] == \failed } } { ent[\state] = \failed }
			{ true } {
				r = (state: \pending, waiting: [ent]);
				raws[path.asSymbol] = r;
				// off the event thread: a graph build on a note is a CPU spike, an
				// NRT render on one is a stall (the ~f2UnitDef rule, §3)
				SystemClock.sched(0, {
					topEnvironment[\f2SmpAnalyzeFile].(path, { |res|
						var w = r[\waiting] ? [];
						if (res.isNil) { r[\state] = \failed } {
							res.keysValuesDo { |k, v| r[k] = v };
							r[\state] = \ready;
						};
						r[\waiting] = [];
						w.do { |e|
							if (r[\state] == \ready) { topEnvironment[\f2SmpFill].(e, r); e[\state] = \ready }
							{ e[\state] = \failed };
						};
						topEnvironment[\f2SmpPublish].value;   // §6 the front's copy of the analysis
					});
					nil
				});
			};
	};
	ent
};
// §6 the resolver \f2voice calls at spawn: the resource opts of a samplerU card
// (`slicing slices beatLen onsetSens pitchSens bpm`, none of which changes a
// graph) → the entry that owns `sliceBuf`. `sbuf` is the sample buffer the card
// already resolved through ~f2SmpBuf, `bpmManual` the card's own `smpBpm` knob,
// which is what `bpm: manual` means ([RN] «allows setting the file tempo
// manually») — a live control cannot key an analysis, so it keys the ENTRY.
// §4 `pitchBuf` is resolved here as well — the card asks for it through the
// GRAPH opt `rootMode: analyzed` (and `slicing: pitch` needs the same pass), so
// the raw analysis is kicked for either. It is keyed on the FILE, not on this
// entry's key, so a card that turns the analyzed root on picks up a curve an
// earlier card already paid for, and an entry minted a moment ago by a marker
// drag does not re-analyse.
// §7 `onsetBuf` and `fftBuf` resolve the same way under `play: spectral`, and
// they are keyed on the file too — the onset table per (sample, onsetSens), the
// FFT frames per (sample, qual) — so two spectral cards on one file share both.
~f2SmpRes = { |opts, sbuf, bpmManual|
	var o = opts ? ();
	var gets = { |k, d| var v = (o[k] ? o[k.asString]); if (v.isNil) { d } { v.asString } };
	var slicing = gets.(\slicing, "div").asSymbol;
	var slices  = gets.(\slices, "8").asInteger.clip(1, topEnvironment[\f2SmpSliceMax]);
	var beatLen = gets.(\beatLen, "1/16").asSymbol;
	var oSens   = gets.(\onsetSens, "100").asFloat.clip(0, 100);
	var pSens   = gets.(\pitchSens, "70").asFloat.clip(0, 100);
	var bpmMode = gets.(\bpm, "auto").asSymbol;
	// §7 SPECTRAL asks for the two artefacts nothing else reads. `play` and
	// `qual` are GRAPH opts — they key no entry of their own, but they are in the
	// card's opts here exactly as `rootMode` is, and the buffers they name are
	// keyed on the FILE, so asking for them costs no extra entry.
	var spectral = gets.(\play, "repitch").asSymbol == 'spectral';
	var qual    = gets.(\qual, "medium").asSymbol;
	// §4 the pitch curve: wanted by the analyzed root, by pitch slicing — and by
	// REHARM, which reads the file's own pitch AT THE HEAD off the same curve to
	// anchor the harmonic bend (§1.7). Without it the bend's split falls back to
	// 20 Hz, collapses onto the bottom two bins and moves the fundamental too.
	var wantPitch = (gets.(\rootMode, "manual").asSymbol == 'analyzed')
		or: { gets.(\slicing, "div").asSymbol == 'pitch' }
		or: { spectral };
	var manBpm  = ((bpmManual ? 120).asFloat).clip(20, 300);
	// §1.8 the card's manual boundaries, decoded from the `cuts` opt. They change
	// no graph either — they are merged into whatever the mode computed (§6) — so
	// they key the ENTRY like every other resource opt, in their canonical form:
	// two spellings of the same list must not build two tables.
	var manual  = topEnvironment[\f2SmpCuts].(gets.(\cuts, ""));
	var cutKey  = manual.collect { |x| (x * (topEnvironment[\f2SmpCutScale] ? 10000)).round.asInteger }.join("_");
	var path    = (sbuf !? { |b| b.tryPerform(\path) });
	var frames  = ((sbuf !? { |b| b.tryPerform(\numFrames) }) ? 0).asInteger;
	var sr      = ((sbuf !? { |b| b.tryPerform(\sampleRate) }) ? 44100);
	var cache   = topEnvironment[\f2SmpAnalysis];
	var key, ent, needsRaw;
	// a Buffer that has not answered /b_query yet has no frame count — the file
	// header has, and `beats` needs the duration to lay its grid out
	if (frames < 1 and: { path.notNil }) {
		SoundFile.openRead(path.asString) !? { |f|
			frames = f.numFrames.asInteger; sr = f.sampleRate; f.close;
		};
	};
	// §6's key, in its order. `qual` is the one GRAPH opt in it: the entry
	// carries the bufnum of the FFT analysis and that analysis is per (sample,
	// quality), so two cards at two qualities on one file must not share the
	// entry whose `fftBuf` field they would take turns overwriting.
	key = ((path ? "-").asString ++ "|" ++ slicing ++ "|" ++ slices ++ "|" ++ beatLen
		++ "|" ++ oSens ++ "|" ++ pSens ++ "|" ++ bpmMode
		++ if (bpmMode == 'manual') { "|" ++ manBpm } { "" }
		++ "|" ++ cutKey ++ "|" ++ qual).asSymbol;
	// mark this key as the most recently used FIRST: the eviction it triggers
	// frees buffers before the new entry asks the allocator for one
	topEnvironment[\f2SmpAnalysisTouch].value(key);
	ent = cache[key];
	if (ent.isNil) {
		needsRaw = #['onsets', 'pitch'].includes(slicing)
			or: { (slicing == 'beats') and: { bpmMode == 'auto' } }
			or: { wantPitch };                     // §4 the analyzed root needs the same pass
		ent = (
			key: key, path: path, frames: frames, sr: sr,
			dur: if (frames > 0) { frames / sr.max(1) } { 1 },
			slicing: slicing, slices: slices,
			beats: (topEnvironment[\f2SmpBeatLen][beatLen] ? 0.25),
			onsetSens: oSens, pitchSens: pSens, bpmMode: bpmMode, manBpm: manBpm,
			manual: manual,                     // the card's marker list, from the `cuts` opt (§1.8)
			bpm: 120, avgHz: 0, n: 1, state: \pending,
			sliceBuf: -1, onsetBuf: -1, pitchBuf: -1, fftBuf: -1
		);
		cache[key] = ent;
		// the provisional grid FIRST, so the very first note already slices (§6).
		// It is computed before the buffer exists on purpose: it then travels as
		// /b_alloc's completion message. A /b_setn sent straight after /b_alloc is
		// executed on the realtime thread while the allocation is still queued on
		// the non-realtime one, so the server drops it (see ~f2SmpWins) — the table
		// stayed all zeros on a live server, its header said 0 slices, and a sliced
		// samplerU card had no grid to play.
		topEnvironment[\f2SmpFill].(ent, nil);
		// the table buffer is allocated ONCE, at the maximum size the contract
		// allows: every later fill is a /b_setn into the same bufnum (§6)
		try {
			var tbl = ent[\table];
			var b = Buffer.alloc(s, topEnvironment[\f2SmpSliceMax] + 2, 1,
				{ |bf| bf.setnMsg(0, tbl) });
			ent[\bufObj] = b; ent[\sliceBuf] = b.bufnum;
		} { |e| ("⚠ [f2 smp] the slice table could not be allocated: %".format(e.errorString)).postln };
		if (needsRaw) { topEnvironment[\f2SmpKick].(ent) } { ent[\state] = \ready };
	};
	// §4 the curve, EVERY call: the entry may predate the card that wants it
	// (rootMode is a graph opt and keys no entry), and the pass it needs may
	// only have landed after the entry was built. Nothing yet ⇒ pitchBuf stays
	// -1 and the graph falls back to the manual root until the next note.
	if (wantPitch) {
		var r = (topEnvironment[\f2SmpRaw] ? IdentityDictionary.new)[(path ? "-").asSymbol];
		if (r.notNil and: { r[\state] == \ready }) {
			ent[\pitchBuf] = ((topEnvironment[\f2SmpPitchBufAt].(path, r) !? { |b| b.bufnum }) ? -1);
			// §1.7 Preserve Onsets reads the onset table the slicer already has,
			// in the layout the GRAPH needs (§6 — the list block plus the dense
			// proximity curve). Same pass, same sensitivity filter, one buffer.
			if (spectral) {
				ent[\onsetBuf] = ((topEnvironment[\f2SmpOnsetBufAt].(path, oSens, r, ent[\dur])
					!? { |b| b.bufnum }) ? -1);
			};
		} {
			// the entry existed already (no kick above) but its file was never
			// analysed: ask for the pass now, the next note gets the curve
			if (r.isNil) { topEnvironment[\f2SmpKick].(ent) };
		};
	};
	// §6 the FFT frames, EVERY call for the same reason the curve is: `qual` and
	// `play` are graph opts, the record pass is asynchronous, and a spectral
	// voice spawned before it lands reads -1 and stays silent for that note
	// rather than erroring. The first call kicks the pass.
	if (spectral) {
		ent[\fftBuf] = topEnvironment[\f2SmpFftBufAt].(path, qual, ent[\dur],
			(sbuf !? { |b| b.tryPerform(\bufnum) }));
		if (ent[\fftBuf] < 0) {
			topEnvironment[\f2UnitWarnOnce].(("smp_fftpending_" ++ key).asSymbol,
				"[f2 smp] the % analysis of % is not ready — spectral voices are silent until it lands".format(
					qual, (path ? "no file").asString.basename));
		};
	};
	ent
};
// §6 THE FRONT'S COPY of the analysis: `ctx.sampleAnalysis`, built here beside
// the pass that produces it and published by ~exportContext (f2dsl §6d). One
// entry per SAMPLE — the analysis describes a FILE, like the sample buffer
// itself — in the units the card draws in: positions in 0…1 of the WHOLE file,
// the tempo in bpm, the length in seconds.
//   state          \ready | \pending | \failed — the pass is asynchronous
//                  (kicked at the first spawn that needs the file), so the card
//                  knows whether a grid is worth waiting for
//   onsets         every transient the detector found, ascending
//   onsetStrength  the strength of each, 1.0 = the loudest in the file. It is
//                  what `onsetSens` filters on ([RN] 100 % = all onsets), so the
//                  CARD can cut the same grid the engine cuts at any sensitivity
//   pitchCuts      the derived cut positions of `slicing: pitch`, and
//   pitchSens      the sensitivity they were derived at: the walk over the pitch
//                  curve is stateful and cannot be re-filtered from its result,
//                  so a card set to another sensitivity keeps its own grid
//   bpm, dur       the detected tempo of the file and its length
// The pitch curve itself and the amplitude envelope stay here: thousands of
// frames per file, and nothing on the front reads them.
~f2SmpCtxOnsets = 512;              // one long file must not bloat the context
~f2SmpCtxPitchSens = 70;            // ~f2UnitOpts[\samplerU].pitchSens.def
~f2SmpCtxPitch = 256;               // §4 points of the pitch curve the card draws
~f2SmpAnalysisCtx = { |samples|
	var raws = topEnvironment[\f2SmpRaw] ? IdentityDictionary.new;
	var pSens = topEnvironment[\f2SmpCtxPitchSens] ? 70;
	var nOns = topEnvironment[\f2SmpCtxOnsets] ? 512;
	var out = ();
	(samples ? IdentityDictionary.new).keysValuesDo { |k, v|
		var path = if (v.isKindOf(Buffer)) { v.path } { nil };
		var r = path !? { raws[path.asSymbol] };
		var st = (r !? { |q| q[\state] }) ? \pending;
		if (r.notNil) {
			var e = (state: st.asString);
			if (st == \ready) {
				var ons = (r[\onsets] ? []);
				var top = if (ons.isEmpty) { 0 } { ons.maxItem { |q| q[1] }[1] };
				// past the cap the strongest onsets survive, as the sensitivity
				// filter itself ranks them — then back into file order
				var keep = if (ons.size > nOns) {
					ons.sort { |a, b| a[1] > b[1] }.keep(nOns).sort { |a, b| a[0] < b[0] }
				} { ons };
				e[\dur] = (r[\dur] ? 0).asFloat.round(0.00001);
				e[\bpm] = (r[\bpm] ? 0).asFloat.round(0.01);
				e[\onsets] = keep.collect { |q| q[0].asFloat.clip(0, 1).round(0.00001) };
				e[\onsetStrength] = keep.collect { |q|
					if (top > 0) { (q[1] / top).asFloat.clip(0, 1).round(0.0001) } { 1.0 }
				};
				e[\pitchCuts] = ((topEnvironment[\f2SmpPitchBounds] !? { |f| f.(r, pSens) }) ? [])
					.collect { |x| x.asFloat.clip(0, 1).round(0.00001) };
				e[\pitchSens] = pSens;
				// §4 the DETECTED PITCH CURVE the card draws in orange under an
				// analyzed root, and the average the one-shot root action reads.
				// Thinned to ~f2SmpCtxPitch points — this rides in the context
				// JSON, once per sample, and the plot is a few hundred pixels
				// wide — from the SAME array the engine's buffer is built out of,
				// so the drawing and the sound cannot disagree.
				(topEnvironment[\f2SmpPitchCurve] !? { |f| f.(r) }) !? { |c|
					var n = (topEnvironment[\f2SmpCtxPitch] ? 256).clip(16, 4096);
					var thin = if (c.size <= n) { c }
						{ Array.fill(n, { |i| c[((i / (n - 1)) * (c.size - 1)).round.asInteger] }) };
					e[\pitchHz] = thin.collect { |f| f.asFloat.round(0.01) };
					e[\avgHz] = (r[\avgHz] ? 0).asFloat.round(0.01);
				};
			};
			out[k.asString.asSymbol] = e;
		};
	};
	out
};

// console: what the analysis knows about a card's opts right now
~f2SmpInfo = { |opts, sbuf|
	var e = topEnvironment[\f2SmpRes].(opts, sbuf);
	("[f2 smp] % — % (%), % slices, bpm %, table buf %".format(
		(e[\path] ? "no file").asString.basename, e[\slicing], e[\state], e[\n],
		e[\bpm].round(0.1), e[\sliceBuf])).postln;
	(e[\bounds] ? []).collect { |x| x.round(0.0001) }.postln;
	e
};

// §port-who the node of a pooled voice through f2dsl's accessor (a stack /
// strip / copies proxy answers its group); before f2dsl is loaded, or for a
// plain Synth, the node's own id. Never nil for a live proxy.
~f2PortVNode = { |sy|
	var f = topEnvironment[\f2VNode];
	if (f.notNil) { f.value(sy) } { sy.tryPerform(\nodeID) }
};
// §port-who one-line diagnosis: who touches a port right now. Console:
//   ~f2PortWho.(\y2)
// Prints the port's buses/commit, every ~f2ReuseCfg entry routed to it, and
// every live voice pool whose fingerprint mentions it (node IDs included).
~f2PortWho = { |name|
	var key = name.asSymbol, ks = key.asString;
	var e = topEnvironment[\f2Ports][key];
	("[f2 port-who] % → %".format(key,
		e !? { "w=% r=% wv=% commit=%".format(e[\bus].index,
			(e[\rbus] ? e[\bus]).index, e[\wv], e[\commit].notNil) } ? "NOT ENSURED")).postln;
	(topEnvironment[\f2ReuseCfg] ? IdentityDictionary.new).keysValuesDo { |dk, c|
		var po = c[\portOut], pin = c[\portIns];
		if ((po == key) or: { pin.notNil and: { pin.values.asArray.includes(key) } }) {
			("  cfg %: portOut=% portIns=%".format(dk, po, pin)).postln;
		};
	};
	// §stack a pooled voice may be a PROXY (stack/strip/copies: an Event whose
	// node is its group) — ~f2VNode (f2dsl) is the one accessor that knows
	(topEnvironment[\f2Voices] ? IdentityDictionary.new).keysValuesDo { |pk, pool|
		if ((pool[\cfgSig] ? "").asString.contains(ks)) {
			("  pool %: nodes % | sig %".format(pk,
				pool[\synths].collect { |sy| topEnvironment[\f2PortVNode].value(sy) }, pool[\cfgSig])).postln;
		};
	};
	nil
};

// §port-who instant mute: free every pool touching the port (they respawn with
// the current cfg on their next trigger). Console: ~f2PortHush.(\y2)
// §stack the node to free is ~f2VNode's answer (the GROUP of a stack/strip/copies
// proxy — an Event has no nodeID, and `tryPerform(\nodeID)` on it was nil for every
// composite pool: the hush freed nothing and the pool entry vanished with its nodes
// still sounding, orphaned). A plain Synth answers its own nodeID either way.
~f2PortHush = { |name|
	var ks = name.asString;
	var vs = topEnvironment[\f2Voices] ? IdentityDictionary.new;
	vs.keys.asArray.do { |pk|
		var pool = vs[pk];
		if ((pool[\cfgSig] ? "").asString.contains(ks)) {
			pool[\synths].do { |sy| topEnvironment[\f2PortVNode].value(sy) !? { |nid|
				s.sendBundle(nil, [\error, 0], [\n_free, nid], [\error, 1]) } };
			vs.removeAt(pk);
			("[f2 port-hush] freed pool %".format(pk)).postln;
		};
	};
	nil
};

// ── §synth-mod unit telemetry → the core's `sc:*` channels ────────────────
// A unit sends SendReply '/f2_chan' [value] with replyID=telId (the compiler puts telId
// in cfg, and voice 0 gets the argument). ~f2TelMap[telId] = "sc:<name>" is written by
// the compiled code at deploy time; the OSCdef below forwards to the core (whose address
// is ~f2CoreAddr from the hello — see f2_remote_eval). The core NaN-guards it, puts it in
// the store and clears the channel on a TTL (0.5s without an update = the writer died), so
// nothing sticks.
~f2TelMap = ~f2TelMap ? IdentityDictionary.new;
OSCdef(\f2chanFwd, { |msg|
	var id = msg[2].asInteger;
	var val = msg[3];
	var map = topEnvironment[\f2TelMap];   // not ~: the callback's environment is not guaranteed
	var name = map !? { map[id] };
	var core = topEnvironment[\f2CoreAddr];
	if (name.notNil and: { core.notNil }) {
		core.sendMsg('/f2_chan', name.asString, val.asFloat);
	};
}, '/f2_chan', s.addr);

// ── §smp playhead telemetry (SAMPLER.md §5) → the cell-telemetry socket ────
// The mirror of \f2chanFwd for the second reply a samplerU voice sends:
// '/f2_head' [vi, ci, pos, span, mode] with replyID = telId, from EVERY voice
// of EVERY samplerU card (\f2voice hands telId, vi and ci to a unit that
// declares `vi`, §3.3). The reply id resolves to the preset alone, so `ci` —
// the card's index in the strip — is what keeps two sampler cards of one preset
// apart on the front (§5).
// telId → dk through the same ~f2TelMap the compiler writes at deploy; the
// packet goes to ~f2CellAddr (127.0.0.1:57130, f2dsl) — the socket the /f2_cell
// telemetry already uses, so the front listens on one port for both. The map
// holds the CHANNEL name ("sc:<dk>"); the wire carries the bare dk, which is
// what the front keys its heads by (CARDS.md §8). Same defensive style as the
// forwarder above: topEnvironment, never ~ (the callback environment is not
// guaranteed), and a missing map or address means silence, never an error.
OSCdef(\f2headFwd, { |msg|
	var id = msg[2].asInteger;
	var map = topEnvironment[\f2TelMap];
	var name = map !? { map[id] };
	var addr = topEnvironment[\f2CellAddr];
	if (name.notNil and: { addr.notNil }) {
		var dk = name.asString;
		if (dk.beginsWith("sc:")) { dk = dk.drop(3) };
		// §ptrs everything past the five fixed values is the variant's extra read
		// pointers — a length that depends on the mode, so it is forwarded as it
		// came instead of being counted here
		addr.sendMsg('/f2_head', dk, msg[3].asInteger, msg[4].asInteger,
			msg[5].asFloat, msg[6].asFloat, msg[7].asInteger,
			*(msg[8..].collect(_.asFloat)));
	};
}, '/f2_head', s.addr);

// ── the units ─────────────────────────────────────────────────────────────
// Common to all: env is gated DIRECTLY by the \gate control (EnvGen releases on the gate→0
// fall), doneAction: i_free (reuse sets 0 → the voice lives on; outside reuse the default 2
// frees it). Re-attack, legato and hold are done by cycling \gate in \f2voice (0→1→0 per
// cell), NOT through t_trig: a composite `gate + Trig` confused EnvGen's fall detection and
// the note stuck. The output is always LeakDC→Sanitize; a port input is
// InFeedback.ar(idx.max(0), 2) * (idx >= 0).
// §cards processors add `chainIn = -1` (stage bus, ~f2ChainIn = In.ar, no delay)
// summed into their primary port BEFORE ~f2CondIn; sources are untouched. In a
// strip (chainIn >= 0) the processor's env is forced to 1 — PASS-THROUGH, see
// the contract at the top: `var env = Select.kr(chainIn >= 0, [envG, 1]);`.

// FM operator / carrier: a tonal source with an audio-rate FM input (the fmIn port).
SynthDef(\fmOscU, { |out = 0, gate = 0, t_trig = 0, amp = 0.2, i_free = 2, tel_bus = 0,
	freq = 220, ratio = 1, fmIn = -1, fmDepth = 0, inGain = 1, inDamp = 0, inSat = 0,
	atk = 0.01, dec = 0.1, sus = 0.8, rel = 0.4, curve = -4, telId = 0|
	var g   = gate;
	var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var fm  = ~f2CondIn.(InFeedback.ar(fmIn.max(0), 2).sum * 0.5, inGain, inDamp, inSat) * (fmIn >= 0);
	var sig = SinOsc.ar((freq * ratio) + (fm * fmDepth * freq));
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(sig * env * amp)) ! 2);
}).add;

// PM operator: phase modulation (the DX classic) — the input goes into phase, not frequency.
SynthDef(\pmOscU, { |out = 0, gate = 0, t_trig = 0, amp = 0.2, i_free = 2, tel_bus = 0,
	freq = 220, ratio = 1, pmIn = -1, pmDepth = 0, inGain = 1, inDamp = 0, inSat = 0,
	atk = 0.01, dec = 0.1, sus = 0.8, rel = 0.4, curve = -4, telId = 0|
	var g   = gate;
	var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var pm  = ~f2CondIn.(InFeedback.ar(pmIn.max(0), 2).sum * 0.5, inGain, inDamp, inSat) * (pmIn >= 0);
	var sig = SinOsc.ar(freq * ratio, (pm * pmDepth * 2pi).mod(2pi));
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(sig * env * amp)) ! 2);
}).add;

// Granular sampler: grains pour while the gate is open; grPos/pitch/size are ordinary
// modulatable arguments (the per-cell ~mbAt buses drive them from any modulator).
// §tape mode=1: grPos steers the read head — a free-running tape MOTOR at the
// sample's natural speed × pitch (sign = direction). The control bus is only
// the TARGET: when the motor drifts out of a small tolerance (slice jump,
// retrigger, tempo mismatch), the head SNAPS there once under a 3 ms dip and
// free-runs again. A ramp scanning at natural speed ⇒ zero splices, literal
// mp3-style playback. grRate/grSize/grJit/spread act in grain mode only;
// mode is an ordinary modulatable arg (XFade2 blend).
SynthDef(\grainU, { |out = 0, gate = 0, t_trig = 0, amp = 0.5, i_free = 2, tel_bus = 0,
	buf = 0, grRate = 12, grSize = 0.12, grPos = 0.3, grJit = 0.02, pitch = 1, spread = 0.4,
	mode = 0, grEnv = 0,
	atk = 0.02, dec = 0.1, sus = 0.9, rel = 0.5, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var env  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	// §grain-hold the grain trigger is gated by a HELD gate (instant up, 50 ms
	// release), not the instantaneous one: legato re-triggers the gate with a
	// few-ms micro-gap at every cell boundary, and an Impulse tick landing in
	// that gap silently swallowed a whole grain — at duty-1 slicing that is a
	// full grain-period hole (105 BPM + grRate=1 resonate exactly every 7
	// beats: a one-second dropout every ~2 bars). Parked pool voices still
	// stay grain-silent: the held gate decays to 0 ~0.25 s after a real
	// release, and the env has closed long before that.
	var gh    = LagUD.kr(g, 0, 0.05) > 0.01;
	var trig0 = Impulse.kr(grRate.clip(0.1, 200)) * gh;
	// §grain-relatch a grain that latched grPos inside a bus TRANSIENT — the
	// smoother's ~16 ms per-cell handoff glide (auto smoothing starts from the
	// key's previous-loop value: up to a whole slice away), a map-seed race,
	// or a target jump landing right after the birth — plays the ENTIRE grain
	// from the wrong spot: at duty-1 slicing that is a beat-long shuffle, and
	// 105 BPM with grRate=1 resonates with the cell grid every 7 beats, so it
	// struck "randomly" every few bars and moved when grRate was wiggled
	// (impulse re-phased off the grid). Detector: the bus moving much faster
	// than any musical scan (>5× natural speed = a glide/jump in flight);
	// when that motion SETTLES within 50 ms of a grain birth, the grain is
	// re-latched at the corrected position — one brief window-faded overlap
	// instead of a second of shifted beat. Ordinary scans never trip it.
	var natV  = 1 / BufDur.kr(buf).max(0.001);
	var fastK = Slope.kr(grPos).abs > (natV * 5);
	var settl = Trig1.kr((1 - fastK) * Delay1.kr(fastK), ControlDur.ir);
	var young = Sweep.kr(trig0, 1) < 0.05;
	var trig  = trig0 + (settl * young);
	var pos  = (grPos + TRand.kr(grJit.neg, grJit, trig)).wrap(0, 1);
	// §flat-grain grEnv=1: COLA slicer window (~f2FlatWin server buffer, see
	// top of file) instead of GrainBuf's built-in Hann swell; grain duration
	// stretched ×1.1 so that at duty 1 (grSize = 1/grRate) each grain overlaps
	// the next by exactly the fade — complementary sin² edges sum to ONE:
	// constant loudness, mp3-flat, while every grain still re-reads grPos at
	// its onset (per-grain re-anchor = the slicer behavior). grSize < period
	// keeps real gaps (staccato slices); grEnv=0 keeps the classic Hann grain
	// texture untouched. The bufnum is baked at def build; -1 (no buffer =
	// alloc failed) falls back to Hann so the unit never goes silent.
	var flat  = grEnv > 0.5;
	var gDur  = grSize.clip(0.005, 2) * (1 + (flat * 0.1));
	var wIdx  = (~f2FlatWin !? { ~f2FlatWin.bufnum } ? -1);
	// §nat GrainBuf's `rate` is ALREADY relative to the buffer's own sample
	// rate: measured on a 48 kHz server reading 44.1 kHz material, rate 1 plays
	// back at 220.03 Hz against the file's 220 and rate = BufRateScale at
	// 202.16 — 8.1 % flat, the ratio itself. The factor was here because a
	// frame-per-sample reader needs it; GrainBuf is not one, and every grain
	// preset has been detuned by the distance between the file and the server.
	var gsig = GrainBuf.ar(2, trig, gDur, buf,
		pitch, pos, 2, TRand.kr(spread.neg, spread, trig),
		Select.kr(flat, [-1, wIdx]));
	// §tape head v6 (v7 PI servo REVERTED by user request — it reacted audibly
	// to boundary transients in real patches and made things worse; see git
	// history for the servo design if it ever returns). MOTOR, not
	// reconstruction: v4/v5 tried to rebuild continuous motion FROM the 60 Hz
	// stepped bus (period estimation); tick jitter kinked the head ~60×/s —
	// the mode-1 rasp. v6: the head is a free-running motor advancing at the
	// sample's natural speed × pitch (per-sample Sweep integration — pitch is
	// live varispeed, its sign is direction), and the control bus only
	// supplies the TARGET. Whenever the motor disagrees with grPos by more
	// than a tolerance (slice jump, retrigger, tempo drift accumulated), it
	// SNAPS there once — a single splice under the 3 ms dip — and free-runs
	// again. The 60 Hz staircase, network jitter and cell-boundary handoffs
	// all live INSIDE the tolerance band, so they no longer shape the motion.
	// Distance is measured circularly (a 1→0 loop wrap of a scanning ramp is
	// zero distance — the buffer loops seamlessly instead of splicing). Scan
	// speed ≠ pitch ⇒ periodic catch-up splices; match pitch to the scan
	// speed for continuous varispeed.
	// §cell-trig anti-drift: \f2voice pulses t_trig on every cell event of a
	// grainU preset (compiler cfg cellTrig), and the motor re-anchors to the
	// bus target at that musical onset — sample-vs-grid tempo mismatch is
	// wiped every cell (≈1-2 ms splice at a slice boundary, masked by the
	// break's own transients) instead of accumulating for bars until a 40 ms
	// mid-slice yank. The 3 ms dip fires only when the re-anchor jump is
	// audible (>0.005 ≈ 10 ms of material) — micro re-anchors ride the free
	// one-block K2A blend, so 16th-note onsets aren't ducked.
	var posK  = grPos.wrap(0, 1);
	var rateP = pitch / BufDur.kr(buf).max(0.001);   // motor speed, positions/sec (signed)
	var fbH   = LocalIn.kr(1);                       // previous-block head (1-block-late feedback)
	var dCirc = posK - fbH;
	var errK  = dCirc - dCirc.round(1.0);            // circular distance, ±0.5
	var snapT = Trig1.kr((errK.abs > 0.02) + t_trig + Impulse.kr(0), ControlDur.ir);
	var base  = Latch.kr(posK, snapT);
	var headK = (base + Sweep.kr(snapT, rateP)).wrap(0, 1);
	var headA = (K2A.ar(base) + Sweep.ar(T2A.ar(snapT), rateP)).wrap(0, 1);
	var dip   = 1 - LagUD.kr(Trig1.kr(snapT * (errK.abs > 0.005), 0.003), 0.0005, 0.003);
	var dcl   = LagUD.ar(K2A.ar(g > 0), 0.0025, 0.0025);
	var tsig  = (BufRd.ar(1, buf, headA * BufFrames.kr(buf), 1, 4) * K2A.ar(dip) * dcl) ! 2;
	var sig  = XFade2.ar(gsig, tsig, (mode.clip(0, 1) * 2) - 1);
	LocalOut.kr(headK);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * env * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// Stutter processor: a ring buffer of the input (the srcIn port); on a trigger (a gate
// front or t_trig, with probability `chance`) it loops `slice` seconds FROM THE MOMENT OF
// THE TRIGGER (§stut-look: the read is anchored to the write head; `look` slides the capture
// window back into the past). mix: 0 = the bus passes through, 1 = stutter only.
SynthDef(\stutU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, slice = 0.125, pitch = 1, chance = 1, mix = 1, look = 0,
	inGain = 1, inDamp = 0, inSat = 0,
	atk = 0.005, dec = 0.05, sus = 1, rel = 0.15, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g      = gate;
	var envG   = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env    = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var frames = 65536;
	var buf    = LocalBuf(frames, 2).clear;
	var inp    = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	// §stut-look the write uses an explicit phasor (a ring) so that the write head's position
	var wr     = Phasor.ar(0, 1, 0, frames);
	var rec    = BufWr.ar(inp, buf, wr);
	// re-slice both on the gate front (under reuse t_trig does not move) and on t_trig
	var trig   = (Trig.kr(g, 0.001) + Trig.kr(t_trig, 0.001)).min(1) * (TRand.kr(0, 1, g) < chance);
	var fr     = (slice.clip(0.01, 1.3) * SampleRate.ir).min(frames);
	// §stut-look THE ROOT of «it loops late, once the sound has already died»: the read used
	// to take the ABSOLUTE region [0, fr) of the buffer, tied to nothing about the write head
	// — fresh sound entered the loop only when the ring's head HAPPENED to pass through
	// [0, fr), i.e. with a lag of up to 1.36 s (right after a spawn both heads are at zero,
	// which is why «it works after a deploy» and then drifts). Now the read is anchored to the
	// write position LATCHED BY THE TRIGGER: the loop is exactly `slice` seconds from the trigger.
	//   look (seconds, 0..1.3) — slides the capture window BACK into the past: 0 = forward from
	//   the trigger (the first pass plays the live input and writes it at the same time — the
	//   transient is captured); look = slice = it loops the slice that ENDED at the trigger (what
	//   was just heard); in between, the window straddles the trigger. Modulatable like anything.
	//   The guard block behind the head (blk): reading at the head itself is a UGen-order race.
	var blk    = SampleRate.ir * ControlDur.ir;
	var w0     = Latch.ar(wr, K2A.ar(trig));
	var ph     = (w0 - blk - (look.clip(0, 1.3) * SampleRate.ir)
		+ Phasor.ar(K2A.ar(trig), pitch, 0, fr)).wrap(0, frames);
	var wet    = BufRd.ar(2, buf, ph, 1, 4);
	// §stut-mix master dry/wet instead of a gate-crossfade: 0 = transparent bus,
	// 1 = only the stutter product (wet lives on the ADSR like an instrument).
	// §stut-idle v2 the transparent dry path is open ONLY while the voice is in
	// use. Deliberately NOT derived from the ADSR env: a stuck env (the gate-off
	// suppression class this project has seen) would hold the bus open forever —
	// exactly the "no stutU playing, yet y2 still sounds" report. Instead `open`
	// is its own ASR follower of the RAW \gate control: 5 ms declick attack, the
	// unit's `rel` as release. Idle pool voice (gate 0 since spawn) ⇒ open = 0 ⇒
	// nothing passes; while open the bus stays shape-transparent (no ADSR curve).
	// §cards in a strip the dry path is the stream itself (private stage bus,
	// silent when the sources are) — pass-through like env: no gate at all.
	var openG = EnvGen.kr(Env.asr(0.005, 1, rel.max(0.01)), g);
	var open  = Select.kr(chainIn >= 0, [openG, 1]);
	var sig  = XFade2.ar(inp * open, wet * env, (mix.clip(0, 1) * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// Chaos generator (plain Logistic + Crackle): an audio texture and/or an FM/AM source into
// a port; `rate` smooths it.
SynthDef(\chaosU, { |out = 0, gate = 0, t_trig = 0, amp = 0.3, i_free = 2, tel_bus = 0,
	chaos = 3.8, rate = 200, blend = 0.4,
	atk = 0.05, dec = 0.1, sus = 1, rel = 0.6, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g   = gate;
	var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var lo  = Logistic.ar(chaos.clip(3.2, 4.0), rate.clip(1, 8000));
	var cr  = Crackle.ar(chaos.clip(1.0, 2.0).max(1.0).min(1.99));
	var sig = XFade2.ar(lo, cr, (blend * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1),
		'/f2_chan', [(A2K.kr(sig) * 0.5 + 0.5).clip(0, 1)], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * env * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))) ! 2);
}).add;

// Stochastic source: dust pings with a probability — percussive dust in its own right, and a
// modulator through a port (stochastic FM/AM). It also drives gate channels for OTHER units
// and reports /f2_chan telemetry.
SynthDef(\stochU, { |out = 0, gate = 0, t_trig = 0, amp = 0.4, i_free = 2, tel_bus = 0,
	dens = 6, prob = 0.7, freq = 900, decay = 0.12,
	atk = 0.01, dec = 0.05, sus = 1, rel = 0.3, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var env  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var dst  = Dust.kr(dens.clip(0.1, 200) * (g > 0));
	var trig = dst * (TRand.kr(0, 1, dst) < prob);
	var sig  = Ringz.ar(K2A.ar(Trig.kr(trig, 0.001)), freq, decay);
	SendReply.kr(Impulse.kr(60) * (telId > 0) * (g > 0), '/f2_chan', [Trig.kr(trig, 0.08)], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig.tanh * env * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))) ! 2);
}).add;

// ── §glitch-units the modal-percussive set ────────────────────────────────
// Five units for rich percussive and modal glitch. Same conventions as the rest
// (gate/i_free/telId, LeakDC→Sanitize, InFeedback inputs through ~f2CondIn); in comb and
// pluck the recursion is INTERNAL (sample-accurate, stable) — these are the «bricks» of
// steady loops, unlike the cross-module block loops of the ports.

// Modal resonator: a bank of 6 Ringz modes. Excitation is a click on the gate front (click)
// plus a noise admixture (noiseAmt, while the gate is open) plus SOMEONE ELSE'S audio (the
// exIn port) — i.e. any module can «strike» the resonator. inharm pulls the mode ratios from
// harmonic towards bell-like and metallic, bright tilts the amplitudes, decMul is the ring.
SynthDef(\modalU, { |out = 0, gate = 0, t_trig = 0, amp = 0.4, i_free = 2, tel_bus = 0,
	exIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	freq = 180, inharm = 0.3, bright = 0.5, decMul = 0.4, click = 1, noiseAmt = 0,
	atk = 0.001, dec = 0.05, sus = 0.7, rel = 0.4, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var ext  = ~f2CondIn.((InFeedback.ar(exIn.max(0), 2).sum * 0.5 * (exIn >= 0)) + (~f2ChainIn.(chainIn).sum * 0.5), inGain, inDamp, inSat);
	var tr   = Trig.ar(K2A.ar(g), SampleDur.ir);
	var exc  = (tr * click * 2) + (PinkNoise.ar(noiseAmt.clip(0, 1) * 0.5) * (g > 0)) + ext;
	var ratios = #[1.0, 2.001, 2.987, 4.42, 5.35, 6.79];
	var sig  = Mix(ratios.collect { |r, i|
		Ringz.ar(exc,
			(freq * (r ** (1 + (inharm * 0.55)))).clip(25, 15500),
			(decMul.clip(0.02, 4)) * (1 - (i * 0.08)),
			((i + 1).reciprocal ** (1 - bright.clip(0, 1))) * 0.22)
	});
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.((sig * env * amp).tanh, eqLo, eqMid, eqHi, eqLoF, eqHiF))) ! 2);
}).add;

// Karplus-Strong: a pluck / string percussion (Pluck is a built-in STABLE recursion).
// Excitation is a noise burst on the gate plus the exIn port; fb is the string's lifetime,
// plDamp the loop's damper (dull ↔ bright), burstFreq the colour of the pluck.
SynthDef(\pluckU, { |out = 0, gate = 0, t_trig = 0, amp = 0.5, i_free = 2, tel_bus = 0,
	exIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	freq = 220, fb = 0.6, plDamp = 0.35, burst = 1, burstFreq = 2500,
	atk = 0.001, dec = 0.03, sus = 1, rel = 0.25, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var ext  = ~f2CondIn.((InFeedback.ar(exIn.max(0), 2).sum * 0.5 * (exIn >= 0)) + (~f2ChainIn.(chainIn).sum * 0.5), inGain, inDamp, inSat);
	var tr   = Trig.ar(K2A.ar(g), SampleDur.ir);
	var exc  = LPF.ar(WhiteNoise.ar(burst.clip(0, 2)) * Decay2.ar(tr, 0.0005, 0.012), burstFreq.clip(200, 12000)) + ext;
	var sig  = Pluck.ar(exc, tr, 0.06,
		freq.clip(18, 4000).reciprocal,
		fb.clip(0, 1).linexp(0, 1, 0.04, 9),
		plDamp.clip(0, 1).linlin(0, 1, 0.05, 0.7));
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * env * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))) ! 2);
}).add;

// Percussive noise oscillator: a resonant filter over noise or crackle with a pitch sweep at
// the onset (pEnv/pDec — the depth and time of the sweep: clicks, snares, zaps). res near 1
// makes the filter ring almost at a pitch; crackle mixes in a chaotic crackle.
SynthDef(\noiseU, { |out = 0, gate = 0, t_trig = 0, amp = 0.5, i_free = 2, tel_bus = 0,
	freq = 900, res = 0.4, pEnv = 0.5, pDec = 0.06, crackle = 0,
	atk = 0.0005, dec = 0.04, sus = 0.4, rel = 0.15, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var env  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var tr   = Trig.ar(K2A.ar(g), SampleDur.ir);
	var sw   = EnvGen.ar(Env.perc(0.0005, pDec.clip(0.005, 0.5), 1, -6), tr);
	var f    = (freq * (1 + (sw * pEnv.clip(0, 1) * 6))).clip(30, 15000);
	var src  = XFade2.ar(WhiteNoise.ar, Crackle.ar(1.72 + (crackle.clip(0, 1) * 0.26)), (crackle.clip(0, 1) * 2) - 1);
	var sig  = RLPF.ar(src, f, res.clip(0, 1).linlin(0, 1, 1, 0.05));
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.((sig * env * amp).tanh, eqLo, eqMid, eqHi, eqLoF, eqHiF))) ! 2);
}).add;

// Comb processor: CombC over the input (the srcIn port) — metallic tails and tonal combs;
// the recursion is INSIDE the UGen (sample-accurate, stable at any fb 0..1). combFreq is the
// comb's «note», fb the ring time, damp a high-frequency damper BEFORE the loop.
SynthDef(\combU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	combFreq = 220, fb = 0.6, damp = 0.2, mix = 1,
	atk = 0.003, dec = 0.05, sus = 1, rel = 0.3, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var inp  = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var pre  = OnePole.ar(inp, damp.clip(0, 0.95));
	var wet  = CombC.ar(pre, 0.06,
		combFreq.clip(18, 2000).reciprocal,
		fb.clip(0, 1).linexp(0, 1, 0.03, 10));
	var sig  = XFade2.ar(inp, wet, (mix.clip(0, 1) * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.((sig * env * amp).tanh, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// Folder / crusher processor: drive → wavefold → sample-rate and bit reduction over the input
// (srcIn) — glitch shaping right IN THE LOOP (fold clamps the amplitude hard, so it is one
// more stabiliser of recursion, but one with a character). tone tidies the rubbish up top.
SynthDef(\foldU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	fDrive = 0.3, foldAmt = 0.5, crush = 1, tone = 0.8, mix = 1,
	atk = 0.003, dec = 0.05, sus = 1, rel = 0.2, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var inp  = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var drv  = 1 + (fDrive.clip(0, 1) * 7);
	var fold = ((inp * drv).fold2(1) / drv.max(1)) * (1 + (foldAmt.clip(0, 1) * 6));
	var lvls = 2 ** crush.clip(0, 1).linlin(0, 1, 3, 24);
	var cr   = Latch.ar(fold.fold2(1), Impulse.ar(crush.clip(0, 1).linexp(0, 1, 1200, 44100)));
	var wet  = LPF.ar(((cr * lvls).round(1) / lvls), tone.clip(0, 1).linexp(0, 1, 300, 18000));
	var sig  = XFade2.ar(inp, wet, (mix.clip(0, 1) * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.((sig * env * amp).tanh, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// ── §mod-suite cross-modulation WITHOUT multiplication ────────────────────
// Shifting every frequency by a number of hertz (inharmonic!), granular pitch shift with
// recursion (shimmer), and the envelope of SOMEONE ELSE'S signal as a three-band VCA (vocal
// and rhythmic pads). All of them are processors (port inputs). vocU is the one surviving
// carrier ↔ modulator here: it took amU's place in §cut v49.

// Frequency shifter (SSB): shifts EVERY frequency by `shift` Hz — it destroys harmonicity
// (bells and drones out of any material); fb is the «barber pole» recursion (each turn
// shifts again, an internal tanh holds the loop).
SynthDef(\shiftU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	shift = 120, fb = 0.3, mix = 1,
	atk = 0.005, dec = 0.05, sus = 1, rel = 0.3, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var inp  = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var loop = LocalIn.ar(2);
	var wet  = FreqShift.ar(inp + (loop * fb.clip(0, 0.95)), shift.clip(-2000, 2000));
	var sig;
	LocalOut.ar(LeakDC.ar(wet).tanh);
	sig = XFade2.ar(inp, wet, (mix.clip(0, 1) * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * env * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// Shimmer: granular pitch shift (pRatio, window fixed at 0.18s) with fb recursion — the
// «octave up in the loop» classic = glassy pad tails; pDisp scatters the pitch (chorus, haze).
SynthDef(\shimU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	pRatio = 2, pDisp = 0, fb = 0.4, mix = 0.5,
	atk = 0.01, dec = 0.05, sus = 1, rel = 0.5, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var inp  = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var loop = LocalIn.ar(2);
	var wet  = PitchShift.ar(inp + (loop * fb.clip(0, 0.9)), 0.18,
		pRatio.clip(0.25, 4), pDisp.clip(0, 0.5), 0.012);
	var sig;
	LocalOut.ar(LeakDC.ar(wet) * 0.92);
	sig = XFade2.ar(inp, wet, (mix.clip(0, 1) * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * env * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// Vocoder follower: the modulator's envelopes (modIn) in 3 bands drive the carrier's
// amplitude (carIn) in the same bands — «modIn speaks through the carrier»: rhythm gates,
// talking pads. sens is the sensitivity, hard an expander (sharper dips), vAtk/vRel the
// speed of the followers.
SynthDef(\vocU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	carIn = -1, chainIn = -1, modIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	sens = 1, hard = 0, vAtk = 0.005, vRel = 0.12,
	atk = 0.005, dec = 0.05, sus = 1, rel = 0.25, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var car  = ~f2CondIn.((InFeedback.ar(carIn.max(0), 2) * (carIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var mod  = (~f2CondIn.(InFeedback.ar(modIn.max(0), 2).sum * 0.5, inGain, inDamp, inSat) * (modIn >= 0));
	var a = vAtk.clip(0.0005, 0.2), r = vRel.clip(0.005, 1.5);
	var f1 = Amplitude.ar(LPF.ar(mod, 350), a, r);
	var f2 = Amplitude.ar(BPF.ar(mod, 1000, 1.2), a, r);
	var f3 = Amplitude.ar(HPF.ar(mod, 2500), a, r);
	var pw = 1 + (hard.clip(0, 1) * 3);
	var sig = (LPF.ar(car, 350) * (f1 * sens).clip(0, 2).pow(pw))
		+ (BPF.ar(car, 1000, 1.2) * (f2 * sens).clip(0, 2).pow(pw) * 2)
		+ (HPF.ar(car, 2500) * (f3 * sens).clip(0, 2).pow(pw));
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.((sig * env * amp).tanh, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// ── §pad-drum sources: sub/kick and the layered pad ───────────────────────

// Sub oscillator / kick engine: a sine with a pitch sweep at the onset (pEnv/pDec — depth
// and time: 808 sub → punchy kick → tom), fDrive saturates the body, click is the attack's
// click. Percussion = sus 0 and a short dec; sub bass = sus 1.
SynthDef(\subU, { |out = 0, gate = 0, t_trig = 0, amp = 0.7, i_free = 2, tel_bus = 0,
	freq = 55, pEnv = 0.6, pDec = 0.08, fDrive = 0.2, click = 0.3,
	atk = 0.001, dec = 0.2, sus = 0.4, rel = 0.25, curve = -4, telId = 0|
	var g    = gate;
	var env  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var tr   = Trig.ar(K2A.ar(g), SampleDur.ir);
	var sw   = EnvGen.ar(Env.perc(0.0005, pDec.clip(0.005, 0.5), 1, -6), tr);
	var f    = (freq * (1 + (sw * pEnv.clip(0, 1) * 8))).clip(18, 800);
	var body = SinOsc.ar(f);
	var cl   = BPF.ar(WhiteNoise.ar, 3200, 0.6) * Decay2.ar(tr, 0.0005, 0.006) * click.clip(0, 2) * 3;
	var sig  = ((body * (1 + (fDrive.clip(0, 1) * 6))).tanh) + cl;
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(sig * env * amp)) ! 2);
}).add;

// Pad: a stack of 7 detuned saws plus a sub octave, stereo spread, slow «breathing» of the
// voices (move) and a common tone filter. A self-sufficient layer for complex pads, and a
// harmonically rich carrier for vocU and specU.
SynthDef(\padU, { |out = 0, gate = 0, t_trig = 0, amp = 0.35, i_free = 2, tel_bus = 0,
	freq = 110, dtn = 0.15, wide = 0.7, subAmt = 0.3, move = 0.2, tone = 0.6,
	atk = 0.8, dec = 0.3, sus = 0.8, rel = 1.2, curve = -4, telId = 0|
	var g    = gate;
	var env  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var offs = #[-3, -2, -1, 0, 1, 2, 3];
	var sig  = Mix(offs.collect { |o, i|
		var f  = freq * (1 + (o * dtn.clip(0, 1) * 0.012));
		var mv = 1 + (LFNoise2.kr(0.11 + (i * 0.07)) * move.clip(0, 1) * 0.5);
		Pan2.ar(Saw.ar(f.clip(20, 8000)) * mv, (o / 3) * wide.clip(0, 1))
	}) / 4;
	sig = sig + (SinOsc.ar((freq * 0.5).clip(18, 2000)) * subAmt.clip(0, 1) ! 2);
	sig = LPF.ar(sig, tone.clip(0, 1).linexp(0, 1, 300, 14000));
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(sig * env * amp)));
}).add;

// Chip oscillator (§chip): the Impulse-Tracker idiom — single-cycle waves, the
// Ilkae/4EP sound — with the Jxy trick: "polyphony" on ONE voice = the note
// and up to three semitone offsets cycled at frame rate (arpRate ≈ 50 Hz PAL),
// a chord heard as a pure fast arpeggio. arp1..arp3 are ordinary modulatable
// args (dice/lattice/harmony re-chord it live); arpN = cycle length − 1
// (0 = plain note, 2 = classic note + two offsets). wave: 0 pulse (duty),
// 1 NES-style 16-step triangle, 2 saw, 3 clocked binary noise (pitch-tracked).
// bits/srate = bit crush and downsample (the IT-mixer grit; srate 0 = off);
// cut/rq = resonant lowpass (the IT 2.14 filter); vib/vibRate = chip vibrato.
// The arp stepper resets to the root on every gate front and t_trig.
SynthDef(\chipU, { |out = 0, gate = 0, t_trig = 0, amp = 0.35, i_free = 2, tel_bus = 0,
	freq = 220, wave = 0, duty = 0.5, arp1 = 0, arp2 = 0, arp3 = 0, arpN = 2, arpRate = 50,
	bits = 8, srate = 0, cut = 12000, rq = 1, vib = 0, vibRate = 6,
	atk = 0.001, dec = 0.03, sus = 0.9, rel = 0.06, curve = -4, telId = 0|
	var g    = gate;
	var env  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var aRst = Trig.kr(g, 0.001) + t_trig;
	var step = Stepper.kr(Impulse.kr(arpRate.clip(1, 200)), aRst, 0, arpN.round(1).clip(0, 3), 1);
	var off  = Select.kr(step, [0, arp1, arp2, arp3]);
	var fr   = (freq * off.midiratio
		* (1 + (SinOsc.kr(vibRate.clip(0.1, 20)) * vib.clip(0, 1) * 0.03))).clip(8, 12000);
	var pul  = LFPulse.ar(fr, 0, duty.clip(0.05, 0.95), 2, -1);
	var tri  = (LFTri.ar(fr) * 7.5).round(1) * (1/7.5);
	var saw  = LFSaw.ar(fr);
	var noi  = LFClipNoise.ar((fr * 8).clip(100, 22050));
	var sig  = Select.ar(wave.round(1).clip(0, 3), [pul, tri, saw, noi]);
	var lv   = 2 ** (bits.clip(1, 16) - 1);
	sig = (sig * lv).round(1) * lv.reciprocal;
	sig = Select.ar(srate > 0, [sig, Latch.ar(sig, Impulse.ar(srate.clip(500, 24000)))]);
	sig = RLPF.ar(sig, cut.clip(80, 18000), rq.clip(0.05, 1));
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(sig * env * amp)) ! 2);
}).add;

// ── §spec-suite the spectral suite: harmonics / FFT processor / transients ─

// Additive oscillator: 12 partials; nHarm is how many sound, slope the amplitude falloff,
// odd the odd/even balance, stretch an inharmonic stretch (1 = harmonic, >1 = «piano-like»
// or bell-like), shimmer a slow breathing of the partials. A spectrally precise source for
// pads and carriers.
SynthDef(\harmU, { |out = 0, gate = 0, t_trig = 0, amp = 0.35, i_free = 2, tel_bus = 0,
	freq = 220, nHarm = 8, slope = 0.5, odd = 0.5, stretch = 1, shimmer = 0.2,
	atk = 0.05, dec = 0.1, sus = 0.8, rel = 0.6, curve = -4, telId = 0|
	var g    = gate;
	var env  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var sig  = Mix(12.collect { |k|
		var i  = k + 1;
		var ob = if (i.odd) { 1 } { -1 };   // odd +, even − → the odd knob weighs them
		var w  = (1 + (ob * ((odd * 2) - 1))).clip(0, 1);
		var a  = ((1 / i) ** (slope.clip(0, 1) * 2.5)) * w * (i <= nHarm.clip(1, 12));
		var sh = 1 + (LFNoise2.kr(0.23 + (k * 0.11)) * shimmer.clip(0, 1) * 0.5);
		SinOsc.ar((freq * (i ** stretch.clip(0.5, 2))).clip(20, 16000)) * a * sh
	}) * 0.3;
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(sig * env * amp)) ! 2);
}).add;

// FFT processor over the input: magnitude smearing (smear), bin shifting (bShift, inharmonic
// transposition), a spectral freeze (freeze >0.5 — a spectral drone out of one moment), and a
// random comb of bins (scomb, re-thrown on every onset). One unit covering a whole field of
// cutting-edge processing; the knobs are modulatable.
SynthDef(\specU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	smear = 0, bShift = 0, freeze = 0, scomb = 0, mix = 1,
	atk = 0.005, dec = 0.05, sus = 1, rel = 0.3, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g     = gate;
	var envG  = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env   = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var inp   = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var mono  = inp.sum * 0.5;
	var chain = FFT(LocalBuf(2048), mono);
	var wet, sig;
	chain = PV_MagSmear(chain, (smear.clip(0, 1) * 64).round(1));
	chain = PV_BinShift(chain, 1, bShift.clip(-64, 64));
	chain = PV_MagFreeze(chain, freeze > 0.5);
	chain = PV_RandComb(chain, scomb.clip(0, 1), Trig.kr(g, 0.001) + Trig.kr(t_trig, 0.001));
	wet   = IFFT(chain);
	sig   = XFade2.ar(inp, wet ! 2, (mix.clip(0, 1) * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * env * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// Transient shaper: splits the input into attacks and body (a fast and a slow follower),
// trans boosts or suppresses the transients, body the bodies (0..2, 1 = as it was), snap
// smooths the switching. trans>1 with body<1 = dry clicking percussion out of anything;
// trans<1 with body>1 = smeared pad tails with no attack.
SynthDef(\tranU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	trans = 1, body = 1, snap = 0.15,
	atk = 0.003, dec = 0.05, sus = 1, rel = 0.2, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var inp  = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var mono = inp.sum * 0.5;
	var fast = Amplitude.ar(mono, 0.0008, 0.03);
	var slow = Amplitude.ar(mono, 0.06, 0.25);
	var w    = (((fast - slow).max(0)) / (slow + 0.001)).clip(0, 1);
	var gain = body.clip(0, 2) + ((trans.clip(0, 2) - body.clip(0, 2)) * w);
	var sig  = inp * Lag.ar(gain, (snap.clip(0, 1) * 0.02) + 0.0005);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.((sig * env * amp).tanh, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// ── §conv-suite texture × transient cross-synthesis ────────────────────────
// Three units for the "ambient texture blended with a short percussive hit"
// workflow (real convolution and its relatives). All are processors: port
// inputs through ~f2CondIn, LeakDC→Sanitize→~f2Eq3 on the way out, standard
// gate env under §reuse, env telemetry. The suite's detector, onsetU, was cut
// in v49: scatU's own trigIn + threshold finds the same hits.

// ── §conv-ir the SAMPLE mode's prepared impulse responses ─────────────────
// PartConv does not read a sound file. It reads a buffer of SPECTRA — one per
// partition — that the server's own `PreparePartConv` /b_gen builds out of an
// IR buffer, so convU's `irSample` cannot be handed over the way samplerU's
// `sample` is (~f2SmpBuf → a plain bufnum). The file has to be read at the
// TRIMMED length, levelled, prepared once OFF the event thread and cached: the
// shape of the sampler's per-file analyses (~f2SmpFftBufAt, §6) and for the
// same reason — a file read on a note is a stall on a note.
// The cache key is (sample × irLen × fftsize): the trim changes the IR bytes
// and the partition count follows its length, so all three change the result.
//
// EVERY STEP IS ASYNC AND EACH NEEDS THE ONE BEFORE IT: the read fills the IR
// buffer, normalize rescales what the read put there, PreparePartConv reads
// that. Only /b_alloc-family commands carry a completion message — /b_gen does
// not — so the chain is sequenced with s.sync from a Routine instead, which is
// also why the whole prep is forked: \f2voice calls this from Event:play, where
// waiting is not allowed. The failure this avoids is the one ~f2SmpWins
// documents from the other direction: a command that lands on a buffer whose
// contents are not there yet leaves zeros, and zeros are SILENCE with nothing
// in the log to say why.
~f2ConvFft = 2048;          // partition = fft/2 ⇒ 960 samples of PartConv latency (20 ms @ 48k)
~f2ConvPreMax = 0.2;        // s — the ceiling of preDly and the size of its delay line
~f2ConvIrMaxDur = 20;       // s of impulse response one card may prepare
// PartConv piles every partition of the IR onto the input ("Normalisation
// factors difficult to anticipate" is PartConv's own help), so a two-second IR
// runs some 20 dB hotter than a 40 ms one at the same kGain. The compensation
// is exact and free at prep time: the trimmed IR is normalised to 1/√partitions
// rather than to 1, so the wet level follows the IR's SHAPE and not its length
// or how hot the file was recorded — and kGain stays the Wet Gain the card says
// it is. One partition ⇒ a target of 1.0 ⇒ the null IR passes through.
~f2ConvIrParts = { |frames, fft| ((frames / ((fft ? 2048) div: 2)).roundUp).asInteger.max(1) };
~f2ConvIrNorm = { |frames, fft| 1.0 / (topEnvironment[\f2ConvIrParts].(frames, fft)).sqrt };

// The null IR a card reads while its real one is still being prepared: a single
// 1.0, i.e. convolution with an impulse = the source itself. Going SILENT in
// that window is the wrong default — a card whose prep is one block late would
// drop out of the mix on every reload — so an unprepared wet path passes the
// source through instead. It stays -1 without a booted server (the NRT
// harnesses load this file with nothing running and build their own IR in the
// score); the graph reads -1 as «no IR at all» and mutes the wet path, which is
// the honest answer when there is not even an impulse to convolve with.
~f2ConvIrNullBufs !? { |old| old.do { |b| try { b.free } } };
~f2ConvIrNullBufs = [];
~f2ConvIrNull = -1;
if (s.serverRunning) {
	{
		try {
			var fft = topEnvironment[\f2ConvFft];
			var part = fft div: 2;
			var src = Buffer.loadCollection(s, FloatArray.fill(part, { |i| if (i == 0) { 1.0 } { 0.0 } }));
			var spec = Buffer.alloc(s, fft, 1);          // one partition ⇒ fft floats
			s.sync;                                      // the impulse is in src, spec exists
			s.listSendMsg(['/b_gen', spec.bufnum, 'PreparePartConv', src.bufnum, fft]);
			s.sync;
			topEnvironment[\f2ConvIrNullBufs] = [src, spec];
			topEnvironment[\f2ConvIrNull] = spec.bufnum;
			("✓ f2 conv: null IR (1 partition, fft " ++ fft ++ ") → buf " ++ spec.bufnum).postln;
		} { |e|
			("⚠ [f2 conv] the null IR could not be prepared: % — a convU card whose IR is not ready yet is DRY rather than pass-through".format(e.errorString)).postln;
		};
	}.fork(SystemClock);
};

// One entry per (sample, irLen, fftsize): the prepared spectrum buffer PartConv
// reads. \pending until the server has acked the whole chain, and every call in
// that window gets the null instead. A failure is cached too — a missing file
// must not re-kick a file read on every note.
~f2ConvIrs !? { |old| old.do { |e| (e[\bufs] ? []).do { |b| try { b.free } } } };
~f2ConvIrs = IdentityDictionary.new;
// …and a bound on how many of them may exist at once. Two server buffers per
// entry, and at the 20 s ceiling that is ~4 MB — while the card offers a file
// MENU and a trim SPINNER, both of which a user works through by trying things:
// auditioning a folder of impulses, or stepping `irLen` down to taste, mints a
// fresh entry every time and nothing ever dropped one until ~loadSamples fired.
// The sampler's analysis cache has had this exact bound since §6 for the same
// reason (~f2SmpAnalysisTouch); an IR is the same kind of object and gets the
// same treatment. 16 entries is a folder's worth of auditioning plus the few a
// preset actually uses; the evicted one costs one silent-but-passing-through
// note to re-prepare, never a wrong sound.
~f2ConvIrMax = 16;
~f2ConvIrLRU = [];
~f2ConvIrTouch = { |key|
	var cache = topEnvironment[\f2ConvIrs] ? IdentityDictionary.new;
	var max   = (topEnvironment[\f2ConvIrMax] ? 16).max(1);
	var lru   = (topEnvironment[\f2ConvIrLRU] ? []).reject { |k| k == key } ++ [key];
	var i;
	while { lru.size > max } {
		// the oldest entry that is NOT still preparing. A pending one is held by a
		// running fork which is about to /b_gen into those two bufnums: freeing them
		// now would let the next allocation take the numbers and be written over by
		// the old prep — silent corruption with nothing in the log. So it is skipped,
		// and if every entry is pending the cache simply stays over its bound until
		// one of them lands.
		i = lru.detectIndex { |k| (cache[k] !? { |e| e[\state] }) != \pending };
		if (i.isNil) {
			max = lru.size;
		} {
			var drop = lru.removeAt(i);
			cache[drop] !? { |e| (e[\bufs] ? []).do { |b| try { b.free } } };
			cache.removeAt(drop);
		};
	};
	topEnvironment[\f2ConvIrLRU] = lru;
	nil
};
~f2ConvIrAt = { |name, len, fft|
	// topEnvironment, not `~`: this runs from \f2voice inside an Event, where
	// currentEnvironment is that Event and every `~name` of the library is nil
	var d = topEnvironment[\f2ConvIrs];
	var nul = (topEnvironment[\f2ConvIrNull] ? -1);
	var nm = (name ? "").asString;
	var pc = ((len ? 100).asFloat).clip(1, 100);
	var ff = ((fft ? (topEnvironment[\f2ConvFft] ? 2048)).asInteger);
	var key = (nm ++ "|" ++ pc.round(0.01) ++ "|" ++ ff).asSymbol;
	var e = d[key];
	if (nm.isEmpty.not) { topEnvironment[\f2ConvIrTouch].value(key) };
	case
		{ nm.isEmpty } { nul }                                        // no file named: pass through
		{ e.notNil } { if (e[\state] == \ready) { e[\bufnum] } { nul } }
		{ true } {
			var src = (topEnvironment[\samples] ? IdentityDictionary.new)[nm.asSymbol];
			var path = (src !? { |b| b.tryPerform(\path) });
			var frames = ((src !? { |b| b.tryPerform(\numFrames) }) ? 0).asInteger;
			var sr = ((src !? { |b| b.tryPerform(\sampleRate) }) ? 44100);
			var n, irb, spec;
			e = (state: \pending, bufnum: nul, bufs: []);
			d[key] = e;
			// a Buffer that has not answered /b_query yet has no frame count — the
			// file header has, and the trim needs it to cut anything at all
			if (frames < 1 and: { path.notNil }) {
				SoundFile.openRead(path.asString) !? { |f|
					frames = f.numFrames.asInteger; sr = f.sampleRate; f.close;
				};
			};
			if (path.isNil or: { File.exists(path.asString).not } or: { frames < 1 }
				or: { s.serverRunning.not }) {
				e[\state] = \failed;
				topEnvironment[\f2UnitWarnOnce].(("conv_noir_" ++ key).asSymbol,
					"⚠ [f2 conv] impulse % is not a readable sample — the card's wet path passes the source through".format(
						if (nm.isEmpty) { "(none)" } { nm }));
				nul
			} {
				n = ((frames * pc / 100).round.asInteger)
					.clip(1, (sr * (topEnvironment[\f2ConvIrMaxDur] ? 20)).asInteger);
				irb = Buffer.new(s, n, 1);        // reserves the bufnum, sends nothing yet
				spec = Buffer.new(s, ff * topEnvironment[\f2ConvIrParts].(n, ff), 1);
				e[\bufs] = [irb, spec];
				{
					var ok = true;
					try {
						s.listSendMsg(irb.allocReadChannelMsg(path.asString, 0, n, [0]));
						s.listSendMsg(spec.allocMsg);
						s.sync;                                       // the IR is in irb
						s.listSendMsg(['/b_gen', irb.bufnum, 'normalize',
							topEnvironment[\f2ConvIrNorm].(n, ff)]);
						s.sync;                                       // …and levelled
						s.listSendMsg(['/b_gen', spec.bufnum, 'PreparePartConv', irb.bufnum, ff]);
						s.sync;                                       // …and prepared
					} { |err| ok = false;
						topEnvironment[\f2UnitWarnOnce].(("conv_irprep_" ++ key).asSymbol,
							"⚠ [f2 conv] the IR % could not be prepared: % — the card's wet path passes the source through".format(
								key, err.errorString));
					};
					if (ok) {
						e[\bufnum] = spec.bufnum; e[\state] = \ready;
						("✓ [f2 conv] ir % trim % → buf % (% frames, % partitions, fft %)".format(
							nm, pc, spec.bufnum, n, topEnvironment[\f2ConvIrParts].(n, ff), ff)).postln;
					} { e[\state] = \failed };
				}.fork(SystemClock);
				nul                      // this note plays through; the next one has the IR
			}
		}
};
// What \f2voice calls at spawn, the mirror of ~f2SmpBuf / ~f2SmpRes: the card's
// opts → the bufnum its `irBuf` takes. Under `ir: bus` there is no IR to name
// and the bus graph has no PartConv in it at all, so -1 is simply the value the
// unused control keeps.
~f2ConvIrRes = { |opts|
	var o = opts ? ();
	var gets = { |k, dflt| var v = (o[k] ? o[k.asString]); if (v.isNil) { dflt } { v.asString } };
	if (gets.(\ir, "bus").asSymbol == 'sample') {
		topEnvironment[\f2ConvIrAt].value(gets.(\irSample, ""),
			gets.(\irLen, "100").asFloat, topEnvironment[\f2ConvFft])
	} { -1 }
};
// A samples reload replaces the Buffers the cache keyed its entries on, so the
// prepared spectra belong to files that are no longer loaded: drop them and let
// the next spawn re-prepare (the twin of ~f2SmpForget, called beside it).
~f2ConvIrForget = {
	(topEnvironment[\f2ConvIrs] ? IdentityDictionary.new).do { |e|
		(e[\bufs] ? []).do { |b| try { b.free } };
	};
	topEnvironment[\f2ConvIrs] = IdentityDictionary.new;
	topEnvironment[\f2ConvIrLRU] = [];
	nil
};

// convU's one structural menu. `ir` MUST be structural and not a live control:
// `bus` is Convolution2 over a LocalBuf the graph itself records into, `sample`
// is PartConv over a prepared spectrum buffer — two different graphs whose
// buffer sizes are instantiation arguments on both sides, the same reason
// `grains` and `qual` are structural on samplerU. def `bus` keeps every saved
// convU card on the base def `convU` with no variant name at all, so the live
// capture stays exactly what it is today.
// `irSample` / `irLen` are RESOURCE opts (~f2UnitOptsRes above): they name a
// prepared BUFFER, not a graph. irLen is the END trim — the end of an IR is the
// reverb's length and is what anyone reaches for; the head of an IR is the
// direct sound, and trimming THAT is an expert move that needs a display to
// justify it. It is an opt and not a knob because every commit re-prepares the
// spectrum buffer: a knob a user can sweep that stutters the sound is worse
// than a spinner that commits on pointer release (samplerU's `onsetSens`
// idiom, debounced 150 ms).
~f2UnitOpts[\convU] = (
	ir:       (values: #['bus', 'sample'], def: 'bus', label: "IR"),
	irSample: (values: #[], def: '', label: "impulse", kind: \sample, res: true),
	irLen:    (kind: \num, min: 1, max: 100, step: 1, unit: "%", def: '100',
		label: "IR len", res: true)
);
// Only the control this stage introduces: no processor has a ~f2UnitSpecs entry
// yet (every processor knob is still guessed from its SynthDesc default by the
// front's fallbackSpec), and an entry is read per PARAM — specFor falls through
// to that guess for every key not named here, so a partial table changes
// nothing else on the card. preDly earns one: its default is 0, which tells the
// guess nothing at all, and the graph clips it to the 0…0.2 s the delay line is
// sized for.
~f2UnitSpecs[\convU] = (
	preDly: (min: 0, max: ~f2ConvPreMax, warp: \lin, unit: "s", label: "predly")
);

// True convolution, in two modes that share one card.
//
// `ir: bus` — a LIVE kernel, and the thing this unit owns that a plug-in
// cannot do. srcIn = the long/texture signal, kerIn = the percussive hit. On
// each trigger (gate edge / t_trig) the unit RECORDS kSpan seconds of kerIn
// from that moment (co-timed with the hit's cell = the transient itself), then
// swaps it in as the convolution kernel: the texture is filtered through the
// hit's spectrum — "the room is made of the drum". Kernel window is 4096
// samples (~90 ms); kSpan < 1 shortens it (tighter, brighter kernel). kGain
// compensates convolution level loss. UNCHANGED since v48, deliberately:
// sc/nrt/convab.scd renders this path through the PREVIOUS build and through
// this one and requires max |Δ| == 0 at preDly 0 — the owner's «continuous,
// as it is now», in numbers rather than in intent.
//
// `ir: sample` — an impulse response from a FILE through PartConv, the ordinary
// half of the device: the IR is read at the `irLen` trim, levelled and prepared
// once (~f2ConvIrAt), and the card reads the resulting bufnum in `irBuf`.
// kerIn / kSpan have nothing to record here and the card greys them; irBuf
// carries the null IR (pass-through) until the real one lands. PartConv costs
// one partition of LATENCY — 960 samples at fft 2048, 20 ms at 48 k — which
// Convolution2 does not; preDly adds to that rather than replacing it.
//
// preDly is on the WET path of BOTH variants: it is the one control that puts a
// convolution BEHIND the source instead of on top of it, and unlike the trim it
// is live-safe — a delay line is modulatable like any knob. It sits behind a
// Select.ar rather than always running through DelayN because DelayN with a
// NON-CONSTANT delaytime clamps to a one-sample minimum (measured: the bus
// render came back exactly one sample late at preDly 0), and one sample is
// enough to break the null this file promises the bus mode.
~f2UnitGen[\convU] = { |opts, name|
	var o = opts ? ();
	var mode = (((o[\ir] ? o["ir"]) ? 'bus').asSymbol);
	var fft = (topEnvironment[\f2ConvFft] ? 2048);
	var preMax = (topEnvironment[\f2ConvPreMax] ? 0.2);
	SynthDef(name, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
		srcIn = -1, chainIn = -1, kerIn = -1, inGain = 1, inDamp = 0, inSat = 0,
		kSpan = 1, kGain = 1, mix = 1, preDly = 0, irBuf = -1,
		atk = 0.005, dec = 0.05, sus = 1, rel = 0.4, curve = -4, telId = 0,
		eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
		var g    = gate;
		var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
		var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
		var inp  = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
		var wet, wetD, sig;
		if (mode == 'sample') {
			// mono IR ⇒ one PartConv per channel (multichannel expansion over the
			// stereo `inp`). irBuf < 0 = nothing prepared AND no null IR to stand
			// in: the wet path is muted rather than handed a bufnum that is not a
			// prepared spectrum.
			wet = PartConv.ar(inp, fft, irBuf.max(0)) * kGain.clip(0.1, 8) * (irBuf >= 0);
		} {
			var kbuf = LocalBuf(4096, 1).clear;
			var ker  = (~f2CondIn.(InFeedback.ar(kerIn.max(0), 2).sum * 0.5, inGain, inDamp, inSat) * (kerIn >= 0));
			var trig = (Trig.kr(g, 0.001) + Trig.kr(t_trig, 0.001)).min(1);
			var kdur = (4096 * kSpan.clip(0.1, 1)) / SampleRate.ir;
			// the core's recording: strictly AFTER the trigger, kdur seconds from the start of the
			// buffer (no ring — the core is always in the right order, transient at the head)
			var rec  = Trig1.ar(K2A.ar(trig), kdur);
			// idle (rec=0) — the phase is outside the buffer: BufWr with loop:0 does NOT write there
			// (otherwise an idle voice would forever wipe the core's head with zeroes)
			var wpos = (Phasor.ar(K2A.ar(trig), 1, 0, 4097).min(4095) * rec) + ((1 - rec) * 5000);
			var w    = BufWr.ar(ker * rec, kbuf, wpos, 0);
			// the core is swapped when the recording HAS FINISHED (the rec fall): the fresh hit is
			// already in the buffer by then
			var kswp = Trig.ar(1 - rec, 0.001);
			wet = Convolution2.ar(inp, kbuf, kswp, 4096) * 0.02 * kGain.clip(0.1, 8);
		};
		wetD = Select.ar(preDly > 0, [wet, DelayN.ar(wet, preMax, preDly.clip(0, preMax))]);
		sig  = XFade2.ar(inp, wetD.tanh * env, (mix.clip(0, 1) * 2) - 1);
		SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
		Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
	});
};
// The BASE def is the `bus` graph: the store drops an opt equal to its schema
// default, so a card at `ir: bus` carries no `ir` key, ~f2UnitVariantName
// answers `convU`, and nothing is built on demand for the mode that has always
// been here. `convU__ir_sample` is built on demand by ~f2UnitDef / ~f2UnitEnsure.
~f2UnitGen[\convU].value((), \convU).add;

// Two-input spectral cross-synthesis: carIn = the texture, modIn = the hit.
// xmode crossfades three vanilla-PV combinations:
//   0 = magMul (spectral AND — only what BOTH share survives; dark, the true
//       "convolution in the spectrum" — lift with kGain-style eqHi),
//   1 = copyPhase (texture magnitudes with the hit's PHASES — pixelated,
//       granular ghost of the texture snapped to the hit),
//   2 = max (spectral UNION — glassy merge of both).
SynthDef(\xspecU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	carIn = -1, chainIn = -1, modIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	xmode = 0, mix = 1,
	atk = 0.005, dec = 0.05, sus = 1, rel = 0.4, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g    = gate;
	var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env  = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var car  = ~f2CondIn.((InFeedback.ar(carIn.max(0), 2) * (carIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var mod  = ~f2CondIn.(InFeedback.ar(modIn.max(0), 2).sum * 0.5, inGain, inDamp, inSat) * (modIn >= 0);
	var monoC = car.sum * 0.5;
	var cA = FFT(LocalBuf(2048), monoC);
	var cB = FFT(LocalBuf(2048), mod);
	// PV chains are destructive: every combination gets its own copy of the quarry
	var c1 = PV_Copy(cA, LocalBuf(2048));
	var c2 = PV_Copy(cA, LocalBuf(2048));
	var c3 = PV_Copy(cA, LocalBuf(2048));
	var b2 = PV_Copy(cB, LocalBuf(2048));
	var b3 = PV_Copy(cB, LocalBuf(2048));
	var wMul   = IFFT(PV_MagMul(c1, cB)) * 0.5;
	var wPhase = IFFT(PV_CopyPhase(c2, b2));
	var wMax   = IFFT(PV_Max(c3, b3));
	var wet    = SelectX.ar(xmode.clip(0, 2), [wMul, wPhase, wMax]);
	var sig    = XFade2.ar(car, (wet ! 2) * env, (mix.clip(0, 1) * 2) - 1);
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// Onset-triggered granular scatter: srcIn = the texture (ring-recorded, like
// stutU), trigIn = the percussion. Every detected hit fires a BURST of grains
// read from around the moment of the hit (look reaches back into the past):
// the texture shatters into a percussive cloud exactly on the rhythm of the
// hits. nGrain per burst over scat seconds; pDisp = pitch spray; gDur = grain
// length. Own gate edges also fire a burst (works without trigIn too).
SynthDef(\scatU, { |out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2, tel_bus = 0,
	srcIn = -1, chainIn = -1, trigIn = -1, inGain = 1, inDamp = 0, inSat = 0,
	nGrain = 6, scat = 0.12, gDur = 0.09, pDisp = 0.15, look = 0, threshold = 0.3, wide = 0.7,
	atk = 0.002, dec = 0.05, sus = 1, rel = 0.4, curve = -4, telId = 0,
	eqLo = 1, eqMid = 1, eqHi = 1, eqLoF = 200, eqHiF = 3000|
	var g      = gate;
	var envG   = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), g, doneAction: i_free);
	var env    = Select.kr(chainIn >= 0, [envG, 1]);   // §cards pass-through: in a strip the ADSR does not shape the stream
	var frames = 65536;
	var buf    = LocalBuf(frames, 1).clear;
	var inp    = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) * (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat);
	var mono   = inp.sum * 0.5;
	var wr     = Phasor.ar(0, 1, 0, frames);
	var rec    = BufWr.ar(mono, buf, wr);
	var hitSrc = ~f2CondIn.(InFeedback.ar(trigIn.max(0), 2).sum * 0.5, 1, 0, 0) * (trigIn >= 0);
	var hFast  = Amplitude.ar(hitSrc, 0.0008, 0.05);
	var hSlow  = Amplitude.ar(hitSrc, 0.08, 0.3);
	var hit    = (Trig.ar(hFast > (hSlow + threshold.clip(0.001, 1)), 0.03)
		+ Trig.ar(K2A.ar(Trig.kr(g, 0.001) + Trig.kr(t_trig, 0.001)), 0.03)).min(1);
	// the burst: nGrain grains over `scat` seconds after the hit
	var burst  = Decay.ar(hit, scat.clip(0.01, 0.5));
	var gtrig  = Impulse.ar((nGrain.clip(1, 16) / scat.clip(0.01, 0.5)).min(400)) * (burst > 0.01);
	var w0     = Latch.ar(wr, hit);
	var cpos   = ((w0 - (look.clip(0, 1.3) * SampleRate.ir)
		+ TRand.ar(-0.02, 0.02, gtrig) * SampleRate.ir).wrap(0, frames)) / frames;
	var rate   = (2 ** (TRand.ar(pDisp.neg, pDisp, gtrig) * 2));
	var wet    = GrainBuf.ar(2, gtrig, gDur.clip(0.01, 0.5), buf, rate, cpos, 2,
		TRand.ar(wide.neg, wide, gtrig));
	var sig    = wet * env;
	SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (g > 0)).min(1), '/f2_chan', [env], telId);
	Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * amp, eqLo, eqMid, eqHi, eqLoF, eqHiF))));
}).add;

// ── §flt the FILTER slot and the FEG shared by polysynthU, polymerU, samplerU ─
// One block on three units, the UNION of the contracts (POLYSYNTH.md §1 ∪
// POLYMER.md §1.5 / §1.6, the ten models and the sampler's joining in
// FILTER.md): the MODEL of the slot is the structural opt `filt` (a SynthDef
// variant, «from the next note»), the same eleven values in the same order on
// every card, and every control the slot reads is declared by every def that
// declares the block — a card swapping models moves no knob and breaks no lock
// (CARDS.md §5). What differs per unit stays per unit and is marked where it is
// read: the unit's own default model, and the cutoff BUS feeding the slot —
// polysynthU multiplies factors in Hz under its 20…20000 clip, polymerU sums
// semitones and clips at 0.45·SR (POLYMER.md §2 decision 1), samplerU
// multiplies against the sample ROOT under its `filtKey` alias (FILTER.md §5.2).
// A polysynth save sounds exactly as it did: `poly` IS its old filter, index for
// index — and so does a sampler save: its old filtType 0…7 IS `poly` 0…7, BELL
// included, and its OFF is `filtOn` 0 (FILTER.md §5.3).
~f2FltModels = #[\poly, \ld, \mg, \sk, \svf, \comb, \xp, \vowels, \fizz, \rasp, \ripple];
// Per unit, the models with an arm in ~f2FltSlot; the FIRST entry is the unit's
// own default and the one the generator falls back to for a value it has no arm
// for — the mirror of the front's UNIT_BUILT[unit].filt, whose first entry the
// card prints on the slot button, so the two must not drift. All eleven are
// built on all three units: `poly` is F2's own model (the RLPF / BPF / RHPF /
// BRF core polysynthU has always had, plus the sampler's Bell), not a Bitwig
// one; the ten Bitwig models are FILTER.md §3's arms below, one function each,
// one signature, and a model lands on EVERY unit that declares the block —
// three lists that differ only in which model comes first (copies: the menu
// is a literal array, and a list a check may sort in place must not be it).
~f2FltBuilt = (
	polysynthU: ~f2FltModels.copy,
	polymerU:   [\ld] ++ ~f2FltModels.reject { |m| m == \ld },
	samplerU:   ~f2FltModels.copy
);
// §sc-deps four of the eleven arms play `SVF`, which is not in the core class
// library (see the capability block at the top of this file). Without it those
// models have no arm, and a model with no arm is exactly what ~f2FltResolve
// already handles: the card is told ONCE and the unit's own default plays. So
// the capability is spent here, on the one table every reader consults, rather
// than in four arms and three menus. With sc3-plugins installed this line
// changes nothing — the reject is empty and each list is its own copy.
if (~f2ExtHas.(\svf).not) {
	var lost = ~f2ExtFltModels[\svf];
	~f2FltBuilt.keysValuesDo { |u, list| ~f2FltBuilt[u] = list.reject { |m| lost.includes(m) } };
	("⚠ [f2 deps] filter models % need SVF (sc3-plugins) and are NOT built — a save asking for one plays the unit's default model".format(lost)).postln;
};
// The CORE of the block (FILTER.md §5.2): what a unit that joins it must declare
// — the model, the switch, the bus knobs and the per-model cells. The synths
// declare ~f2FltSpecs whole; the sampler declares this subset, because Bitwig's
// Sampler has no filter envelope, no filter FM, no shaper and no high-pass and
// F2 invents no DSP to give it them. Every key here is passed to ~f2FltSlot.
~f2FltCore = #[\filtOn, \fltMode, \drive, \cut, \res, \keytrack, \resLimit, \fltLin, \fltMode2,
	\fltFbGain, \fltFbCut, \fltColor, \fltVowel, \bellGain];
// One ROLE under a per-unit KEY: `keytrack` is taken on samplerU by the sample's
// pitch keytrack, so the block's keytrack role is the sampler's own `filtKey`
// (its bus law `(freqG / rootHz)^filtKey`, the sample root as the reference) —
// the mirror of the front's FILT_KEYMAP.samplerU. A lock aimed at
// `<id>.filtKey` keeps its target; renaming the sample keytrack instead is
// FILTER.md §6 Q6.
~f2FltKeyMap = (samplerU: (keytrack: \filtKey));
// The configuration lists the arms index — FILTER.md §3.12, one table: the
// `Select` / `case` order inside each arm IS this order, the front's
// FILT_MODELS[m].modes / .mode2.sel must equal it (the card relabels the
// generic `fltMode` / `fltMode2` cells of ~f2FltSpecs from its copy), and
// sc/nrt/build.scd and sweep.scd iterate it. A value past a list is clamped in
// the arm, never wrapped. `mg` has no list (fltMode unread, the cell greys);
// `ld` reads 24 dB at index 0 because every polymer save plays MoogFF = 24 dB
// there (§6 Q2 — a reorder moves no save, a per-model default would need a
// per-unit exception). Rasp's fltMode2 DEFAULT is index 1 (DOUBLE): the card
// seeds it on a switch to `rasp` (§4.1), the arm clamps whatever is stored.
~f2FltModeSel = (
	poly:   #["LP2", "LP4", "BP2", "BP4", "HP2", "HP4", "NOTCH", "BELL"],
	ld:     #["24dB", "18dB", "12dB", "6dB"],
	mg:     #[],
	sk:     #["LP 1ᴾ", "LP 2ᴾ", "LP 3ᴾ", "LP 4ᴾ", "LP 6ᴾ", "LP 8ᴾ",
	          "HP 1ᴾ", "HP 2ᴾ", "HP 3ᴾ", "HP 4ᴾ", "HP 6ᴾ", "HP 8ᴾ",
	          "BP 2ᴾ", "BP 4ᴾ", "BP 6ᴾ", "BP 8ᴾ"],
	svf:    #["LP", "BP", "HP", "NOTCH"],
	comb:   #["+FB", "−FB"],
	// the three combinations spelled as Bitwig's chooser prints them (`HP 1ᴾ + LP 2ᴾ`,
	// FILTER.md §4.1 ✓ [FIG]) — the front's FILT_MODELS.xp.modes is this list to the glyph
	xp:     #["LP 1ᴾ", "LP 2ᴾ", "LP 3ᴾ", "LP 4ᴾ", "HP 1ᴾ", "HP 2ᴾ", "HP 3ᴾ", "HP 4ᴾ",
	          "BP 2ᴾ", "BP 4ᴾ", "Peak", "Notch", "HP 2ᴾ + LP 1ᴾ", "HP 1ᴾ + LP 2ᴾ", "HP 1ᴾ + LP 3ᴾ"],
	vowels: #["CASC", "LP/BP", "LP/BP/HP"],
	fizz:   #["STD", "ALT"],
	rasp:   #["LP", "BP"],
	ripple: #["EARTH", "WIND", "FIRE"]
);
~f2FltMode2Sel = (
	vowels: #["W1", "W2", "F", "M1", "M2", "M", "KIDS"],
	rasp:   #["SHIFT", "DOUBLE", "GRAVITY"],
	ripple: #["—", "FB", "FF", "FB+FF"]
);
// ── the vowel datasets, baked (FILTER.md §2.7, §3.7) ─────────────────────────
// Seven profiles × 27 IPA slots × four formants, each (F Hz, BW Hz, A dB).
// Bitwig never names its studies (§2.7 «source ?»), so the content is §3.7's
// provisional reading, quoted from memory of the published tables and marked
// VERIFY BEFORE SHIPPING as that section demands: Men 1 / Women 1 / Kids ←
// Peterson & Barney 1952 (F1–F3; F4 = 3300 / 3800 / 4300 Hz where the study
// stops, ?), Men 2 / Women 2 ← Hillenbrand et al. 1995 (F1–F4), Female / Male
// («one individual» — no candidate) ← the Csound / CLM soprano and bass
// tables, their own bandwidths and amplitudes. Bandwidths for the studies are
// Klatt 1980's defaults 60 / 90 / 150 / 200 Hz (~), amplitudes 0 / −6 / −12 /
// −18 dB per formant (?) — the parallel topologies read them, the cascade does
// not (Klatt's rule: amplitudes fall out of the chain).
//
// The 27 slots are FILTER.md §2.7's list, 0-based, in the guide's order — the
// IPA quadrilateral row by row minus ʊ. Each carries its chart position
// (height 0 close … 3 open, backness 0 front … 2 back, rounded) so that a slot
// the English-only studies do not cover is SYNTHESISED from the profile's own
// measured rows (~f2VowelSynth below — a Gaussian blend in chart space, the
// anchors un-rounded first, rounding then lowering F2 by 12 % and F3 by 5 %:
// §3.7's «F1 from height, F2 from backness, rounding lowers F2 ≈ 10–15 %»,
// all ?). Slot 6 is printed ɯ in the guide but glossed «hook / book» — ʊ's
// words — so it carries ʊ's measured data and ʊ's chart position (§2.7's
// note). No control reaches a synthesised slot today: F2's fixed path is
// i – ɛ – ɑ – ɔ – u, all five measured in both studies (§6 Q10).
~f2VowelIpa = [
	//  glyph  height backness rounded          (index)
	["i", 0, 0, 0],     ["y", 0, 0, 1],     ["ɪ", 0.5, 0.5, 0], ["ʏ", 0.5, 0.5, 1],   //  0… 3
	["ɨ", 0, 1, 0],     ["ʉ", 0, 1, 1],     ["ɯ", 0.5, 1.5, 1], ["u", 0, 2, 1],       //  4… 7  (6 = ʊ's data)
	["e", 1, 0, 0],     ["ø", 1, 0, 1],     ["ɘ", 1, 1, 0],     ["ɵ", 1, 1, 1],       //  8…11
	["ɣ", 1, 2, 0],     ["o", 1, 2, 1],     ["ə", 1.5, 1, 0],   ["ɛ", 2, 0, 0],       // 12…15
	["œ", 2, 0, 1],     ["ɜ", 2, 1, 0],     ["ɞ", 2, 1, 1],     ["ʌ", 2, 2, 0],       // 16…19
	["ɔ", 2, 2, 1],     ["æ", 2.5, 0, 0],   ["ɐ", 2.5, 1, 0],   ["a", 3, 0, 0],       // 20…23
	["Œ", 3, 0, 1],     ["ɑ", 3, 2, 0],     ["ɒ", 3, 2, 1]                            // 24…26
];
// Rows: [slot, [F1 F2 F3 (F4)]] with the profile's bw / a, or [slot, F, bw, a]
// where the table carries its own. Every number here is `?` (§2.7, §6 Q10).
~f2VowelProfiles = [
	(name: "W1", src: "Peterson & Barney 1952, women", f4: 3800, bw: [60, 90, 150, 200], a: [0, -6, -12, -18], rows: [
		[0, [310, 2790, 3310]], [2, [430, 2480, 3070]], [15, [610, 2330, 2990]], [21, [860, 2050, 2850]],
		[25, [850, 1220, 2810]], [20, [590, 920, 2710]], [6, [470, 1160, 2680]], [7, [370, 950, 2670]], [19, [760, 1400, 2780]]]),
	(name: "W2", src: "Hillenbrand et al. 1995, women", bw: [60, 90, 150, 200], a: [0, -6, -12, -18], rows: [
		[0, [437, 2761, 3372, 4352]], [2, [483, 2365, 3053, 4334]], [8, [536, 2530, 3047, 4319]], [15, [731, 2058, 2979, 4294]],
		[21, [669, 2349, 2972, 4290]], [25, [936, 1551, 2815, 4299]], [20, [781, 1136, 2824, 3923]], [13, [555, 1035, 2828, 3927]],
		[6, [519, 1225, 2827, 4052]], [7, [459, 1105, 2735, 4115]], [19, [753, 1426, 2933, 4092]]]),
	(name: "F", src: "Csound / CLM soprano table (a e i o u → ɑ ɛ i ɔ u and a e o)", rows: [
		[0,  [270, 2140, 2950, 3900], [60, 90, 100, 120], [0, -12, -26, -26]],
		[8,  [350, 2000, 2800, 3600], [60, 100, 120, 150], [0, -20, -15, -40]],
		[15, [350, 2000, 2800, 3600], [60, 100, 120, 150], [0, -20, -15, -40]],
		[23, [800, 1150, 2900, 3900], [80, 90, 120, 130], [0, -6, -32, -20]],
		[25, [800, 1150, 2900, 3900], [80, 90, 120, 130], [0, -6, -32, -20]],
		[13, [450, 800, 2830, 3800], [70, 80, 100, 130], [0, -11, -22, -22]],
		[20, [450, 800, 2830, 3800], [70, 80, 100, 130], [0, -11, -22, -22]],
		[7,  [325, 700, 2700, 3800], [50, 60, 170, 180], [0, -16, -35, -40]]]),
	(name: "M1", src: "Peterson & Barney 1952, men", f4: 3300, bw: [60, 90, 150, 200], a: [0, -6, -12, -18], rows: [
		[0, [270, 2290, 3010]], [2, [390, 1990, 2550]], [15, [530, 1840, 2480]], [21, [660, 1720, 2410]],
		[25, [730, 1090, 2440]], [20, [570, 840, 2410]], [6, [440, 1020, 2240]], [7, [300, 870, 2240]], [19, [640, 1190, 2390]]]),
	(name: "M2", src: "Hillenbrand et al. 1995, men", bw: [60, 90, 150, 200], a: [0, -6, -12, -18], rows: [
		[0, [342, 2322, 3000, 3657]], [2, [427, 2034, 2684, 3618]], [8, [476, 2089, 2691, 3649]], [15, [580, 1799, 2605, 3677]],
		[21, [588, 1952, 2601, 3624]], [25, [768, 1333, 2522, 3687]], [20, [652, 997, 2538, 3486]], [13, [497, 910, 2459, 3384]],
		[6, [469, 1122, 2434, 3400]], [7, [378, 997, 2343, 3357]], [19, [623, 1200, 2550, 3557]]]),
	(name: "M", src: "Csound / CLM bass table (a e i o u → ɑ ɛ i ɔ u and a e o)", rows: [
		[0,  [250, 1750, 2600, 3050], [60, 90, 100, 120], [0, -30, -16, -22]],
		[8,  [400, 1620, 2400, 2800], [40, 80, 100, 120], [0, -12, -9, -12]],
		[15, [400, 1620, 2400, 2800], [40, 80, 100, 120], [0, -12, -9, -12]],
		[23, [600, 1040, 2250, 2450], [60, 70, 110, 120], [0, -7, -9, -9]],
		[25, [600, 1040, 2250, 2450], [60, 70, 110, 120], [0, -7, -9, -9]],
		[13, [400, 750, 2400, 2600], [40, 80, 100, 120], [0, -11, -21, -20]],
		[20, [400, 750, 2400, 2600], [40, 80, 100, 120], [0, -11, -21, -20]],
		[7,  [350, 600, 2400, 2675], [40, 80, 100, 120], [0, -20, -32, -28]]]),
	(name: "KIDS", src: "Peterson & Barney 1952, children", f4: 4300, bw: [60, 90, 150, 200], a: [0, -6, -12, -18], rows: [
		[0, [370, 3200, 3730]], [2, [530, 2730, 3600]], [15, [690, 2610, 3570]], [21, [1010, 2320, 3320]],
		[25, [1030, 1370, 3170]], [20, [680, 1060, 3180]], [6, [560, 1410, 3310]], [7, [430, 1170, 3260]], [19, [850, 1590, 3360]]])
];
// A slot with no measured row: the profile's own rows blended by chart
// distance (σ² = 0.5 chart units²), log-domain for F and BW, linear in dB for
// A — the same domains the morph interpolates in, so a synthesised vowel sits
// where the chart puts it between the measured ones, never at a Hz average
// no mouth makes (§3.7). Rounded anchors are un-rounded before the blend and
// the target re-rounded after, so «u» and «i» both inform «y».
~f2VowelSynth = { |meas, v|
	var h = ~f2VowelIpa[v][1], b = ~f2VowelIpa[v][2], r = ~f2VowelIpa[v][3];
	var wsum = 0, lf = 0 ! 4, lbw = 0 ! 4, la = 0 ! 4;
	meas.do { |m|
		var mi = m[\idx], mh = ~f2VowelIpa[mi][1], mb = ~f2VowelIpa[mi][2], mr = ~f2VowelIpa[mi][3];
		var w = exp(((h - mh).squared + (b - mb).squared).neg / 0.5);
		var f = m[\f].copy;
		if (mr == 1) { f[1] = f[1] / 0.88; f[2] = f[2] / 0.95 };
		wsum = wsum + w;
		lf = lf + (f.log2 * w); lbw = lbw + (m[\bw].log2 * w); la = la + (m[\a] * w);
	};
	lf = (lf / wsum).collect { |x| 2 ** x }; lbw = (lbw / wsum).collect { |x| 2 ** x }; la = la / wsum;
	if (r == 1) { lf[1] = lf[1] * 0.88; lf[2] = lf[2] * 0.95 };
	[lf.round(1), lbw.round(1), la.round(0.1), "synth"]
};
// ~f2VowelTable[profile][slot] = [F(4), BW(4), A(4), "meas" | "synth"]
~f2VowelTable = ~f2VowelProfiles.collect { |p|
	var meas = p[\rows].collect { |r|
		var f = r[1].copy; if (f.size < 4) { f = f.add(p[\f4]) };
		(idx: r[0], f: f, bw: r[2] ? p[\bw], a: r[3] ? p[\a])
	};
	27.collect { |v|
		var m = meas.detect { |e| e[\idx] == v };
		if (m.notNil) { [m[\f], m[\bw], m[\a], "meas"] } { ~f2VowelSynth.(meas, v) }
	}
};
// The fixed path (§6 Q10's recommendation): i – ɛ – ɑ – ɔ – u at fltVowel
// −1 / −0.5 / 0 / +0.5 / +1, the five Vowel Positions F2 does not expose.
~f2VowelPath = #[0, 15, 25, 20, 7];
// What the SynthDef carries: only the path's five vowels per profile, as three
// (F, BW, A) × four formant tables of 35 constants each, indexed
// `profile × 5 + position` — 420 constants and 24 Select.kr per voice, against
// the 2268 constants and 756-input Selects of the whole 27-slot table (§3.7's
// count), which no control could reach. The full table stays baked above for
// the day a positions opt wants it.
~f2VowelFlat = 3.collect { |q| 4.collect { |n| ~f2VowelTable.collect { |prof| ~f2VowelPath.collect { |v| prof[v][q][n] } }.flat } };
// The morph (§3.7), on UGens or on plain numbers — `sel.(idx, table)` is
// Select.kr in the arm and an array read in a check, so the numbers a
// measurement compares against are this same formula. Position space
// u = (x + 1) × 2 ∈ 0…4; L = the left vowel, t the blend; F and BW interpolate
// in log2, A linearly in dB. Tuning: ratio = cutA / 2000 — the Cutoff Pitch
// Offset in semitones with the knob's 2000 Hz default as «0 st», so a save at
// the default plays the dataset untransposed; BW stays in Hz, NOT scaled with
// the ratio (§3.7 — what makes the offset «like moving the cutoff … but
// different»: a bank transposed up gets sharper). Resonance: k = 10^(2·res − 1),
// a Q multiplier 0.1…10 with res 0.5 = ×1 = the dataset's own bandwidths.
~f2VowelMorph = { |sel, flat, m2, x, res, ratio, sr|
	var u  = (x.clip(-1, 1) + 1) * 2;
	var lft = u.floor.min(3);           // the left position; the top blends 3 → 4 at t = 1, never reads a sixth slot
	var t  = u - lft;
	var iL = (m2 * 5) + lft, iR = iL + 1;
	var k  = 10 ** ((2 * res.clip(0, 1)) - 1);
	4.collect { |n|
		var fL = sel.(iL, flat[0][n]), fR = sel.(iR, flat[0][n]);
		var bL = sel.(iL, flat[1][n]), bR = sel.(iR, flat[1][n]);
		var aL = sel.(iL, flat[2][n]), aR = sel.(iR, flat[2][n]);
		var f  = (fL * ((fR / fL) ** t) * ratio).clip(20, 0.45 * sr);
		var bw = (bL * ((bR / bL) ** t)) / k;
		var a  = aL + ((aR - aL) * t);
		(f: f, bw: bw, a: a, rq: bw / f)
	}
};

// The model a variant builds: `filt` out of opts, or the unit's own default
// when the key is absent — chainSetOpt drops a value equal to the schema
// default, so a polysynth card with no `filt` key is `poly` and its variant is
// still `polysynthU` / `polysynthU__v1_4__v2_1`, the def name every save
// resolves to today. Every advertised value has an arm on every unit, so the
// fallback is for a value the list does not carry (a hand-edited save, a front
// ahead of the engine): the unit's first built model, said ONCE per (unit,
// value) — the §6.1 idiom, because a silent swap reads as «the filter sounds a
// bit plain» to whoever hears a ladder where they picked Vowels. The key
// prefix is per unit (`pm_` / `poly_` / `smp_`) because the offline check
// counts each unit's warnings.
~f2FltResolve = { |unit, opts, name|
	var u = unit.asSymbol;
	var built = topEnvironment[\f2FltBuilt][u] ? #[\poly];
	var want = ((opts !? { |o| o[\filt] }) ? built.first).asSymbol;
	var tag = (polysynthU: "poly", polymerU: "pm", samplerU: "smp")[u] ? u.asString;
	if (built.includes(want)) { want } {
		topEnvironment[\f2UnitWarnOnce].value((tag ++ "_filt_" ++ want).asSymbol,
			"⚠ [f2 %] filt: % is % — % is built as %".format(tag, want,
				if (topEnvironment[\f2FltModels].includes(want)) { "advertised but has no arm on this unit (~f2FltBuilt)" } { "not an advertised value" },
				name, built.first));
		built.first
	}
};
// The FEG (§1.6): Env.adsr at kr, curve −4 — Analog's fixed curve, model A of
// `fEnvModel`, the one both units have always had (R and D are §6.5) — gated by
// the note and NOT holding the voice alive: the AEG's doneAction does that, so
// a release longer than the AEG's simply stops being heard. kr and not ar
// because nothing audio-rate reads it (the cutoff bus is exponentiated once per
// block on both units). Returned already scaled by the velocity depth
// `(1 − fVel + fVel·vel)` — polysynthU's law, a ×1 exactly at fVel 0, which is
// polymerU's default, so a polymer save moves by nothing. The clips are the
// polymer form: an out-of-range mod must not hand EnvGen a negative time.
~f2Feg = { |gate, fAtk, fDec, fSus, fRel, fVel, vel|
	var env = EnvGen.kr(Env.adsr(fAtk.clip(0.001, 8), fDec.clip(0.01, 8),
		fSus.clip(0, 1), fRel.clip(0.01, 8), 1, -4), gate);
	var fv  = fVel.clip(0, 1);
	env * (1 - fv + (fv * vel.clip(0, 1)))
};
// ── §flt the ten Bitwig arms — FILTER.md §3.1 … §3.10, one function each ─────
// Each arm is a function whose arguments are the twelve names of ~f2FltSlot's
// arm contract below (pre, cutA, res, fltMode, then the eight per-model cells
// in the order the slot declares them) and whose value is the stereo model
// output; the slot's `case` clause is the call site and nothing else. Every
// cell may arrive as a kr Control or as a plain number (the sampler passes
// zeros for the paths it does not declare), so no arm compares a cell with `<`
// or `>=` — a Boolean would not build — every flag is a Select.kr table or
// arithmetic. Each header states what its arm takes from the contract as
// written, where it deviates and why, and what it was measured to;
// sc/nrt/sweep.scd renders every configuration of every arm through the units.
// ld — the closed-form ladder with taps (FILTER.md §3.1, H1 per §6 Q1).
// Feedback k closed round ALL FOUR one-pole stages and the output read at
// tap n: H_n(s') = (1+s')^(4−n) / ((1+s')⁴ + k). The denominator factorises
// into two real quadratics whose poles are the four roots of (1+s')⁴ = −k
// (r = k^¼: pair A at −1 + r/√2 ± j r/√2, pair B at −1 − r/√2 ± j r/√2), so
// every slope shares ONE resonant pole pair and the tap only changes the
// numerator — a live Select over six kr coefficients, no rebuild. Bilinear
// with prewarp kt = tan(π fc/SR): a retained stage is the factor (1 + z⁻¹), a
// removed one the image of its zero, ((1+kt) + (kt−1) z⁻¹)/kt; both are 2 at
// DC so each SOS keeps unit DC gain and the ladder's 1/(1+k) is applied once
// — the bass loss IS the character, never compensated. At the 24 dB tap this
// is MoogFF's transfer function to the letter: MoogFF's stage is the same
// bilinear one-pole (b0 = kt/(kt+1), a1 = (kt−1)/(kt+1), FilterUGens.cpp)
// closed in the same loop, solved per sample instead of iterated, so
// G⁴/(1 + kG⁴) = 1/((1+s')⁴ + k) is one rational function computed two ways
// and the two differ by rounding (measured: ≤ 5e-7 on a saw at 1 kHz, up to
// 2e-4 below 100 Hz where float32 kr coefficients pinch a direct form). Two
// ways, and the arm uses both. Through res 0.9 the 24 dB tap IS MoogFF — the
// UGen every polymer save plays, fed the same wires and the same k, so a save
// at fltMode 0 renders bit for bit what it did (measured: max|ld −
// MoogFF| = 0 on the whole cut × res grid through res 0.9). MoogFF clips k
// to 4 and so cannot swell into the knee at res 1, so over res 0.9…1 the tap
// fades to the closed form of the same transfer function, which carries the
// 0.5 % overdrive and settles on the AGC (the fade is an exact 0 below 0.9:
// `y4 + 0·(…)` is y4 to the bit). That closed form puts its gains at the SOS
// INPUT so its states stay at signal scale: it then takes a cutoff jump as
// MoogFF does (measured, ×1.5 on four octaves in one block), where the
// same gains in the numerator burst ×14. The three tapped slopes are not
// numerators at all but the ladder's own tap points: what enters stage 1 is
// the feedback junction u − k·y4, and the tap after n stages is that signal
// through n of MoogFF's own bilinear one-poles (FOS) — H1's physics to the
// letter, G^n·(1 − k·H4) = (1+s')^(4−n)/((1+s')⁴ + k), with states that are
// stage outputs and so jump as MoogFF's do, unlike a numerator with zeros at
// the cutoff (the SOS-tapped build measured ×9…×14 on the same jump).
// Everything runs always (a live Select, POLYMER.md §3's rule), so a slope
// switch mid-note lands on a warm filter. The per-sample loops live inside
// MoogFF, the SOS and the FOS (rule 1); the only thing that crosses a block
// boundary is the AGC, on purpose (rule 4).
~f2FltArmLd = { |pre, cutA, res, fltMode, fltLin = 0, resLimit = 1, fltMode2 = 0, fltFbGain = 0,
		fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6|
	var sr    = SampleRate.ir;
	// coefficients at kr, read once per block (rules 5 / 6): the first sample of
	// an ar bus is exactly what MoogFF's IN0 read gave the same wire on
	// polysynthU, so a save's sweep keeps its cutoff per block; SOS then ramps
	// the coefficients across the block (SOS_next_k) where MoogFF steps them —
	// the one place the two differ during a sweep, measured
	var fcK   = if (cutA.rate == \audio) { A2K.kr(cutA) } { cutA };
	var kt    = (fcK * pi / sr).tan;
	var kt2   = kt * kt;
	var rs    = res.clip(0, 1);
	// Resonance Limit as a LEVEL: the amplitude at which the loop gain starts
	// to compress (FILTER.md §1.2 «L, the level where the loop gain
	// compresses»); the linexp map 0.05…1 is the contract's `?`
	var lim   = resLimit.clip(0, 1).linexp(0, 1, 0.05, 1);
	// The overdrive past k = 4 that lets the oscillation grow into the AGC
	// knee (the contract's 0.5 %) fades in over res 0.9…1: below 0.9 the loop
	// gain is 4·res EXACTLY — MoogFF's k, what every polymer save plays — and
	// only the top of the knob sings. A constant 4.02·res would move every
	// save's peak by 0.5 % of k for nothing.
	var k     = rs * 4 * (1 + (0.005 * ((rs - 0.9) * 10).clip(0, 1)));
	// The AGC's loop gain per block. A change of k moves the loop's amplitude
	// by beta = ¼·ωc·T per block (T = one control block, the growth rate of the
	// pole pair at −1 + r/√2): 0.2 at 100 Hz, 10 at 5 kHz. A knee read one
	// block late with a per-block gain above one over-corrects and pumps (the
	// literal `min(1, L/A)` at 2…12 kHz: 4…8 dB of ripple, never settling at
	// 5 kHz, measured with the literal knee), so the knee's exponent is
	// p = 1/beta above ~480 Hz — deadbeat: one block's correction equals one
	// block's overshoot — and the contract's hard knee (p = 1) below it, where
	// beta is already under one.
	var beta  = (fcK * 2pi * ControlDur.ir * 0.25).max(1e-6);
	var p     = beta.reciprocal.min(1);
	// the AGC's one-block memory: the previous block's log-gain (≤ 0) in a
	// per-voice LocalBuf frame, read before it is written so the write lands
	// one block later. NOT a LocalIn.kr: a def has ONE kr LocalIn/LocalOut pair
	// (a second is silently zeroed — IOUGens.cpp LocalIn_Ctor) and a unit may
	// own it (grainU does); a buffer frame has no such limit and the BufWr is
	// ordered after the BufRd by the graph's own dependencies. `.clear` returns
	// the LocalBuf itself; a bare `ClearBuf(buf)` outputs 0 (DelayUGens.cpp
	// ClearBuf_Ctor: OUT0 = 0), which would address global buffer 0 and leave
	// the regulator inert — the previous draft's silent failure.
	var mem   = LocalBuf(1, 1).clear;
	var lg    = BufRd.kr(1, mem, 0, 0, 1);
	var kEff  = (k * lg.exp).max(0);
	// the two pole pairs of (1+s')⁴ + kEff, bilinear with prewarp (§3.0 rule 2)
	var r     = kEff ** 0.25;
	var rq    = r * 0.7071067811865476;
	var aA    = rq - 1;
	var aB    = rq.neg - 1;
	var cA    = 1 - (r * 1.4142135623730951) + (r * r);
	var cB    = 1 + (r * 1.4142135623730951) + (r * r);
	var d0A   = 1 - (2 * aA * kt) + (cA * kt2);
	var d0B   = 1 - (2 * aB * kt) + (cB * kt2);
	var b1A   = (2 - (2 * cA * kt2)) / d0A;
	var b2A   = (1 + (2 * aA * kt) + (cA * kt2)).neg / d0A;
	var b1B   = (2 - (2 * cB * kt2)) / d0B;
	var b2B   = (1 + (2 * aB * kt) + (cB * kt2)).neg / d0B;
	// the closed form's gain: unit DC gain per section (numerators 1, 2, 1)
	// and the ladder's 1/(1+k), all at kr and applied once at the SOS input
	var g24   = cA * kt2 / d0A / (1 + kEff) * cB * kt2 / d0B;
	// MoogFF's own stage as a FOS: y = a·x + a·x1 + b·y1, the bilinear one-pole
	// b0 = kt/(kt+1), −a1 = (1−kt)/(1+kt) of FilterUGens.cpp
	var a1p   = kt / (1 + kt);
	var b1p   = (1 - kt) / (1 + kt);
	var m     = fltMode.round(1).clip(0, 3);
	// the drive's nonlinearity BEFORE the low-pass (rule 3): the identity to
	// +6 dBFS and a tanh knee above it (ceiling +9.5 dBFS), the same knee level
	// as mg's mix-buss saturator so the two Drive knobs bite at one place. Not
	// the contract's bare `pre.tanh`: the polymer saw table is normalised to a
	// peak of 1 and tanh(1) = 0.76 would have recoloured every polymer save at
	// drive 0 (a probe with the bare tanh measured it). Below the knee the arm is
	// the linear ladder to the sample; at +24 dB (×16) it is fully saturated.
	var thr   = 2;
	var uc    = pre.clip2(thr);
	var u     = uc + (pre - uc).tanh;
	// the 24 dB tap: MoogFF through res 0.9 (every save's sound, to the bit),
	// fading to its closed form over res 0.9…1 so the top of the knob can
	// swell into the knee — MoogFF clips k to 4 and would only ring at the
	// level a note leaves it. The closed form's gains sit at the SOS input
	// (numerators 1, 2, 1): its states then stay at signal scale and a cutoff
	// jump costs what MoogFF's costs (measured), where the same gains in
	// the numerator burst ×14 on a four-octave jump at res 0.9.
	var fade  = ((rs - 0.9) * 10).clip(0, 1);
	var y4    = MoogFF.ar(u, cutA, kEff);
	var y24   = SOS.ar(SOS.ar(u * g24, 1, 2, 1, b1A, b2A), 1, 2, 1, b1B, b2B);
	var ySrc  = y4 + (fade * (y24 - y4));
	// the tap points: the feedback junction through one, two, three stages —
	// tap table (H1) in FILT_MODELS.ld.modes order 24dB 18dB 12dB 6dB
	var fbj   = u - (kEff * ySrc);
	var y1    = FOS.ar(fbj, a1p, a1p, b1p);
	var y2    = FOS.ar(y1, a1p, a1p, b1p);
	var y3    = FOS.ar(y2, a1p, a1p, b1p);
	var y     = Select.ar(m, [ySrc, y3, y2, y1]);
	// the AGC (rule 4): the loop's own level, previous block, both channels
	// matched by taking the louder; kEff = k·min(1, L/A)^p one block late.
	// The follower is the contract's (2 ms attack, 10 ms release); measured, it
	// settles the sine +0.3 dB over L at 100…500 Hz and up to +2.3 dB at 5 kHz,
	// where a 2 ms attack reads ~0.77 of the peak — a shorter attack buys back
	// 0.4 dB there and nothing below, so the contract's numbers stand.
	var lvl   = y.asArray.collect { |c| Amplitude.kr(c, 0.002, 0.01) }.reduce(\max);
	var lgNew = ((lim / lvl.max(1e-9)).min(1).log * p).max(-6);
	// Linearity — the resonance saturator's symmetry, faded by res so res 0 is
	// the linear ladder exactly (the contract's `y + res·(sat − y)`). The
	// saturator is a KNEE at L: the identity up to |y| = L and a C¹ soft curve
	// above it (ceiling 1.5 L) — «the point where clipping (and saturation)
	// begins» is then a point, and a save whose ladder output stays under L
	// (resLimit 1 → 0 dBFS) is untouched at every res, where the contract's
	// L·tanh(y/L) compresses a 0.5-peak signal by 8 % (measured with the literal saturator).
	// SYM is the odd knee. ASYM is the same knee pushed 0.3·L up its curve and
	// the offset subtracted, the contract's own construction: the identity for
	// y/L in −1.3…0.7, so the positive half-wave compresses first (even
	// harmonics) and the DC that a real asymmetric loop would carry INTO the
	// loop is blocked after it — this tier cannot detune like a real ladder,
	// and the card says so (FILTER.md §3.1). The blocker is the unit's own
	// 0.9993 (≈ 5 Hz), not the contract's 0.995: at 48 kHz that is a 38 Hz
	// high-pass, which would thin the bass on ASYM — the one effect FILTER.md
	// §1.1 says no source supports. The knee is written in the y domain
	// (clip the signal, not a normalised copy) so that below L it returns y
	// ITSELF and `y + res·(sat − y)` adds an exact zero — `(y / L) · L` would
	// be a rounding away from bit identity on every save.
	var knee  = { |w| var c = w.clip2(lim); c + (((w - c) * (2 / lim)).tanh * (0.5 * lim)) };
	var symS  = knee.(y);
	var asymS = LeakDC.ar(knee.(y + (0.3 * lim)) - (0.3 * lim), 0.9993);
	var sat   = Select.ar(fltLin.round(1).clip(0, 1), [symS, asymS]);
	BufWr.kr([lgNew], mem, 0, 0);
	y + (rs * (sat - y))
};

// mg — MoogFF + the mix-buss saturator on `drive` (FILTER.md §3.2 v1). One
// fixed 4-pole ladder: fltMode is unread (MG documents no configuration list),
// fltLin is not drawn. The saturator is the Minimoog MIXER overdriving the
// ladder: tanh with its knee at +6 dBFS (T = 2 — the contract's `?`; measured,
// a full-scale sine at drive 0 keeps 7.7 % THD, so «transparent» holds below
// about −6 dBFS), first-order antiderivative-antialiased (measured: 2.1 dB
// less alias residual on a 5 kHz sine at +24 dB); Delay1 is feed-forward, no
// loop. What first-order ADAA costs: in its linear regime it IS the two-tap
// average (x + x1)/2, a zero at Nyquist — measured on the arm's response
// −0.3 dB at 4 kHz and −3.0 dB at 12 kHz that MoogFF alone does not have.
// The contract's `?`, kept as given; the plain tanh (a plain-tanh probe)
// has no roll-off and 2.1 dB more alias, and swapping is a five-line edit. The ladder's gain is 4·res and NEVER above 4: MoogFF is a linear
// structure-preserving model with no in-loop clip, so gain > 4 grows without
// bound (RESULTS.txt: +32 dB at gain 4.4) and MoogFF itself clips k to 4. At
// res 1 it is marginal: a kick rings at its own level for ever (measured: a
// flat envelope, THD 0.00 %, f0 = fc exactly) and a sustained input AT fc
// grows linearly — `resLimit` is an OUTPUT soft limit at L that bounds what
// leaves, because MoogFF has no inside to put it in; it colours nothing in
// the loop, and the card says so.
~f2FltArmMg = { |pre, cutA, res, fltMode, fltLin = 0, resLimit = 1, fltMode2 = 0, fltFbGain = 0,
		fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6|
	var thr  = 2;
	var x    = pre / thr;
	var x1   = Delay1.ar(x);
	var d    = x - x1;
	// F = log cosh, in the overflow-safe form |v| + log(1 + e^(−2|v|)) − log 2:
	// cosh(v) is inf past |v| ≈ 89 in float32 and inf − inf is the NaN a +24 dB
	// polysynth with `fb` could reach. F(x1) is F(x) delayed — F is memoryless,
	// so one Delay1 replaces a second six-op evaluation (Delay1's first output
	// is its first input, so x1 = x on the first sample either way)
	var lc   = { |w| var a = w.abs; a + ((a * -2).exp + 1).log - 0.6931471805599453 };
	var fx   = lc.(x);
	var fx1  = Delay1.ar(fx);
	// the antiderivative form loses precision when the two F's nearly cancel
	// (float32 wires: ~1e-6 absolute on an F of ~8), so below a 1e-2 step the
	// midpoint tanh is both more accurate (its error is ~Δ²/24) and alias-free
	// enough; the contract's 1e-4 threshold would divide that rounding by 1e-4
	var mid  = ((x + x1) * 0.5).tanh;
	var adaa = (fx - fx1) / d;
	var sat  = Select.ar(d.abs > 1e-2, [mid, adaa]) * thr;
	var lad  = MoogFF.ar(sat, cutA, res.clip(0, 1) * 4);
	var lim  = resLimit.clip(0.05, 1);
	(lad / lim).tanh * lim
};

// sk — one resonant SVF.ar cell with taps + FOS one-poles (FILTER.md §3.3),
// all sixteen configurations LIVE on fltMode (§6 Q14's recommendation taken),
// ONE resonant cell per configuration — two in series square the peak (+39.6
// dB at res 0.9 against +14, measured there), so the second block of the
// 6ᴾ / 8ᴾ entries and the HP half of the BP entries run at Q 0.5.
//
// §3.3's table is sixteen chains of the SAME three parts in the same order —
// [a non-resonant pre-block] → the resonant cell → [one or two one-poles] —
// that differ only in which parts are present and which tap each cell reads:
//
//   LP 1ᴾ  = cell(LP+BP)r                       HP 1ᴾ  = cell(HP+BP)r
//   LP 2ᴾ  = cell(LP)r                          HP 2ᴾ  = cell(HP)r
//   LP 3ᴾ  = cell(LP)r → lp1                    HP 3ᴾ  = cell(HP)r → hp1
//   LP 4ᴾ  = cell(LP)r → lp1 → lp1              HP 4ᴾ  = cell(HP)r → hp1 → hp1
//   LP 6ᴾ  = [cell(LP)0 → lp1] → LP 3ᴾ          HP 6ᴾ  = [cell(HP)0 → hp1] → HP 3ᴾ
//   LP 8ᴾ  = [cell(LP)0 → lp1 → lp1] → LP 4ᴾ    HP 8ᴾ  = [cell(HP)0 → hp1 → hp1] → HP 4ᴾ
//   BP 2ᴾ  = [cell(HP+BP)0] → LP 1ᴾ             BP 6ᴾ  = [cell(HP)0 → hp1] → LP 3ᴾ
//   BP 4ᴾ  = [cell(HP)0] → LP 2ᴾ                BP 8ᴾ  = [cell(HP)0 → hp1 → hp1] → LP 4ᴾ
//
// so the arm builds that ONE chain and steers it at kr — the cells' tap levels
// are SVF.ar's own kr level arguments, the one-poles' coefficients flip
// between the LP and HP forms, and two Select.ar pick how much of each end is
// in the path — instead of sixteen sub-graphs into a Select.ar: the same
// sixteen responses for 3 SVF + 4 FOS per channel (84 UGens for the stereo
// arm, about 40 of them kr coefficient arithmetic — measured) against
// ≈ 30 per channel PER sub-graph, sixteen times over. A fltMode
// change steps the chain's coefficients and inputs at a block boundary — a
// transient the filter itself smooths, and fltMode is a configuration list,
// not a sweep. Stages at one cutoff commute, so the pre-block sits FIRST as in
// the table: the resonant cell (the only place a nonlinearity lives) sees a
// signal the non-resonant block has already band-limited.
//
// Resonance (§1.2): `r = 0.9·res` into SVF.ar — Q ≤ 19; the UGen is LOSSLESS
// at 1.0 and exposes no loop an AGC could reach (§3.0 rule 4), so the arm
// clips the gain below the threshold and v1 has no self-oscillation — by
// contract. DC gain stays 1 at any r: NOT gain-compensated, that is THE
// difference from the ladders. Nonlinearity (rule 3): the drive knee before
// the model and the Resonance Limit on the resonant COMPONENT of the cell —
// `cell0` is the same tap at res 0, `rsn = cellR − cell0`, and only that
// clips (a literal reading of «the point where clipping begins within the
// filter's resonance»): SYM `lim·tanh(rsn/lim)`, ASYM the same curve pushed 0.3 up
// its knee so one half-wave compresses first (even harmonics), then LeakDC —
// the bias a real K35 loop would carry INTO the loop and detune by; a
// SynthDef cannot put it there, so it is removed rather than left to shift
// the one-poles' operating point (LeakDC at 0.999, corner 7.6 Hz: 0.995 would
// thin a resonance parked at a 20 Hz cutoff). lim = resLimit.linexp(0, 1, 0.05,
// 1) — the ld arm's map, because sk and ld are the two models that draw the
// same `limit · linear` pair and one knob must feel the same on both.
// Coefficients at kr (rule 5): the one-poles read A2K.kr(cutA) where the bus is
// audio-rate, the block's first sample; the cells take the bus as it comes.
// Both read it ONCE per block (rule 6, measured: SVF.ar on an
// ar cutoff wire and on A2K.kr of the same wire render identical files), so
// polysynthU's ar bus and polymerU's kr bus are one cutoff to every stage here.
~f2FltArmSk = { |pre, cutA, res, fltMode, fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain|
	var sr     = SampleRate.ir;
	var m      = fltMode.round(1).clip(0, 15);
	// the three groups of §3.12's order: 0…5 LP · 6…11 HP · 12…15 BP. Every
	// flag is a Select.kr table, never a comparison: a unit that hands the arm
	// a plain number (as the slot's shaper / filtFm paths do) would turn `m <
	// 5.5` into a Boolean and the graph would not build
	var isLP   = Select.kr(m, #[1, 1, 1, 1, 1, 1,  0, 0, 0, 0, 0, 0,  0, 0, 0, 0]);
	var isHP   = Select.kr(m, #[0, 0, 0, 0, 0, 0,  1, 1, 1, 1, 1, 1,  0, 0, 0, 0]);
	// what feeds the resonant cell: 0 dry (1…4ᴾ) · 1 the pre-cell alone
	// (BP 2ᴾ / 4ᴾ) · 2 pre-cell + one one-pole (6ᴾ, BP 6ᴾ) · 3 + two (8ᴾ, BP 8ᴾ)
	var src    = Select.kr(m, #[0, 0, 0, 0, 2, 3,  0, 0, 0, 0, 2, 3,  1, 1, 2, 3]);
	// one-poles AFTER the cell: 3ᴾ / 6ᴾ one, 4ᴾ / 8ᴾ two, BP 6ᴾ / 8ᴾ likewise
	var post   = Select.kr(m, #[0, 0, 1, 2, 1, 2,  0, 0, 1, 2, 1, 2,  0, 0, 1, 2]);
	// the pre-block is the HP form for the HP group AND the BP group (HP N/2
	// into LP N/2, the MS-20 way — why the BP list has no odd entries); the
	// post one-poles are HP only for the HP group
	var preHP  = 1 - isLP;
	// the 1ᴾ taps are the cell's mid node, LP2 + BP2 / HP2 + BP2 (= a one-pole
	// at res 0, resonant above it): LP 1ᴾ, HP 1ᴾ, and BP 2ᴾ's LP 1ᴾ cell
	var cellBP = Select.kr(m, #[1, 0, 0, 0, 0, 0,  1, 0, 0, 0, 0, 0,  1, 0, 0, 0]);
	// BP 2ᴾ's pre-cell is HP 1ᴾ (HP2 + BP2); every other pre-cell reads one tap
	var preBP  = Select.kr(m, #[0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0,  1, 0, 0, 0]);
	var r      = res.clip(0, 1) * 0.9;
	var lim    = resLimit.clip(0, 1).linexp(0, 1, 0.05, 1);
	var lin    = fltLin.round(1).clip(0, 1);
	// the one-pole coefficients: bilinear with prewarp g = tan(π fc/SR), the
	// same first-of-block cutoff sample the cells read. The 0.49·SR guard is
	// for a bus wider than today's units' clips: at 0.5·SR the tangent is
	// infinite and every coefficient NaN
	var fcK    = if (cutA.rate == \audio) { A2K.kr(cutA) } { cutA };
	var g      = (fcK.min(0.49 * sr) * pi / sr).tan;
	var q      = 1 / (1 + g);
	var b1     = (1 - g) * q;                             // shared by both forms
	var preA0  = q * (g + (preHP * (1 - g)));             // LP: g/(1+g) · HP: 1/(1+g)
	var preA1  = q * (g - (preHP * (1 + g)));             // LP: g/(1+g) · HP: −1/(1+g)
	var pstA0  = q * (g + (isHP * (1 - g)));
	var pstA1  = q * (g - (isHP * (1 + g)));
	// the drive's nonlinearity BEFORE the model (rule 3): the identity to
	// +6 dBFS and a tanh knee above it — the ld / mg arms' knee, one drive law
	// on every arm, and «linear until Drive engages» (§2.4) taken literally: a
	// bare tanh would colour a full-scale oscillator at drive 0
	var kneeAt = 2;
	var x      = pre.clip2(kneeAt) + ((pre.abs - kneeAt).max(0).tanh * pre.sign);
	// the non-resonant pre-block (Q 0.5) and its one-poles
	var pc     = topEnvironment[\f2Svf].(x, cutA, 0, isLP, preBP, preHP);
	var pc1    = FOS.ar(pc, preA0, preA1, b1);
	var pc2    = FOS.ar(pc1, preA0, preA1, b1);
	var cellIn = Select.ar(src, [x, pc, pc1, pc2]);
	// the resonant cell, and the same tap at res 0 for the resonant component
	var cellR  = topEnvironment[\f2Svf].(cellIn, cutA, r, 1 - isHP, cellBP, isHP);
	var cell0  = topEnvironment[\f2Svf].(cellIn, cutA, 0, 1 - isHP, cellBP, isHP);
	var rsn    = cellR - cell0;
	var sym    = (rsn / lim).tanh * lim;
	var asym   = LeakDC.ar((((rsn / lim) + 0.3).tanh - 0.3.tanh) * lim, 0.999);
	var cell   = cell0 + Select.ar(lin, [sym, asym]);
	var c1     = FOS.ar(cell, pstA0, pstA1, b1);
	var c2     = FOS.ar(c1, pstA0, pstA1, b1);
	Select.ar(post, [cell, c1, c2])
};

// svf — SVF.ar with the four taps as one-hot kr levels (FILTER.md §3.4, the
// contract's lines as written). res 0…1 → 0…0.999 linearly: 1.0 is LOSSLESS
// and unbounded (an impulse rings forever, a sine at fc grows without bound —
// measured), and the UGen clips its res at 1 so nothing
// past it exists; §6 Q8's recommendation taken — v1 caps at 0.999, the top of
// the knob rings for seconds without sustaining, and the «extended resonance
// range» past the threshold is the compiled F2SVF's (§3.11). The Resonance
// Limit is an OUTPUT soft limit at 2·resLimit: it bounds the level, not the
// tone (the loop cannot see it), and the card says so. Mode switching at kr is
// click-free — all four taps share two state variables — and the peak tap is
// always 0 (not a Bitwig mode). The cutoff is read once per block (measured:
// an ar cutoff wire and A2K.kr of the same wire render identical
// files — §3.4's aside that the UGen honours a sub-block cutoff is refuted,
// §3.0 rule 6 stands), so polysynthU's ar bus and polymerU's kr bus are the
// same thing to it. NOTCH's null at the exact fc is the UGen's tuning
// residual times Q (−69 dB at 562 Hz, −33 dB at 4.5 kHz, measured); at res 1
// the onset ring masks the null for seconds (τ 1.13 s) before it reads. The
// drive knee is the sk / ld / mg arms' (see sk). 30 UGens for the stereo arm.
~f2FltArmSvf = { |pre, cutA, res, fltMode, fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain|
	var rr  = res.clip(0, 1) * 0.999;
	var m   = fltMode.round(1).clip(0, 3);
	// one-hot → the four level args, §3.12's order LP BP HP NOTCH (tables, not
	// comparisons, so a plain-number fltMode builds too — see sk)
	var lv  = [Select.kr(m, #[1, 0, 0, 0]), Select.kr(m, #[0, 1, 0, 0]), Select.kr(m, #[0, 0, 1, 0]), Select.kr(m, #[0, 0, 0, 1])];
	var kneeAt = 2;
	var x   = pre.clip2(kneeAt) + ((pre.abs - kneeAt).max(0).tanh * pre.sign);
	var y   = topEnvironment[\f2Svf].(x, cutA, rr, lv[0], lv[1], lv[2], lv[3], 0);
	var lim = resLimit.clip(0.05, 1) * 2;
	(y / lim).tanh * lim
};

// comb — Pluck as a continuous feedback comb (FILTER.md §3.5). Pluck is a
// Karplus-Strong string: a cubic-interpolated delay, feedback
// 0.001^(delay/|decay|) signed by the decay, a OnePole INSIDE the per-sample
// loop (DelayUGens.cpp: buf[n] = in + g·onepole, out = onepole), and an
// input gate that opens for delay·SR samples on each trigger — a trigger
// every two samples (Impulse.ar at SR/2 outputs 1,0,1,0 …) keeps the gate
// open forever, and the UGen is a comb with damping in the loop and no
// LocalIn (rule 1: the LocalIn build is dead above ~SR/64, measured in the
// contract). `res` is a DECAY TIME here (§1.2, §6 Q7 taken: t = 8·res³ s,
// RT60 at −60 dB), so g < 1 always and there is nothing for `resLimit` to
// limit — unread, as are fltLin, fltMode2, fltFbGain, fltColor, fltVowel.
// `fltFbCut` is the Dampening Frequency RELATIVE to the cutoff (§1.2, §6 Q3
// taken: ±4 oct, 0.5 = at the cutoff), mapped to the OnePole's coefficient
// through the exact −3 dB relation of SC's y = (1−c)x + c·y₁. Gain policy §6
// Q16 taken: faithful, no compensation — the peaks reach 1/(1 − g·|P|) and
// the unit's Sanitize downstream is the only guard (+48 dB at 500 Hz / 8 s,
// measured).
~f2FltArmComb = { |pre, cutA, res, fltMode, fltLin = 0, resLimit = 1, fltMode2 = 0, fltFbGain = 0,
		fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6|
	var sr    = SampleRate.ir;
	// the cutoff once per block (rule 6): Pluck reads its delaytime by IN0 and
	// ramps it across the block; converting first keeps the reciprocal and the
	// damping maths at kr instead of 64× at ar for the same read
	var fcK   = if (cutA.rate == \audio) { A2K.kr(cutA) } { cutA };
	// the drive's nonlinearity before the loop (rule 3): the identity to
	// +6 dBFS and a tanh knee above it — the same knee as the ld / mg arms so
	// the Drive knob bites at one place on every model, and a drive-0 signal
	// (the polymer saw peaks at 1) reaches the loop untouched where the
	// contract's bare `pre.tanh` would recolour it
	var thr   = 2;
	var u     = pre.clip2(thr) + ((pre.abs - thr).max(0).tanh * pre.sign);
	// T = 1/cutoff — the comb's tuning (§2.5: «treat cutoff as a tuning control»)
	var dT    = fcK.reciprocal;
	// Dampening: relative ±4 oct, 0.5 = at the cutoff; the OnePole coefficient
	// with its −3 dB point exactly at fD (|H|² = ½ ⇒ c² − 2c(2 − cos w) + 1 = 0,
	// the root below 1); the 0.999 ceiling keeps a sub-20 Hz request from
	// closing the loop entirely
	var fD    = (fcK * (2 ** ((fltFbCut.clip(0, 1) - 0.5) * 8))).clip(20, sr * 0.45);
	var wD    = 2pi * fD / sr;
	var q     = 2 - wD.cos;
	var coef  = (q - ((q * q) - 1).sqrt).clip(0, 0.999);
	// The OnePole's phase delay at the cutoff, subtracted from T (the
	// contract's own refinement, §3.5). Without it the loop's round trip is
	// T + τ and the first peak sits BELOW the knob: at the default damping
	// (fD = cutoff) τ is an eighth of a period — the comb sings 12.5 % (two
	// semitones) flat of the cutoff it displays and of the note keytrack
	// aims it at. The upper peaks keep the small stretch τ(f) − τ(cutoff)
	// leaves them (measured: the residual, not a bug).
	var wC    = 2pi * fcK / sr;
	var tau   = ((coef * wC.sin).atan2(1 - (coef * wC.cos)) / wC) / sr;
	// ≥ 4 samples (the cubic reader's floor with margin) ⇒ tops out near SR/4
	var dTc   = (dT - tau).clip(SampleDur.ir * 4, 0.06);
	// Feedback as a decay time 0…8 s, cubic (§6 Q7): Pluck forms
	// g = 0.001^(delaytime/decay) from ITS delay, so the decay is scaled by
	// dTc/T to keep g = 0.001^(T/t) per round trip — RT60 = t exactly for the
	// undamped loop; res 0 ⇒ decay 0 ⇒ g = 0, a plain delay (bypass with
	// latency, as on Bitwig)
	var tFb   = 8 * res.clip(0, 1).cubed * dTc * fcK;
	// polarity on fltMode: 0 = +FB → +1, 1 = −FB → −1; the SAME delay for
	// both (4.3+), so −FB's lowest peak lands near cutoff/2
	var sign  = 1 - (fltMode.round(1).clip(0, 1) * 2);
	var y     = Pluck.ar(u, Impulse.ar(sr * 0.5), 0.06, dTc, tFb * sign, coef);
	// +FB has a DC peak (k = 0) of gain 1/(1 − g): block it after the loop.
	// 0.9993 (≈ 5 Hz at 48 kHz) and not LeakDC's default 0.995: that one is a
	// 38 Hz high-pass, which takes 7 dB off a 19.4 Hz +FB fundamental
	LeakDC.ar(y, 0.9993)
};

// xp — the pole-mixing ladder as two SOS sections (FILTER.md §3.6). One
// linear 4-pole ladder with global feedback k from the 4th pole and a 5-tap
// mixer: tap y_n(s) = X(s)·(1+s)^(4−n)/D(s), D(s) = (1+s)⁴ + k, so every one of
// the fifteen configurations is the EXACT 4th-order LTI filter N(s)/D(s).
// D factorises into the resonant pair (s² + (2−c)s + 1−c+r²) and the damped
// pair (s² + (2+c)s + 1+c+r²), r = k^¼, c = √2·r; each numerator into two
// real quadratics — two SOS in series, coefficients at kr (rule 5), the
// per-sample loop solved in closed form (rules 1 / 2). The configuration is
// a live kr Select of six numerator constants, so a switch is a coefficient
// step on a state the numerator does not touch (SOS is direct form II — its
// recursion is the all-pole state, the numerator an FIR on it) — no rebuild,
// no state reset, modulatable. Resonance law §6 Q9 taken: k = 4·res, the
// knob's 1 = the k = 4 threshold; the 122 % mapping (4.88·res) is NOT built —
// it waits for an ear test of Bitwig's 100 %. What IS built is the v1.1 AGC
// the contract makes that region's prerequisite: at the top of the knob the
// loop is let a hair past 4 and regulated one block late (rule 4) on the LP4
// pair — the resonant state itself, not the configuration output, because
// Notch is silent at fc while the loop oscillates — so res 1 settles to a
// clean sine at fc at the Resonance Limit's level on every configuration.
// DC gain 1/(1+k) is the ladder's bass loss and is not compensated. fltLin
// (undocumented for XP), fltMode2, the feedback pair, fltColor, fltVowel
// unread.
~f2FltArmXp = { |pre, cutA, res, fltMode, fltLin = 0, resLimit = 1, fltMode2 = 0, fltFbGain = 0,
		fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6|
	var sr    = SampleRate.ir;
	// coefficients at kr, read once per block (rules 5 / 6): the block's first
	// sample of an ar bus, which SOS then ramps across the block
	var fcK   = if (cutA.rate == \audio) { A2K.kr(cutA) } { cutA };
	// bilinear prewarp, s normalised to the cutoff
	var g     = (fcK * pi / sr).tan;
	var g2    = g * g;
	var rs    = res.clip(0, 1);
	// Resonance Limit as a LEVEL: the amplitude the loop settles at (§1.2 «L»);
	// the same linexp 0.05…1 map as the ld arm so one knob means one level on
	// both ladders
	var lim   = resLimit.clip(0, 1).linexp(0, 1, 0.05, 1);
	// The overdrive past k = 4 that lets the oscillation grow into the AGC
	// knee, fading in over res 0.9…1 so below 0.9 the loop gain is 4·res
	// EXACTLY (LP4 = MoogFF's linear system, measured: max|xp − MoogFF| ≤ 1e-4). Its size falls
	// as 1/fc above 100 Hz: the loop's growth per second is (k − 4)·ωc/16, so
	// a flat overdrive would be sluggish at 100 Hz and — because the AGC
	// reads one block late — overshoot L by (k − 4)·ωc·T/16 at 12 kHz
	// (the contract's «scaling with ωc, so keep the overshoot small at high
	// cutoffs»); scaled, the growth is ~17 dB/s and the overshoot +0.02 dB
	// at every cutoff above 100 Hz
	var over  = 0.0125 * (100 / fcK).min(1);
	var k     = rs * 4 * (1 + (over * ((rs - 0.9) * 10).clip(0, 1)));
	// The AGC's loop gain per block: a log-gain step lg moves the loop's
	// log-amplitude by beta = ¼·ωc·T per block, so the knee's exponent is
	// p = 1/beta above ~480 Hz (deadbeat: one block's correction equals one
	// block's overshoot — a per-block gain above one pumps) and 1 below it
	var beta  = (fcK * 2pi * ControlDur.ir * 0.25).max(1e-6);
	var p     = beta.reciprocal.min(1);
	// the AGC's one-block memory: the previous block's log-gain (≤ 0) in a
	// per-voice LocalBuf frame, read before it is written so the write lands
	// one block later. NOT a LocalIn.kr: a def has ONE kr LocalIn (a second is
	// silently zeroed) and samplerU's analysed-root variant owns it; the BufWr
	// is ordered after the BufRd by the graph's own dependencies. Cleared at
	// start (LocalBuf memory is not zeroed), so the first block's gain is 1.
	// The reads and writes address `mem`, NEVER ClearBuf's output: ClearBuf
	// outputs 0 (ClearBuf_Ctor: OUT0(0) = 0.f), so a BufRd aimed at it reads
	// server buffer 0 and the memory silently never exists — the loop then
	// grows through L unregulated (measured: +68 dB re L before this line)
	var mem   = LocalBuf(1, 1);
	var memC  = ClearBuf(mem);
	var lg    = BufRd.kr(1, mem, 0, 0, 1);
	var kEff  = (k * lg.exp).max(0);
	var r     = kEff ** 0.25;
	var c     = r * 1.4142135623730951;
	var r2    = r * r;
	// [a2, a1, a0] in s: the resonant pair A and the damped pair B
	var denA  = [1, 2 - c, 1 - c + r2];
	var denB  = [1, 2 + c, 1 + c + r2];
	// numerator factor pairs, section A · section B, each [b2, b1, b0] in s —
	// FILTER.md §3.6's table in §3.12's index order:
	//   s → [0,1,0]  (1+s) → [0,1,1]  (1−s) → [0,−1,1]  s² → [1,0,0]
	//   (1+s)² → [1,2,1]  s(1+s) → [1,1,0]  s²+1 → [1,0,1]  1−s² → [−1,0,1]  1 → [0,0,1]
	var numTab = #[
		[[1, 2, 1], [0, 1, 1]],    //  0 LP 1ᴾ    y1                    N = (1+s)³
		[[0, 1, 1], [0, 1, 1]],    //  1 LP 2ᴾ    y2                    N = (1+s)²
		[[0, 1, 1], [0, 0, 1]],    //  2 LP 3ᴾ    y3                    N = (1+s)
		[[0, 0, 1], [0, 0, 1]],    //  3 LP 4ᴾ    y4                    N = 1        (= MoogFF)
		[[1, 1, 0], [1, 2, 1]],    //  4 HP 1ᴾ    x − y1                N = s(1+s)³
		[[1, 2, 1], [1, 0, 0]],    //  5 HP 2ᴾ    x − 2y1 + y2          N = s²(1+s)²
		[[1, 1, 0], [1, 0, 0]],    //  6 HP 3ᴾ    x − 3y1 + 3y2 − y3    N = s³(1+s)
		[[1, 0, 0], [1, 0, 0]],    //  7 HP 4ᴾ    x − 4y1 + 6y2 − 4y3 + y4  N = s⁴
		[[1, 1, 0], [0, 1, 1]],    //  8 BP 2ᴾ    y1 − y2               N = s(1+s)²
		[[0, 1, 0], [0, 1, 0]],    //  9 BP 4ᴾ    y2 − 2y3 + y4         N = s²
		[[1, 2, 1], [-1, 0, 1]],   // 10 Peak     2y1 − x (LP2 − HP2)   N = (1+s)³(1−s)   allpass at k = 0 (§6 Q9, ?)
		[[1, 2, 1], [1, 0, 1]],    // 11 Notch    x − 2y1 + 2y2         N = (1+s)²(s²+1)  zeros on ±j·fc
		[[1, 0, 0], [0, 1, 1]],    // 12 HP2+LP1  y1 − 2y2 + y3         N = s²(1+s)
		[[1, 1, 0], [0, 0, 1]],    // 13 HP1+LP2  y2 − y3               N = s(1+s)
		[[0, 1, 0], [0, 0, 1]]     // 14 HP1+LP3  y3 − y4               N = s
	];
	// rule 2's bilinear: quadratic P(s) → [p2 + p1 g + p0 g², 2 p0 g² − 2 p2,
	// p2 − p1 g + p0 g²], normalised by the denominator's z⁰ term; SOS ADDS
	// its recursive terms, so the denominator's z⁻¹ / z⁻² are negated
	var bil   = { |num, den|
		var b2 = num[0], b1 = num[1], b0 = num[2];
		var a2 = den[0], a1 = den[1], a0 = den[2];
		var n0 = b2 + (b1 * g) + (b0 * g2), n1 = (b0 * g2 * 2) - (2 * b2), n2 = b2 - (b1 * g) + (b0 * g2);
		var d0 = a2 + (a1 * g) + (a0 * g2), d1 = (a0 * g2 * 2) - (2 * a2), d2 = a2 - (a1 * g) + (a0 * g2);
		var id = d0.reciprocal;
		[n0 * id, n1 * id, n2 * id, d1.neg * id, d2.neg * id]
	};
	// a value past the list is clamped, never wrapped (§3.12)
	var ci    = fltMode.round(1).clip(0, 14);
	var numA  = 3.collect { |i| Select.kr(ci, numTab.collect { |e| e[0][i] }) };
	var numB  = 3.collect { |i| Select.kr(ci, numTab.collect { |e| e[1][i] }) };
	var cA    = bil.(numA, denA);
	var cB    = bil.(numB, denB);
	var lA    = bil.([0, 0, 1], denA);
	var lB    = bil.([0, 0, 1], denB);
	// the drive's nonlinearity BEFORE the ladder (rule 3): the identity to
	// +6 dBFS and a tanh knee above it, the ld / mg arms' knee, so drive 0 is
	// the linear ladder to the sample and +24 dB is fully saturated
	var thr   = 2;
	var u     = pre.clip2(thr) + ((pre.abs - thr).max(0).tanh * pre.sign);
	var y     = SOS.ar(SOS.ar(u, cA[0], cA[1], cA[2], cA[3], cA[4]), cB[0], cB[1], cB[2], cB[3], cB[4]);
	// the LP4 pair the AGC reads — the resonant state under the same kEff,
	// whatever the configuration mixes on top of it
	var lp4   = SOS.ar(SOS.ar(u, lA[0], lA[1], lA[2], lA[3], lA[4]), lB[0], lB[1], lB[2], lB[3], lB[4]);
	// the follower's release stretches with the period below ~1.15 kHz so its
	// block-end reading does not sag between the peaks of a slow sine and
	// flutter the loop gain; both channels matched by taking the louder
	var relT  = (11.5 / fcK).clip(0.01, 0.15);
	var lvl   = lp4.asArray.collect { |ch| Amplitude.kr(ch, 0.002, relT) }.reduce(\max);
	var lgNew = ((lim / lvl.max(1e-9)).min(1).log * p).max(-6);
	BufWr.kr([lgNew], mem, 0, 0);
	y
};

// vowels — Klatt sections, the datasets above, a log-domain morph (FILTER.md
// §3.7). The one model with no cross-section feedback: every «internal filter»
// is a 2-pole resonator recursing inside one UGen and the three topologies
// only chain or sum them, so no LocalIn, no block boundary in any audio path,
// and every coefficient is a kr value the cores read once per block and ramp
// (§3.0 rules 1, 5, 6 — measured). Sections: the Klatt
// resonator is `TwoPole.ar(x, F', r) × (1 − b1 − b2)`, r = exp(−π·BW'/SR),
// b1 = 2r·cos(2πF'/SR), b2 = −r² — unity DC gain, −12 dB/oct above F'; the
// parallel band-passes `BPF.ar(x, F', rq) × A.dbamp` (unit peak gain at any
// rq, so the dataset's dB land where written — not Resonz, whose peak moves
// with bwr) with Klatt's alternating polarity; the high-pass `RHPF.ar` at the
// top formant, −12 dB. All three topologies run and a Select.ar picks — the
// contract's line; fltMode is a configuration list, not an opt. Q Limit
// (§1.2, §3.7): the section OUTPUTS saturate, `c = 1 + 8·(1 − resLimit)`,
// `(y·c).tanh / c` — a ceiling of 1/c, from 1 at the knob's top to 1/9 at the
// bottom; there is no feedback to clip and the model cannot self-oscillate
// (r < 1 always) — at res 1 it rings ≈ 1/(π·BW') s. The drive knee is the
// ld / mg / sk / svf arms' (identity to +6 dBFS, tanh above), not the
// contract's bare `pre.tanh`, so one Drive knob bites at one place on every
// model: tanh(1) = 0.76 would have recoloured a full-scale oscillator at
// drive 0. Keytrack is read (§2.7 — the bus carries it); Bitwig advises 0 and
// the card says so. Cost (measured): ≈ 190 UGens for the stereo arm —
// ≈ 45 ar (nine filters, the knee, the sums and the ceiling per channel) and
// ≈ 145 kr (the morph: 24 Select.kr over the baked tables and their maths);
// ≈ 12 KB of SynthDef, most of it the 420 constants and the Selects' inputs.
~f2FltArmVowels = { |pre, cutA, res, fltMode, fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain|
	var sr    = SampleRate.ir;
	var m     = fltMode.round(1).clip(0, 2);
	var m2    = fltMode2.round(1).clip(0, 6);
	// the bus at kr: the cores read their cutoff once per block anyway (rule
	// 6), and the (1 − b1 − b2) gain must be the same block value as the poles
	var fcK   = if (cutA.rate == \audio) { A2K.kr(cutA) } { cutA };
	var ratio = fcK / 2000;
	var sect  = topEnvironment[\f2VowelMorph].({ |i, arr| Select.kr(i, arr) }, topEnvironment[\f2VowelFlat],
		m2, fltVowel, res, ratio, sr);
	var thr   = 2;
	var uc    = pre.clip2(thr);
	var x     = uc + (pre - uc).tanh;
	var klatt = { |in, s|
		var r  = exp(pi.neg * s[\bw] / sr);
		var b1 = 2 * r * cos(2pi * s[\f] / sr);
		var b2 = r.squared.neg;
		TwoPole.ar(in, s[\f], r) * (1 - b1 - b2)
	};
	// 0 CASC: F1 first, the amplitudes fall out of the chain
	var casc  = sect.inject(x, { |acc, s| klatt.(acc, s) });
	// 1 LP/BP: F1 as the body, F2…F4 as band-passes with the dataset's dB,
	// alternating polarity — Klatt's parallel rule AS KLATT STATES IT: F1 +,
	// F2 −, F3 +, F4 −. Adjacent resonators sit 180° apart between their
	// peaks, so like signs cancel there; §3.7's line has the signs the other
	// way round (F2 +), and measured that way F2 — the vowel's main cue —
	// is eaten by the F1 low-pass's inverted tail: −9 dB and no local maximum
	// at F2 on i / ɑ / u of every profile (measured before this flip). With F2 − the F2 peak stands (measured).
	var par   = klatt.(x, sect[0]) + sect[1..].collect({ |s, i|
		BPF.ar(x, s[\f], s[\rq]) * s[\a].dbamp * (if (i.even) { -1 } { 1 })
	}).sum;
	// 2 LP/BP/HP: what lies above the bank passes, −12 dB (h ?)
	var parhp = par + (RHPF.ar(x, sect[3][\f], sect[3][\rq]) * (-12).dbamp);
	var y     = Select.ar(m, [casc, par, parhp]);
	var c     = 1 + (8 * (1 - resLimit.clip(0, 1)));
	(y * c).tanh / c
};

// fizz — the loop-free approximation, v1 (FILTER.md §3.8, the contract's lines
// as written). The target is an outer resonant LP whose feedback path IS a
// nested filter (two all-passes, a peak, a saturator); that loop cannot close
// in a SynthDef (rule 1), so v1 lays the nest out open-loop in front of the
// outer stage: dry + two all-passes whose corners Color splits (= notches),
// four BPeakEQ nodes on a ladder above fbHz (Alt: below it, an odd-ish
// inharmonic ladder) that Feedback Gain FEEDS (+k, peaks) or CHOKES (−k,
// notches), the feedback-path saturator with resLimit as its ceiling, then
// SVF.ar as the outer LP whose resonance is |Feedback Gain| — `res` is not
// read (§1.2: dead, dimmed on the card). fltFbCut is ABSOLUTE Hz through the
// slot's own exponential (§1.2, §6 Q3), so the nodes do not follow the key —
// the outer cutoff does. Why SVF for the outer stage: measured (§3.8) to ring
// near self-oscillation where RLPF / MoogFF die in 100 ms. The drive knee is
// the shared one (see vowels). What v1 gets right and wrong is §3.8's list:
// the nodes never self-oscillate (biquad peaks bounded at +24 dB) and their
// shape is a biquad's, not a loop's; F2Fizz (§3.11) is the faithful build and
// the card's tooltip says «the loop-free approximation». Cost (measured):
// ≈ 90 UGens for the stereo arm, 7 biquads + the knee per channel and
// the kr node maths; ≈ 4 KB of SynthDef.
~f2FltArmFizz = { |pre, cutA, res, fltMode, fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain|
	var sr   = SampleRate.ir, top = 0.45 * sr;
	// max/min, not clip: with a plain-number fltFbCut this is a Float and Float.clip(20, aUGen) fails
	var fbHz = (19.4 * ((33500 / 19.4) ** fltFbCut.clip(0, 1))).max(20).min(top);
	var col  = Lag.kr(fltColor.clip(-1, 1), 0.005);
	var k    = Lag.kr(fltFbGain.clip(-1, 1), 0.005);
	var alt  = fltMode.round(1).clip(0, 1);
	var thr  = 2;
	var uc   = pre.clip2(thr);
	var u    = uc + (pre - uc).tanh;
	// phase-shifting: two all-passes whose corners Color splits; Alt mirrors
	var sp   = 2 ** (1.5 * col * Select.kr(alt, #[1, -1]));
	var ph   = BAllPass.ar(BAllPass.ar(u, (fbHz / sp).clip(20, top), 0.7), (fbHz * sp).clip(20, top), 0.7);
	var v    = 0.5 * (u + ph);                       // dry + all-pass = notches; the nodes between them are then peaked
	var rat  = Select.kr(alt, [#[1, 2, 3, 4], #[1, 1.5, 2.5, 3.5]]);   // Alt 1: an odd-ish, inharmonic ladder
	var ex   = rat ** (1 + (0.75 * col));
	var fN   = Select.kr(alt, [fbHz * ex, fbHz / ex]).clip(20, top);
	var gN   = k * 24 * #[1, 0.8, 0.65, 0.5];        // dB: +k feeds (peaks), −k chokes (notches)
	var rqN  = 0.35 - (0.25 * k.abs);                // sharper as it feeds
	var g    = 1 / resLimit.clip(0.05, 1);
	var nest = v, sat, y;
	4.do { |i| nest = BPeakEQ.ar(nest, fN[i], rqN, gN[i]) };
	sat = (nest * g).tanh / g;                       // the feedback-path saturation; resLimit = its ceiling
	y   = topEnvironment[\f2Svf].(sat, cutA, (k.abs * 0.9).clip(0, 0.98), 1, 0, 0, 0, 0);   // the outer resonant LP: its resonance IS |Feedback Gain|
	LeakDC.ar(y, 0.9993)
};

// rasp — the open-loop equivalent of Bitwig's nested loop (FILTER.md §3.9,
// v1). Bitwig closes a phase-rotating element N inside the outer filter's
// feedback and saturates the loop; rule 1 forbids that loop in a SynthDef, so
// this arm renders its AUDIBLE result feed-forward: an outer LP / BP (both
// built — fltMode is live) plus three parallel band-pass NODES at
// mode-dependent ratios of the cutoff, lifted and sharpened by Resonance and
// pushed through ONE tanh knee together with the outer. The nodes are fed
// from `pre`, not from `outer`: nodes after the LP sat buried under its
// 12 dB/oct roll-off (§3.9 probe3), contradicting «resonances above the
// cutoff» — a loop's resonances are not attenuated by the output filter's
// slope, and parallel band-passes on the pre-filter signal reproduce that.
// The knee at the output is the Feedback Limit, shared by the input and the
// nodes: that sharing IS the documented «Drive and Resonance are connected»
// — pull Drive down and the nodes get the knee's headroom. Its floor is the
// `[3P]` 35 %, clipped in the ARM and not in the schema (§1 rule 6): a schema
// change reaches every save, an arm clip reaches one model. Resonance does
// three things at once (`?`): node level 6·res² (0 at res 0 — the whisper —
// so res 0 is the plain outer through the knee), node Q (rq 1 → 0.1) and a
// mild coupling into the outer (rq 1 → 0.5). Brightness `b` moves the nodes:
// SHIFT slides ONE node ±2 oct past the cutoff («The Finger» — one partial
// at a time, inharmonic: nodes 2–3 at ×1.618 / ×2.618 of it, faint);
// GRAVITY moves the whole set as a body, b = −1 piling every node ONTO the
// cutoff (the scream), b = +1 spreading them to 2·3·4 × the cutoff; DOUBLE =
// Shift's node 1 with Gravity's nodes 2–3 («a tuned mixture» — Bitwig's
// default). What v1 cannot do is self-oscillate at a node (§6 Q11: the card
// prints the divergence); the knee bounds everything at ≤ L, so res 1 with
// drive +24 dB is finite by construction. Knobs are lagged 5 ms (rule 5): a
// stepped `bright` moves three centre frequencies at once and zips.
~f2FltArmRasp = { |pre, cutA, res, fltMode, fltLin = 0, resLimit = 1, fltMode2 = 0, fltFbGain = 0,
		fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6|
	var nyq   = 0.45 * SampleRate.ir;
	var r     = Lag.kr(res.clip(0, 1), 0.005);
	var b     = Lag.kr(fltColor.clip(-1, 1), 0.005);
	var lim   = resLimit.clip(0.35, 1);
	var m     = fltMode2.round(1).clip(0, 2);
	var typ   = fltMode.round(1).clip(0, 1);
	var rqO   = 1 - (0.5 * r);
	// LP | BP, both built: the same cutoff bus, the centre at fltMode 1
	var outer = Select.ar(typ, [RLPF.ar(pre, cutA, rqO), BPF.ar(pre, cutA, rqO)]);
	var shift = 2 ** (2 * b);
	var grav  = { |n| 1 + (n * (1 + b) * 0.5) };
	var rat   = [Select.kr(m, [shift, shift, grav.(1)]),
	             Select.kr(m, [shift * 1.618, grav.(2), grav.(2)]),
	             Select.kr(m, [shift * 2.618, grav.(3), grav.(3)])];
	var wgt   = [1, Select.kr(m, [0.25, 0.8, 0.8]), Select.kr(m, [0.1, 0.6, 0.6])];
	var rqN   = 1 - (0.9 * r);
	var g     = 6 * r * r;
	// the node centres are clipped to the audio band: at b = +1 GRAVITY puts
	// node 3 at 4 × the cutoff, past Nyquist for any cutoff above 5.4 kHz,
	// and BPF fed a centre above Nyquist is not a filter
	var nodes = (3.collect { |i| BPF.ar(pre, (cutA * rat[i]).clip(20, nyq), rqN) * wgt[i] }).sum * g;
	((outer + nodes) / lim).tanh * lim
};

// ripple — the nested loop of FILTER.md §3.10: `x = tanh(pre)`;
// `u = x + g·N(P)`; `y = H1(u)`, the outer 2-pole LP at cutA with Q0 = 0.707
// (no documented resonance of its own); P = y, or the outer's band-pass node
// under Tweak Feedback; `out = y + twFF·kff·N(P)`, kff = 0.5·sign(g), under
// Tweak Feedforward. `fltFbGain` (bipolar, ✓ [REL] −100…+100 %) IS the
// resonance — `res` is not read, and neither are fltLin / fltColor /
// fltVowel / bellGain; `fltFbCut` is an ABSOLUTE Hz control on the slot's
// own exponential (§1.2, §6 Q3) and is not key-tracked (undocumented, `?`).
// Nature swaps N: EARTH a 1-pole LP at fbF, WIND a 2-pole BP (Q 4), FIRE a
// 2-pole all-pass (Q 0.707, `?`) with a slow ±0.1 oct / 0.3 Hz drift as its
// «motion» — a deterministic LFO, not a noise, so an offline render of a
// saved preset is sample-identical run to run. Two routes, by nature:
//
// EARTH — R1, the exact linear core, no loop delay. H1 (2 poles) closed
// round a 1-pole N is a 3rd-order LTI system, D(s') = (s'² + q0 s' + 1)(s' + a)
// − g·a with s' = s/ω1, a = ω2/ω1 (both corners prewarped, so each lands
// exactly), q0 = 1/Q0; under Tweak Feedback the loop term is −g·a·q0·s'
// instead. Cardano at kr finds a real root, the quadratic that remains is
// bilineared into an all-pole SOS and the real factor with the whole
// numerator into a FOS — two UGens per channel, the modes exact, zero loop
// delay (rule 2). Numerics that the float32 kr path forced, each measured
// offline before it was written: (a) the depressed cubic's discriminant
// cancels when fbF and cut are far apart, so one guarded Newton polish on the
// monic cubic follows Cardano (root error 1.7e-3 → 2e-6); (b) `p0 = c1 + r·p1`
// cancels catastrophically at fbF/cut = 1000 and came out NEGATIVE — an
// unstable SOS — so the quadratic factor is `p0 = −c0/r` (no cancellation) and
// `p1 = c2 + r` for a small root, `(p0 − c1)/r` for a large one; (c) the real
// root is pinned below zero and p0 / p1 above it, so a garbage root can only
// mistune, never blow up. Which real root when all three are real: the one
// that stays simple at the region's boundary (t2 when the depressed q > 0,
// t0 otherwise) — the partition of a cubic into (real) × (quadratic) has NO
// jump-free choice across such a region (any rule jumps once per crossing,
// tracking with memory included), so the transient was measured instead
// of hidden (a 0.3 → 0.6 ramp through the region: ×1.00 of the steady peaks). Stability is Routh–Hurwitz,
// not a numeric max: with P = y the loop is unstable at g ≥ 1 (the DC pole —
// D(0) = a(1 − g)) and never for g < 0 within the knob, so g is clipped to
// 0.98 there (the contract's 0.98·g_crit, g_crit = 1 exactly — its «evaluate
// at ω1» would have allowed g > 1); with P = the band-pass node the loop is
// stable for every g in −1…1 on paper (g_crit = 1 + 1/(a(q0 + a)) > 1) and is
// clipped to 0.98·g_crit all the same, for float32's sake. What positive
// feedback does on EARTH is therefore a bass boost 1/(1 − g) that over-damps
// the pair (three real poles at g ≳ 0.45 for fbF ≳ 2.5·cut), and negative
// feedback a mild resonance above the cutoff; the «central peak» is the
// Tweak-Feedback reading. The limiter sits OUTSIDE the loop (rule 3): the
// modes are exact, the in-loop distortion and the limit cycle are lost, and
// the card says so.
//
// WIND / FIRE — R3, the block-delayed loop. A 2-pole N makes the loop 4th
// order (Ferrari at kr: closed-form, numerically ugly — not built), so the
// loop is closed with ONE block of delay. Not through `LocalIn/LocalOut`:
// polysynthU's `fb` owns that pair (a def has one audio-rate pair — a second
// is silently zeroed), and the contract's «keep Ripple polymerU-only until
// then» is not an end state. The loop goes through a per-voice 64-frame
// LocalBuf instead: BufRd at a running Phasor reads what BufWr wrote 64
// samples ago because the graph orders the read before the write (the write
// depends on the read through the loop) — measured sample-identical to a
// LocalIn/LocalOut loop, and it coexists with polysynthU's pair with no
// crosstalk. Same acoustics as the contract's R3: the delay is SR/64 =
// 750 Hz in the loop (689 Hz at 44.1 kHz) — a comb whose teeth the resonance
// picks, and the loop phase at any audio frequency is off by ω·64/SR, so the
// modes are near fbF, not at it. Hence |g| ≤ 0.9: past 1 the loop would
// sing at a comb tooth — a pitch set by the block size, not by any knob —
// and the cap keeps R3 a resonant loop that follows fbF (peaks to 1/(1 − 0.9)
// = +20 dB) instead of an oscillator tuned to 750 Hz. The outer is SVF.ar
// (click-free under a sweep, rule 5) at res 0.00737, which is Q0 = 0.707 on
// its law damp = 2(1 − res^¼) — measured −3.02 dB at fc — so all three
// natures share one outer and a nature switch at g = 0 changes nothing
// (the contract's literal 0.15 would have peaked +2.4 dB); its band-pass tap
// peaks at Q0 (−3 dB) and is scaled by √2 so Tweak Feedback means the same
// unity-peak node it means on EARTH. The limiter is IN the loop here — the
// fed-back P is `lim·tanh(P/lim)` — and the tanh'd input plus |g| < 1 bound
// the output. In all routes F2's arm is de facto Bitwig's «Low Quality» tier
// or below (§6 Q11): the card prints that on the tooltip, no toggle is drawn.
~f2FltArmRipple = { |pre, cutA, res, fltMode, fltLin = 0, resLimit = 1, fltMode2 = 0, fltFbGain = 0,
		fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6|
	var sr    = SampleRate.ir;
	var nyq   = 0.45 * sr;
	// the closed form's coefficients at kr, read once per block (rules 5 / 6):
	// the first sample of an ar bus is what every core's IN0 read gives it
	var fcK   = if (cutA.rate == \audio) { A2K.kr(cutA) } { cutA };
	var gK    = Lag.kr(fltFbGain.clip(-1, 1), 0.005);
	// the slot's own exponential on the stored 0…1 → Hz, clipped to the band.
	// max/min and not clip: a unit may pass a plain NUMBER for a cell (§3.0),
	// Lag.kr hands a number straight back, and Float:clip has no primitive
	// for a UGen bound where the binary ops reverse-dispatch
	var fbF   = (19.4 * ((33500 / 19.4) ** Lag.kr(fltFbCut.clip(0, 1), 0.005))).max(20).min(nyq);
	var nat   = fltMode.round(1).clip(0, 2);
	var tw    = fltMode2.round(1).clip(0, 3);
	var twFB  = Select.kr(tw, [0, 1, 0, 1]);       // bit 0 — Tweak Feedback
	var twFF  = Select.kr(tw, [0, 0, 1, 1]);       // bit 1 — Tweak Feedforward
	var kff   = 0.5 * gK.sign * twFF;
	var lim   = resLimit.clip(0, 1).linlin(0, 1, 0.25, 2);
	var x     = pre.tanh;
	var q0    = 1.4142135623730951;
	// ── R1: EARTH — the cubic, its real root, the two sections ──
	var g1    = (fcK * pi / sr).tan;
	var g2    = (fbF * pi / sr).tan;
	var a     = g2 / g1;
	// Routh–Hurwitz per pick-off (see above): P = y is unstable at g ≥ 1 and
	// never for g < 0; P = the band-pass node at g ≥ 1 + 1/(a(q0 + a)) — above
	// the knob, but only by 1e-7 once fbF/cut ≈ 2800, and a float32 SOS cannot
	// hold a pole that close to the circle (measured: a 20 Hz ring that outlived
	// its segment by +39 dB), so that side takes 0.98·g_crit as well — inert
	// below fbF/cut ≈ 6, a Q-35 «central peak» at the knob's top beyond it
	var gCritB = 1 + (1 / (a * (q0 + a)));
	var gE    = Select.kr(twFB, [gK.min(0.98), gK.min(0.98 * gCritB)]);
	var c2    = q0 + a;
	var c1    = 1 + (q0 * a) - (twFB * gE * a * q0);
	var c0    = a * (1 - ((1 - twFB) * gE));
	var pd    = c1 - (c2 * c2 / 3);
	var qd    = (2 * c2 * c2 * c2 / 27) - (c2 * c1 / 3) + c0;
	var disc  = (qd * qd / 4) + (pd * pd * pd / 27);
	var sq    = disc.max(0).sqrt;
	var cbrt  = { |v| v.sign * (v.abs ** (1 / 3)) };
	var tOne  = cbrt.((qd.neg / 2) + sq) + cbrt.((qd.neg / 2) - sq);
	var pm    = pd.min(-1e-12);
	var mag   = 2 * (pm.neg / 3).sqrt;
	var th    = ((3 * qd / (2 * pm)) * (-3 / pm).sqrt).clip(-1, 1).acos;
	var tTri  = Select.kr(qd > 0, [mag * (th / 3).cos, mag * ((th / 3) - (4pi / 3)).cos]);
	var rRaw  = Select.kr(disc >= 0, [tTri, tOne]) - (c2 / 3);
	var fv    = ((((rRaw + c2) * rRaw) + c1) * rRaw) + c0;
	var fd    = (((3 * rRaw) + (2 * c2)) * rRaw) + c1;
	var stepL = (0.05 * rRaw.abs) + 1e-4;
	var r     = (rRaw - (fv / (fd + ((fd.abs < 1e-12) * 1e-12))).clip(stepL.neg, stepL)).min(-1e-9);
	var p0    = (c0.neg / r).max(1e-6);
	var p1    = Select.kr(r.abs < (c2 / 2), [(p0 - c1) / r, c2 + r]).max(1e-6);
	var n1    = 1 + (twFB * kff * a * q0);
	var n0    = a * (1 + ((1 - twFB) * kff));
	var d0f   = 1 - (r * g1);
	var fa0   = (n1 + (n0 * g1)) / d0f;
	var fa1   = ((n0 * g1) - n1) / d0f;
	var fb1   = (1 + (r * g1)) / d0f;
	var g1sq  = g1 * g1;
	var d0s   = 1 + (p1 * g1) + (p0 * g1sq);
	var sa0   = g1sq / d0s;
	var sb1   = (2 - (2 * p0 * g1sq)) / d0s;
	var sb2   = (1 - (p1 * g1) + (p0 * g1sq)).neg / d0s;
	var earth = FOS.ar(SOS.ar(x, sa0, 2 * sa0, sa0, sb1, sb2), fa0, fa1, fb1);
	var earthO = (earth / lim).tanh * lim;
	// ── R3: WIND / FIRE — one block round the loop through a per-voice frame ──
	var mem   = LocalBuf(64, 2).clear;
	var ph    = Phasor.ar(0, 1, 0, 64);
	var fb    = BufRd.ar(2, mem, ph, 1, 1);
	var fire  = nat.clip(1, 2) - 1;               // arithmetic, not `nat >= 2`: a Boolean for a scalar fltMode
	var fN    = (fbF * (2 ** (0.1 * SinOsc.kr(0.3) * fire))).max(20).min(nyq);
	var nWind = BPF.ar(fb, fN, 0.25);
	var gA    = (fN * pi / sr).tan;
	var gA2   = gA * gA;
	var dA    = 1 + (gA * q0) + gA2;
	var nFire = SOS.ar(fb, (1 - (gA * q0) + gA2) / dA, ((2 * gA2) - 2) / dA, 1, (2 - (2 * gA2)) / dA, (1 - (gA * q0) + gA2).neg / dA);
	var nfb   = Select.ar(fire, [nWind, nFire]);
	var gR    = gK.clip(-0.9, 0.9);
	var u     = x + (gR * nfb);
	var y     = topEnvironment[\f2Svf].(u, cutA, 0.00737, 1, 0, 0, 0, 0);
	var pTap  = topEnvironment[\f2Svf].(u, cutA, 0.00737, 1 - twFB, twFB * 1.4142135623730951, 0, 0, 0);
	var r3    = y + (kff * nfb);
	BufWr.ar((pTap / lim).tanh * lim, mem, ph, 1);
	Select.ar(nat, [earthO, r3, r3])
};

// The slot itself, on the cutoff bus the unit hands it. `cutK` is that bus
// BEFORE the filter FM and before the clip: the FM multiplies INSIDE the clip,
// as polysynthU always did, so the bounds bound the modulated cutoff too, and
// `lo` / `hi` are the unit's own — polymerU 19.4…0.45·SR (§2), polysynthU
// and samplerU 20…20000 kept on purpose: widening it to 0.45·SR would move a
// saturated FEG sweep's ceiling up 0.1 oct at 48 kHz and DOWN to 19.8 kHz at
// 44.1 kHz, and a saved sweep has to saturate exactly where it did. The shared
// knob range reaches past that clip; those ends are inert on those two units
// and the card says so. THE RATE OF THE FM PRODUCT IS PART OF EACH UNIT'S LAW (`fmKr`). Every
// filter here — RLPF and its siblings, MoogFF — reads its cutoff input ONCE
// per block (IN0, the first sample), so «audio-rate» filter FM has always
// been the block's first mono sample; what the wire's rate changes is the
// LAG. A kr × ar multiply (BinaryOpUGen mul_ka) ramps the kr operand from the
// PREVIOUS block's value, and K2A.ar ramps the same way, so a filter fed an ar
// cutoff wire sees the previous block's cutoff during a sweep. polysynthU
// forms the product at ar (fmKr false): that one-block lag is what its filters
// have always had, and a save keeps it bit for bit. polymerU forms it at kr
// (fmKr true, `A2K.kr(mono)` — the same first sample, no ramp): its ladder
// reads this block's cutoff, exactly what stage 1's kr bus gave it, and at
// filtFm 0 the multiply is a ×1 the bus does not notice.
// `pre` is the stereo signal INTO the model, after drive (the unit multiplies
// drive.dbamp in BEFORE the call — FILTER.md §3.0: the drive is a gain into the
// model's own nonlinearity, so where it sits is the unit's). Returns
// (filt: the bypass-selected model output — pre-shaper, what polysynthU's
// feedback loop reads; post: after the waveshaper).
// THE ARM CONTRACT (FILTER.md §3.0). Eleven arms, ONE `case` clause each, in
// ~f2FltModels order, and never a live Select over models: the model is
// structural, so a variant carries one arm and pays for no other. Every arm
// reads the same names and returns a stereo signal:
//   pre      stereo, the drive already multiplied in
//   cutA     the unit's cutoff bus in Hz after keytrack / FEG / filter FM,
//            clipped to (lo, hi) — the unit's own bounds; an ar wire on
//            polysynthU, kr on polymerU and samplerU, and every core here reads
//            it ONCE per block (measured per arm), so the two rates are one
//            cutoff to every model
//   res      0…1 — ONE key, a law per model (FILTER.md §1.2: feedback on the
//            ladders, a decay time on comb, a Q multiplier on vowels, dead on
//            fizz and ripple)
//   fltMode  the model's configuration list, 0-based in ~f2FltModeSel's order
//            (FILTER.md §3.12); clamp `round(1).clip(0, n − 1)` INSIDE the arm,
//            never wrap
//   fltLin resLimit fltMode2 fltFbGain fltFbCut fltColor fltVowel bellGain
//            the per-model cells — an arm reads the ones §2 gives its model and
//            ignores the rest; every unit declares all of them so a lock aimed
//            at any lands on every card (CARDS.md §5), and a range a
//            third-party number narrows is clipped in the ARM, not the schema
//            (§1 rule 6)
//   SampleRate.ir is the arm's to read where a loop is solved in closed form.
// A model listed in ~f2FltBuilt without a clause here is a BUILD ERROR — the
// `case` falls through to the throw at the end, ~f2UnitDef catches it, warns
// once and spawns the base def. Loud on purpose: a silent `poly` in its place
// would pass every listening test as «the filter sounds a bit plain».
//   poly — F2's own core: the RLPF / BPF / RHPF / BRF 2-pole cascade, 4-pole =
//          the same stage twice, rq = 1 − 0.95·res; fltMode 0…7 = LP2 LP4 BP2
//          BP4 HP2 HP4 NOTCH BELL, index-identical to polysynthU's old filtType
//          (its 7, OFF, is `filtOn` 0 now — a bypass is not a model) and to
//          samplerU's old filtType 0…7 (its 8, OFF, likewise). BELL is the
//          sampler's MidEQ — `res` the bandwidth, `bellGain` the gain — carried
//          on the synths too so the key means one thing everywhere (FILTER.md
//          §2.0, §5, §6 Q15);
//   ld … ripple — the ten Bitwig models, ~f2FltArmLd … ~f2FltArmRipple above:
//          one function per arm taking the twelve names of this contract, so
//          the clause is the call site and nothing else; what each arm takes
//          from FILTER.md §3 as written, where it deviates and why, and what it
//          measured are in its own header. `ld` at its 24 dB tap IS MoogFF
//          through res 0.9 — bit-identical, the sound every polymer save plays
//          — with the closed form and the AGC taking over only at the top of
//          the knob (its header; sc/nrt/envab.scd's `pm_ld` / `poly_ld` cases).
// A unit that declares no filter FM or no shaper passes PLAIN NUMBERS (0) for
// filtFm / shaper / shaperMode and those paths are built out, not multiplied
// by zero: the sampler's def is the one nearest the 16383-byte /d_recv line.
~f2FltSlot = { |model, pre, cutK, lo, hi, filtFm, res, fltMode, filtOn, shaper, shaperMode, fmKr = false,
		fltLin = 0, resLimit = 1, fltMode2 = 0, fltFbGain = 0, fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6|
	// cutoff FM by the mono pre-model signal — polysynthU's maths, at the rate
	// the unit asks for (see above); at filtFm 0 the factor is exactly 1
	var cutA  = if (filtFm.isNumber and: { filtFm == 0 }) { cutK.clip(lo, hi) } {
		var mono = (pre[0] + pre[1]) * 0.5;
		var fmIn = if (fmKr) { A2K.kr(mono) } { mono };
		(cutK * (1 + (filtFm.clip(0, 1) * 8 * fmIn))).clip(lo, hi)
	};
	// the eight per-model cells in the arm contract's order — one shape for
	// the ten call sites below
	var cells = [fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain];
	var out   = case
		{ model == \poly } {
			var rq  = 1 - (res.clip(0, 1) * 0.95);
			var lp2 = RLPF.ar(pre, cutA, rq);
			var lp4 = RLPF.ar(lp2, cutA, rq);
			var bp2 = BPF.ar(pre, cutA, rq);
			var bp4 = BPF.ar(bp2, cutA, rq);
			var hq2 = RHPF.ar(pre, cutA, rq);
			var hq4 = RHPF.ar(hq2, cutA, rq);
			var ntc = BRF.ar(pre, cutA, rq);
			var bel = MidEQ.ar(pre, cutA, rq, bellGain.clip(-24, 24));
			// Select order: LP2 LP4 BP2 BP4 HP2 HP4 NOTCH BELL
			Select.ar(fltMode.round(1).clip(0, 7), [lp2, lp4, bp2, bp4, hq2, hq4, ntc, bel])
		}
		{ model == \ld }     { topEnvironment[\f2FltArmLd].(pre, cutA, res, fltMode, *cells) }
		{ model == \mg }     { topEnvironment[\f2FltArmMg].(pre, cutA, res, fltMode, *cells) }
		{ model == \sk }     { topEnvironment[\f2FltArmSk].(pre, cutA, res, fltMode, *cells) }
		{ model == \svf }    { topEnvironment[\f2FltArmSvf].(pre, cutA, res, fltMode, *cells) }
		{ model == \comb }   { topEnvironment[\f2FltArmComb].(pre, cutA, res, fltMode, *cells) }
		{ model == \xp }     { topEnvironment[\f2FltArmXp].(pre, cutA, res, fltMode, *cells) }
		{ model == \vowels } { topEnvironment[\f2FltArmVowels].(pre, cutA, res, fltMode, *cells) }
		{ model == \fizz }   { topEnvironment[\f2FltArmFizz].(pre, cutA, res, fltMode, *cells) }
		{ model == \rasp }   { topEnvironment[\f2FltArmRasp].(pre, cutA, res, fltMode, *cells) }
		{ model == \ripple } { topEnvironment[\f2FltArmRipple].(pre, cutA, res, fltMode, *cells) }
		{ Error("~f2FltSlot: filt % has no arm — ~f2FltBuilt lists a model this case does not build".format(model)).throw };
	// bypass: 0 = the dry pre-model signal, and the shaper still follows it
	var filt  = Select.ar(filtOn.round(1).clip(0, 1), [pre, out]);
	// shaper — Select order: OFF SOFT HARD FOLD WRAP SINE RECT, cross-faded with
	// filt by `shaper`; built out where the unit declares none (plain numbers)
	var post  = if (shaper.isNumber and: { shaperMode.isNumber }) { filt } {
		var shpA  = shaper.clip(0, 1);
		var x     = filt * (1 + (shpA * 9));
		var shaped = Select.ar(shaperMode.round(1).clip(0, 6),
			[filt, x.tanh, x.clip(-1, 1), x.fold2(1), x.wrap2(1), (x * 0.5pi).sin, (x.abs * 2) - 1]);
		(filt * (1 - shpA)) + (shaped * shpA)
	};
	(filt: filt, post: post)
};
// The schema of the block, ONE table the two synths' ~f2UnitSpecs merge whole
// and the sampler's takes ~f2FltCore of (the card dims and relabels per model
// from the same source): the label / range / sel list of every control the
// slot, the high-pass and the FEG declare. Defaults are NOT here — they come
// from each unit's SynthDesc, and they differ per unit (polysynthU keytrack 1,
// fltMode 1 = LP4, hpMode 0, hpFreq 20; polymerU 0, 0, 1, 19.4; samplerU
// filtOn 0, fltMode 1, filtKey 1). Ranges are supersets of what either unit had, same meaning at every
// old value: cut / hpFreq 19.4…33500 ⊃ 20…20000 / 20…8000, keytrack 0…2 ⊃ 0…1,
// fAtk / fDec 8 s ⊃ 4 s, egAmt ±120 st ⊃ the old ±1 (×72 — a RESCALE the store
// applies on load, the one migration that changes a number). fltMode / fltMode2
// ship generic labels: unitSpecs is keyed by UNIT, not by variant, so one entry
// cannot carry eleven label sets and the card relabels them per `filt`.
~f2FltSpecs = {
	var sp = ();
	sp[\filtOn]     = (min: 0, max: 1, warp: \lin, label: "filter", sel: #["—", "ON"]);
	sp[\fltMode]    = (min: 0, max: 15, warp: \lin, label: "mode",
		sel: #["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15"]);
	sp[\drive]      = (min: -24, max: 24, warp: \lin, unit: "dB", label: "drive");
	sp[\cut]        = (min: 19.4, max: 33500, warp: \exp, unit: "Hz", label: "cutoff");
	sp[\res]        = (min: 0, max: 1, warp: \lin, label: "res");
	sp[\keytrack]   = (min: 0, max: 2, warp: \lin, label: "note");
	// the gain of `poly`'s eighth response, BELL — the sampler's, read at fltMode
	// 7 only and declared on all three units so the key means one thing (§5)
	sp[\bellGain]   = (min: -24, max: 24, warp: \lin, unit: "dB", label: "bell");
	sp[\egAmt]      = (min: -120, max: 120, warp: \lin, unit: "st", label: "EG");
	sp[\filtFm]     = (min: 0, max: 1, warp: \lin, label: "fm");
	sp[\shaper]     = (min: 0, max: 1, warp: \lin, label: "shaper");
	sp[\shaperMode] = (min: 0, max: 6, warp: \lin, label: "shaper mode", sel: #["OFF", "SOFT", "HARD", "FOLD", "WRAP", "SINE", "RECT"]);
	// the per-model cells (FILTER.md §1.1) — declared on all three units, read by
	// the arms of the models that have them
	sp[\resLimit]   = (min: 0, max: 1, warp: \lin, label: "limit");
	sp[\fltLin]     = (min: 0, max: 1, warp: \lin, label: "linearity", sel: #["SYM", "ASYM"]);
	sp[\fltMode2]   = (min: 0, max: 7, warp: \lin, label: "mode 2",
		sel: #["0", "1", "2", "3", "4", "5", "6", "7"]);
	sp[\fltFbGain]  = (min: -1, max: 1, warp: \lin, label: "fb gain");
	sp[\fltFbCut]   = (min: 0, max: 1, warp: \lin, label: "fb cut");
	sp[\fltColor]   = (min: -1, max: 1, warp: \lin, label: "color");
	sp[\fltVowel]   = (min: -1, max: 1, warp: \lin, label: "vowel");
	// the pre-model high-pass (drawn where each card already keeps it)
	sp[\hpMode]     = (min: 0, max: 2, warp: \lin, label: "hp mode", sel: #["—", "2p", "4p"]);
	sp[\hpFreq]     = (min: 19.4, max: 33500, warp: \exp, unit: "Hz", label: "hp");
	sp[\hpRes]      = (min: 0, max: 1, warp: \lin, label: "hp res");
	// the FEG (§1.6): fEnvModel is §6.5 on both units; fSubNoise gates polymerU's
	// sub and noise legs before either crossfade (§1.3) and has nothing to gate on
	// polysynthU (its sub and noise live inside the oscillator lanes — no
	// pre-filter leg, so it is never read there)
	sp[\fAtk]       = (min: 0.001, max: 8, warp: \exp, unit: "s", label: "A");
	sp[\fDec]       = (min: 0.01, max: 8, warp: \exp, unit: "s", label: "D");
	sp[\fSus]       = (min: 0, max: 1, warp: \lin, label: "S");
	sp[\fRel]       = (min: 0.01, max: 8, warp: \exp, unit: "s", label: "R");
	sp[\fVel]       = (min: 0, max: 1, warp: \lin, label: "vel");
	sp[\fEnvModel]  = (min: 0, max: 2, warp: \lin, label: "model", sel: #["A", "R", "D"]);
	sp[\fSubNoise]  = (min: 0, max: 1, warp: \lin, label: "sub+nz", sel: #["—", "S+N"]);
	sp
}.value;

// ── §curve THE DRAWN POINT LIST (POLYMER.md §1.2.9 / §6.8, ENVELOPE.md §2.9) ─
// ONE encoding and ONE renderer serving two models, because they are one data
// problem — and that is Bitwig's own grouping, not F2's convenience: 5.0 shipped
// Segments, Curves, Scrawl, Slopes and Transfer as one MSEG family sharing one
// editor and one file format `✓ [REL]`. `osc: scrawl` reads the render as a
// single audio cycle, `env: segments` reads the same floats as an envelope.
//
// THE GRAMMAR (v1), the whole of it — one fixed-stride string, base-32, three
// equal 10-bit fields per point, a two-character header:
//     curve := "1" shape point{0,64}
//     shape := "C" (closed — Scrawl) | "O" (open — Segments)
//     point := PP VV KK                     // 6 characters, three 2-char fields
//     field := b32 b32                      // code = hi*32 + lo, 0…1023
//     b32   := [0-9A-V]                     // base32hex, 5 bits
// The value rides in an opt, so it becomes a SuperCollider symbol AND a word of
// the compiled session text, where everything outside [A-Za-z0-9_] is rewritten
// (compiler `sanPort`) — base32hex passes both untouched, which is the same
// constraint `cuts` is written to (~f2SmpCuts).
// Base-32 and not 63 characters of the legal set: 63 is not a power of two, so a
// radix-63 value is a bignum conversion in which no point is a readable field
// and ONE corrupt character shifts every later point. Two base-32 digits are a
// field with no bit packing across a character boundary, and `clump(6)` is the
// whole decoder.
~f2CurveVer    = $1;
~f2CurveAlpha  = "0123456789ABCDEFGHIJKLMNOPQRSTUV";   // base32hex, index = value
~f2CurveRadix  = 32;
// Codes span 0…960; 961…1023 are OUT OF RANGE and the point carrying one is
// dropped WHOLE, never guessed at (~f2SmpCuts' own rule for a non-integer
// token). 961 levels and not 1024 because an axis with a meaningful CENTRE needs
// an ODD level count, or a wave drawn flat at zero carries a DC offset no snap
// can remove — and 960 puts every fraction a wave editor reaches for exactly on
// the grid (½ ⅓ ¼ ⅕ ⅙ ⅛ 1/10 1/12 1/16 1/24 1/32 1/64).
~f2CurveField  = 960;
// 64 points, and it is F2's cap against Bitwig's «as many points as you need»
// (§7 Q23). The number is the EDITOR's: 64 points across the widest drawing
// surface the card has sit 5.6 px apart against a 4.2 px grab radius, so at 64
// two neighbours are just outside each other's reach and at 96 they are inside
// it and become ungrabbable. On this side 64 points over 16384 samples is 256
// samples a segment against a top mip level that keeps 1024 harmonics, so the
// cap costs the spectrum nothing. A 64-point value is 386 characters, the same
// order as `cuts`' declared 314-character ceiling.
~f2CurveMax    = 64;
// The render: 16384 samples of the HALF-OPEN cycle plus ONE GUARD FRAME. That
// single extra frame is the whole trap of §1.2.9 in one line — the terminal
// point must exist as a rendered VALUE (it is the right-hand limit of the last
// segment) and must never exist as a stored POINT. Store it and it is a 65th
// draggable handle that can be moved off its partner; leave it unrendered and
// the last segment is held flat to the end and the wrap carries a step 8192×
// the interior one.
~f2CurveRender = 16384;
~f2CurveLevels = 12;            // mip levels, the ~f2PolyTables bank's own count
~f2CurveTable  = 2048;          // points per level ⇒ 4096-frame wavetable buffers
// The empty value is the schema default and STAYS the schema default — the
// editor never writes on a model pick — so both sides fall back to the same
// declared drawing. Two shapes and not one because the axis MEANING differs: the
// closed triangle read unipolar is an envelope that starts at half.
//   scrawl   3 points closed: (0, ½) (¼, 1) (¾, 0), terminal (1, ½) implied — a
//            triangle, and bipolar exactly the geometric one the tri bank holds.
//   segments 3 points open: (0, 0) (¼, 1, curve −4) (1, 0) — the AD every synth
//            envelope starts life as, with Env.adsr's own −4 on both segments.
~f2CurveDefault = (scrawl: "1C00F0F07GU0F0MG00F0", segments: "1O0000MG7GU0MGU000F0");

// One base-32 digit → 0…31, or nil. A character outside the alphabet is not a
// digit to guess at: it drops its whole point below.
~f2CurveDigit = { |ch| (topEnvironment[\f2CurveAlpha] ? "").indexOf(ch) };
// THE DECODER. `raw` → (closed: bool, pts: [[p, u, k] …]) or nil when the header
// is not this grammar's. Every rule of the shape lives here so the two readers
// cannot disagree:
//   · points are sorted NON-DECREASING by position, STABLY — equal positions are
//     not a duplicate to dedupe, they are a VERTICAL STEP, which is how a square
//     or a staircase is drawn. sclang's `sort` is not documented stable, so the
//     index is carried through the comparison rather than trusted;
//   · the first point is pinned at 0 by the encoder; a decoded list that starts
//     past 0 is HELD from 0 at that point's value below, never extrapolated;
//   · past the cap the first 64 OF THE STRING are kept — the cap bites before the
//     sort, which is the order curveList.ts decodes in, and the two renderers may
//     not differ by so much as a rule — and the rest are dropped with one warning:
//     a hand-edited save is told, never silently truncated;
//   · a body that is not a whole number of points is refused outright, not padded
//     or part-read: a ragged value is a corrupted one, and half a point is a
//     coordinate nobody drew.
~f2CurvePoints = { |raw|
	var s = (raw ? "").asString;
	var field = (topEnvironment[\f2CurveField] ? 960);
	var maxp  = (topEnvironment[\f2CurveMax] ? 64);
	var dig   = topEnvironment[\f2CurveDigit];
	var body, closed, pts = [];
	if (s.size < 2 or: { s[0] != (topEnvironment[\f2CurveVer] ? $1) }
		or: { (s[1] != $C) and: { s[1] != $O } }) { nil } {
		closed = (s[1] == $C);
		body = s.copyToEnd(2);
		if ((body.size % 6) != 0) { body = nil };
		(body ? "").clump(6).do { |t, i|
			var f = [0, 2, 4].collect { |j|
				var hi = dig.(t[j]), lo = dig.(t[j + 1]);
				if (hi.isNil or: { lo.isNil }) { -1 } { (hi * 32) + lo }
			};
			// an out-of-range or unreadable field drops the POINT, not the field:
			// a guessed coordinate is a shape the user never drew
			if (f.every { |c| (c >= 0) and: { c <= field } }) {
				pts = pts.add([f[0] / field, f[1] / field, ((f[2] / field) * 2) - 1, i]);
			};
		};
		if (pts.size > maxp) {
			topEnvironment[\f2UnitWarnOnce].value(("curve_cap_" ++ s.size).asSymbol,
				"⚠ [f2 curve] a % -point list was read and F2's cap is % (POLYMER.md §7 Q23) — the first % are kept".format(
					pts.size, maxp, maxp));
			pts = pts.keep(maxp);
		};
		// stable by construction: ties fall back to the string index, so two points at
		// one position stay in the order they were written and remain a vertical STEP
		pts = pts.sort { |a, b| (a[0] < b[0]) or: { (a[0] == b[0]) and: { a[3] <= b[3] } } };
		if (body.isNil or: { pts.isEmpty }) { nil }
			{ (closed: closed, pts: pts.collect { |q| q.copyFromStart(2) }) }
	}
};
// ONE segment, t ∈ 0…1. Curvature −1…+1 maps to SC's Env curve as c = −8·k — the
// SAME inversion §2.5 gives the envelope's A/R/D curve knobs, so one number
// means one thing on the whole card — and the formula below IS EnvGen's curved
// segment, so a drawn curvature and a knobbed one bend identically.
~f2CurveSeg = { |y0, y1, t, k|
	var c = -8 * k;
	if (c.abs < 1e-6) { y0 + ((y1 - y0) * t) }
	{ y0 + ((y1 - y0) * (1 - exp(c * t)) / (1 - exp(c))) }
};
// THE RENDER: `raw` → n + 1 floats, unipolar 0…1. Frames 0…n−1 are the HALF-OPEN
// cycle at φ = i/n; frame n is the GUARD FRAME holding the terminal value.
//   · under "C" the terminal point is (1, u of point 0) and the LAST STORED
//     point's curvature runs into it — that is what makes the single cycle wrap
//     seamlessly and what §1.2.9 says must not be stored twice;
//   · under "O" the last stored point is at code 960 and IS the end, so the
//     terminal value is its own and the appended frame repeats it exactly.
// Read the CLOSED interval instead (n samples spanning period n−1) and the cycle
// is no longer periodic in the table: the FFT leaks, and the free band-limiting
// §1.2.9 promises is gone. Hold the last stored value to the end instead of
// running its segment into the implied terminal point and the wrap grows a step
// thousands of times the interior one. That step is the click.
~f2CurveShape = { |raw, n|
	var d = topEnvironment[\f2CurvePoints].value(raw);
	var nn = (n ? (topEnvironment[\f2CurveRender] ? 16384)).asInteger.max(2);
	var seg = topEnvironment[\f2CurveSeg];
	var pts, ext, term, j = 0;
	if (d.isNil) { nil } {
		pts = d[\pts];
		// held from 0, never extrapolated: a first point past the start means the
		// user drew nothing before it, not that the shape continues backwards
		if (pts[0][0] > 0) { pts = [[0.0, pts[0][1], 0.0]] ++ pts };
		term = if (d[\closed]) { pts[0][1] } { pts.last[1] };
		ext = pts ++ [[1.0, term, 0.0]];
		Array.fill(nn + 1, { |i|
			var phi = i / nn, p0, y0, k0, p1, y1, w;
			while { (j + 2) < ext.size and: { ext[j + 1][0] <= phi } } { j = j + 1 };
			p0 = ext[j][0]; y0 = ext[j][1]; k0 = ext[j][2];
			p1 = ext[j + 1][0]; y1 = ext[j + 1][1];
			w = p1 - p0;
			// a zero-width segment is two points at one position — a VERTICAL STEP,
			// and its value is the second point's
			if (w <= 0) { y1 } { seg.(y0, y1, ((phi - p0) / w).clip(0, 1), k0) }
		})
	}
};
// The partial count of mip level l — ~f2PolymerTablePartials' law to the
// character, so `lvl` means the same thing on the saw bank, the triangle bank,
// the half-sine bank and every drawn one: level L covers [27.5·2^L, 55·2^L) and
// keeps the harmonics that stay under SR/2 for the TOP of that band.
~f2CurveHarm = { |l, sr = 48000| (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024) };
// THE MIP BANK, offline: 16384 bipolar samples → 12 band-limited 2048-point
// tables in wavetable format. One forward FFT of the genuinely periodic cycle,
// then one inverse per level with every bin above ~f2CurveHarm zeroed — no
// window, no endpoint fixup, because the cycle IS periodic (that is the whole
// point of the guard frame living outside it).
// Nothing is NORMALISED, unlike the three fixed banks: those hold one known
// shape per level and a peak of 1 means the same thing on all twelve, while a
// drawn shape's top level is often a bare sine — per-level normalising would
// turn the mip step into a gain jump of tens of dB. The drawn amplitude is the
// amplitude, and `gain` / `amp` are where headroom is dealt with (§7 Q4's rule).
// The DC term is KEPT (bin 0 of the inverse): a drawn shape's mean is part of
// the shape, and the unit's one 0.9993 blocker is where it goes (§2 decision 5).
~f2CurveBank = { |sig, sr = 48000|
	var nR = (topEnvironment[\f2CurveRender] ? 16384);
	var nT = (topEnvironment[\f2CurveTable] ? 2048);
	var nL = (topEnvironment[\f2CurveLevels] ? 12);
	var ctF = Signal.fftCosTable(nR), ctI = Signal.fftCosTable(nT);
	// sclang's fft is UNNORMALISED and its ifft carries the 1/N, so resampling a
	// spectrum from nR bins to nT bins is one factor of nT/nR (measured, not
	// assumed: fft of cos at bin k comes back as N/2, and ifft(fft(x)) == x)
	var scale = nT / nR;
	var cplx = fft(Signal.newFrom(sig), Signal.newClear(nR), ctF);
	var re = cplx.real, im = cplx.imag;
	Array.fill(nL, { |l|
		// h is capped one below nT/2: bin nT/2 is the inverse table's own Nyquist
		// bin, which is self-conjugate and cannot carry a phase — a harmonic
		// written there would come out as an arbitrary cosine
		var h = topEnvironment[\f2CurveHarm].value(l, sr).min((nT div: 2) - 1);
		var r2 = Signal.newClear(nT), i2 = Signal.newClear(nT);
		r2[0] = re[0] * scale; i2[0] = im[0] * scale;
		(1 .. h).do { |k|
			r2[k] = re[k] * scale;            i2[k] = im[k] * scale;
			r2[nT - k] = re[nR - k] * scale;  i2[nT - k] = im[nR - k] * scale;
		};
		ifft(r2, i2, ctI).real.asWavetable.asArray
	})
};

// /b_setn in chunks. A 4096-frame table is ~16 kB of OSC in one message and a
// whole bank is twelve of them back to back; scsynth's UDP path drops what it
// cannot read in one datagram, and a dropped fill is a buffer full of ZEROS,
// which is SILENCE with nothing in the log (the failure ~f2SmpWins documents
// from the other direction). 1024 floats a message is ~4 kB and always fits.
~f2CurveSend = { |buf, data|
	var n = data.size, chunk = 1024, i = 0;
	while { i < n } {
		var m = (n - i).min(chunk);
		s.listSendMsg(['/b_setn', buf.bufnum, i, m] ++ data.copyRange(i, i + m - 1));
		i = i + m;
	};
	nil
};
// One entry per ENCODED STRING, not per card, and that is what makes the
// double-buffered swap unnecessary rather than merely cheap: a new drawing is a
// DIFFERENT key and gets DIFFERENT bufnums, so no buffer is ever written while
// it is being read. The mechanism the contract's two halves were for is already
// in the deploy path — a `curve` edit changes the card's opts, which are baked
// into the pool fingerprint (f2dsl `cfgSig`), so the old voices are gate-0'd at
// once and freed 0.4 s later while the fresh pool spawns on the new bufnums.
// Two halves would give exactly one gesture of grace; the LRU gives sixteen.
// A failure is cached too — a value that does not decode must not re-kick a
// render on every note.
~f2Curves !? { |old| old.do { |e| (e[\bufs] ? []).do { |b| try { b.free } } } };
~f2Curves = IdentityDictionary.new;
// …and the bound on how many may exist at once. Thirteen server buffers an entry
// (12 × 4096 mip + 1 × 16385 shape ≈ 262 kB), so sixteen is ~4.2 MB and 208
// bufnums — real pressure beside ~f2PolyTables (12), ~f2PolymerTables (24) and
// ~f2SmpWins (16), which is why the allocation below takes ~f2PolymerTables'
// escape instead of throwing. Sixteen is a gesture's worth of undo plus the few
// a preset actually uses; the evicted one costs one note on the default drawing
// to re-render, never a wrong sound.
~f2CurveCacheMax = 16;
~f2CurveLRU = [];
~f2CurveTouch = { |key|
	var cache = topEnvironment[\f2Curves] ? IdentityDictionary.new;
	var max   = (topEnvironment[\f2CurveCacheMax] ? 16).max(1);
	var lru   = (topEnvironment[\f2CurveLRU] ? []).reject { |k| k == key } ++ [key];
	var i;
	while { lru.size > max } {
		// the oldest entry that is NOT still rendering. A pending one is held by a
		// running fork which is about to /b_setn into those bufnums: freeing them now
		// would let the next allocation take the numbers and be written over by the
		// old render — silent corruption with nothing in the log. So it is skipped,
		// and if every entry is pending the cache stays over its bound until one of
		// them lands (~f2ConvIrTouch, line for line, and for the same reason).
		i = lru.detectIndex { |k| (cache[k] !? { |e| e[\state] }) != \pending };
		if (i.isNil) {
			max = lru.size;
		} {
			var drop = lru.removeAt(i);
			cache[drop] !? { |e| (e[\bufs] ? []).do { |b| try { b.free } } };
			cache.removeAt(drop);
		};
	};
	topEnvironment[\f2CurveLRU] = lru;
	nil
};
// Forget ONE key — for a failure whose cause goes away (no server yet, no free
// consecutive bufnums), so the next note renders instead of reading the default
// for the rest of the session. A value that does not DECODE is not this: that
// entry stays \failed on purpose, or every note re-decodes a string that will
// never parse and re-prints its warning's key check.
~f2CurveDrop = { |key|
	var cache = topEnvironment[\f2Curves] ? IdentityDictionary.new;
	cache[key] !? { |e| (e[\bufs] ? []).do { |b| try { b.free } } };
	cache.removeAt(key);
	topEnvironment[\f2CurveLRU] = (topEnvironment[\f2CurveLRU] ? []).reject { |k| k == key };
	nil
};
// The drawing a card reads while its own is still rendering, and the one an
// EMPTY `curve` reads for ever: the two schema defaults, prepared once per
// f2units load. Going silent in that window is the wrong default — a card whose
// render is one block late would drop out of the mix on every reload — so an
// unprepared curve SOUNDS, on the shape the card's own editor opens at. The bank
// is the scrawl default and the shape buffer the segments one, so each reader
// gets ITS default from the one null pair. Both stay -1 without a booted server
// (the NRT harnesses load this file with nothing running and build their own);
// the graphs read -1 as «no table at all» and fall back to buffer 0, which is
// what every other bank in this file does when its allocation failed.
~f2CurveNullBufs !? { |old| old.do { |b| try { b.free } } };
~f2CurveNullBufs = [];
~f2CurveNull = -1;
~f2CurveNullShape = -1;
if (s.serverRunning) {
	{
		try {
			var sr = (s.sampleRate ? 48000);
			var nR = topEnvironment[\f2CurveRender];
			var shp = topEnvironment[\f2CurveShape].value(topEnvironment[\f2CurveDefault][\scrawl], nR);
			var env = topEnvironment[\f2CurveShape].value(topEnvironment[\f2CurveDefault][\segments], nR);
			var bank = topEnvironment[\f2CurveBank].value(shp.copyFromStart(nR - 1).collect { |u| (2 * u) - 1 }, sr);
			var bufs = Buffer.allocConsecutive(topEnvironment[\f2CurveLevels], s, topEnvironment[\f2CurveTable] * 2);
			var sbuf = Buffer.alloc(s, nR + 1, 1);
			s.sync;                                   // every allocation has landed
			bufs.do { |b, l| topEnvironment[\f2CurveSend].value(b, bank[l]) };
			topEnvironment[\f2CurveSend].value(sbuf, env);
			s.sync;                                   // …and every fill
			topEnvironment[\f2CurveNullBufs] = bufs ++ [sbuf];
			topEnvironment[\f2CurveNull] = bufs.first.bufnum;
			topEnvironment[\f2CurveNullShape] = sbuf.bufnum;
			("✓ f2 curve: default drawings → mip bank %…%, shape buf %".format(
				bufs.first.bufnum, bufs.last.bufnum, sbuf.bufnum)).postln;
		} { |e|
			("⚠ [f2 curve] the default drawings could not be prepared: % — a scrawl or segments card whose own render is not ready yet reads buffer 0".format(e.errorString)).postln;
		};
	}.fork(SystemClock);
};
// The entry for one encoded string: the 12-level mip bank `osc: scrawl` reads
// and the single 16385-frame shape buffer `env: segments` reads, both products
// of ONE render. Returns the pair a card's two engine args take — the null pair
// while the fork runs, so the note that asked plays through on the default
// drawing and ~f2CurveSwap moves it the moment the real one lands.
~f2CurveAt = { |raw, cardKey|
	// topEnvironment, not `~`: this runs from \f2voice inside an Event, where
	// currentEnvironment is that Event and every `~name` of the library is nil
	var d   = topEnvironment[\f2Curves];
	var nul = (curveBuf: (topEnvironment[\f2CurveNull] ? -1),
		shapeBuf: (topEnvironment[\f2CurveNullShape] ? -1));
	var str = (raw ? "").asString;
	var key = str.asSymbol;
	var e;
	if (str.isEmpty) { nul } {
		e = d[key];
		topEnvironment[\f2CurveTouch].value(key);
		case
			{ e.notNil } {
				// still rendering: take the default now and be moved when it lands
				if (e[\state] == \ready) { (curveBuf: e[\curveBuf], shapeBuf: e[\shapeBuf]) } {
					if (e[\state] == \pending and: { cardKey.notNil }) {
						e[\waiting] = (e[\waiting] ? []).add(cardKey);
					};
					nul
				}
			}
			{ true } {
				var sr = (s.sampleRate ? 48000);
				var nR = topEnvironment[\f2CurveRender];
				// only the DECODE happens here, and it is 64 points of arithmetic. The
				// 16385-sample render and the twelve inverse FFTs are inside the fork
				// below: this runs from \f2voice inside Event:play, and a tenth of a
				// second of language work on a note is a stall you hear on every other
				// card in the strip (the rule ~f2SmpKick is written to).
				var ok = topEnvironment[\f2CurvePoints].value(str).notNil;
				var bufs, sbuf;
				e = (state: \pending, curveBuf: nul[\curveBuf], shapeBuf: nul[\shapeBuf],
					bufs: [], waiting: if (cardKey.isNil) { [] } { [cardKey] });
				d[key] = e;
				// The two ways this can stop here are NOT the same failure and must not
				// print the same line. A value that does not decode is the CARD's and
				// never will decode, so the entry stays \failed and the decode is not
				// retried per note. No server is the RIG's and goes away: the entry is
				// dropped so the first note after the boot renders, and the message says
				// «no server» — printing «not a v1 curve value» there blames a drawing
				// that is perfectly good, which is exactly how an engine ends up looking
				// guilty for something it did not do.
				if (ok.not) {
					e[\state] = \failed;
					topEnvironment[\f2UnitWarnOnce].value(("curve_bad_" ++ key).asSymbol,
						"⚠ [f2 curve] % is not a v1 curve value — the card reads the default drawing".format(
							if (str.size > 24) { str.copyFromStart(23) ++ "…" } { str }));
					nul
				} { if (s.serverRunning.not) {
					topEnvironment[\f2CurveDrop].value(key);
					topEnvironment[\f2UnitWarnOnce].value(\curve_noserver,
						"⚠ [f2 curve] no server — a drawn curve renders on the first note after the boot; until then the card reads the default drawing");
					nul
				} {
					// Buffer.allocConsecutive → Server:nextBufferNumber THROWS ("No block
					// of % consecutive buffer numbers is available") instead of returning
					// nil, so the alloc is inside `try` and a failure keeps the default
					// drawing rather than abandoning the note (~f2PolymerTables' escape)
					bufs = try { Buffer.allocConsecutive(topEnvironment[\f2CurveLevels], s,
						topEnvironment[\f2CurveTable] * 2) } { |err|
						topEnvironment[\f2UnitWarnOnce].value(\curve_alloc,
							"⚠ [f2 curve] a mip bank could not be allocated (%) — the card reads the default drawing until buffers are free".format(err.errorString));
						nil
					};
					// the entry is DROPPED, not marked \failed: the message promises the
					// card reads the default «until buffers are free», and a \failed entry
					// is never retried, so without this the promise is one a later note
					// could not keep
					if (bufs.isNil) { topEnvironment[\f2CurveDrop].value(key); nul } {
						sbuf = Buffer.alloc(s, nR + 1, 1);
						e[\bufs] = bufs ++ [sbuf];
						{
							var done = true;
							try {
								var shp = topEnvironment[\f2CurveShape].value(str, nR);
								var bank = topEnvironment[\f2CurveBank].value(
									shp.copyFromStart(nR - 1).collect { |u| (2 * u) - 1 }, sr);
								s.sync;                       // every allocation has landed
								bufs.do { |b, l| topEnvironment[\f2CurveSend].value(b, bank[l]) };
								topEnvironment[\f2CurveSend].value(sbuf, shp);
								s.sync;                       // …and every fill
							} { |err| done = false;
								topEnvironment[\f2UnitWarnOnce].value(("curve_fill_" ++ key).asSymbol,
									"⚠ [f2 curve] the drawing % could not be rendered: % — the card reads the default drawing".format(
										key, err.errorString));
							};
							if (done) {
								e[\curveBuf] = bufs.first.bufnum; e[\shapeBuf] = sbuf.bufnum;
								e[\state] = \ready;
								topEnvironment[\f2CurveSwap].value(e);
								("✓ [f2 curve] % points → mip bank %…%, shape buf % (% chars)".format(
									(topEnvironment[\f2CurvePoints].value(str) !? { |q| q[\pts].size }) ? 0,
									bufs.first.bufnum, bufs.last.bufnum, sbuf.bufnum, str.size)).postln;
							} { e[\state] = \failed };
						}.fork(SystemClock);
						nul                    // this note plays through; the swap moves it
					}
				} }
			}
	}
};
// THE SWAP. A voice spawned while the render was in flight took the default
// drawing; the moment the real one lands it is moved to it, at a control-block
// boundary, with nothing rewritten under it. It reaches exactly the nodes of the
// cards that asked — the pool's own demux routes a prefixed `id__param` to the
// card that owns it (f2dsl ~f2VDemux), and the pool key names the preset, so a
// second preset that happens to reuse a card id is not touched.
// Without this the first note after every deploy would play the default shape
// for its whole length; with it the wrong wave lasts a few milliseconds.
~f2CurveSwap = { |e|
	var set = topEnvironment[\f2VSet];
	var pools = topEnvironment[\f2Voices];
	var waiting = (e[\waiting] ? []);
	e[\waiting] = [];
	if (set.notNil and: { pools.notNil }) {
		waiting.asSet.do { |ck|
			var cs = ck.asString, i = cs.find("|");
			var pdef = if (i.isNil) { "" } { cs.copyFromStart(i - 1) };
			var cid  = if (i.isNil) { cs } { cs.copyToEnd(i + 1) };
			var args = [(cid ++ "__curveBuf").asSymbol, e[\curveBuf],
				(cid ++ "__shapeBuf").asSymbol, e[\shapeBuf]];
			pools.keysValuesDo { |pk, pool|
				// the pool key is `scene|preset@group`, so this is the preset's own pools
				// and nobody else's
				if (pk.asString.contains("|" ++ pdef ++ "@")) {
					(pool[\synths] ? []).do { |v| if (v.notNil) { try { set.(v, args) } } };
				};
			};
		};
	};
	nil
};
// What \f2voice calls at spawn, the mirror of ~f2SmpRes / ~f2ConvIrRes: the
// card's opts → the pair of bufnums its `curveBuf` and `shapeBuf` take. `curve`
// is the only resource opt here and an empty one is the schema default, so a
// card nobody has drawn on reads the default drawing rather than buffer 0.
// `cardKey` is `<preset>|<card id>` and is used for the swap alone — the CACHE is
// keyed on the drawing itself, so two cards on one curve share one bank.
~f2CurveRes = { |opts, cardKey|
	var o = opts ? ();
	var v = (o[\curve] ? o["curve"]);
	topEnvironment[\f2CurveAt].value(if (v.isNil) { "" } { v.asString }, cardKey)
};
// A samples/units reload replaces the server's buffers under us: drop the lot
// and let the next spawn re-render (the twin of ~f2SmpForget / ~f2ConvIrForget,
// called beside them).
~f2CurveForget = {
	(topEnvironment[\f2Curves] ? IdentityDictionary.new).do { |e|
		(e[\bufs] ? []).do { |b| try { b.free } };
	};
	topEnvironment[\f2Curves] = IdentityDictionary.new;
	topEnvironment[\f2CurveLRU] = [];
	nil
};

// ── §env the ONE amplitude envelope of polysynthU, samplerU and polymerU ───
// (docs/design/ENVELOPE.md). Three envelopes that shared four names — the
// polysynth's fixed −4 Env.adsr, the sampler's AHDSR with three curve knobs or
// its one-shot, the polymer's Env.adsr with a model select and curve knobs
// declared and unread — are ONE block now: the structural opt `env` (a SynthDef
// variant, «from the next note») lists the same seven models in the same order
// on all three cards; every control any model reads is declared by all three
// defs (§1.2 — a card swapping models moves no knob and breaks no lock); and
// what differs per unit stays per unit, marked where it is read: the default
// model (adsr / ahdsr / adsr), the default curves and `envModel` (the synths'
// fixed −4 IS Analog; the sampler's knobs were always read, which is Digital),
// and the one-shot's BODY (§2.8). A save renders as it did: at its defaults each
// unit's fragment Env is the Env it built before, node for node —
// sc/nrt/envab.scd proves it in sclang (the Env arrays) and in a render (§4.7).
~f2EnvModels = #[\adsr, \ahdsr, \ar, \ad, \pluck, \shot, \segments];
// Per unit, the models with an arm in ~f2Aeg; the FIRST entry is the unit's
// default and the one the generator falls back to — the mirror of the front's
// UNIT_BUILT[unit].env, so the two must not drift. `shot` is built on all
// three: on the sampler its own one-shot (the read window as the body), on the
// two synths the same arm with `hold` as the body (§2.8, §5 Q3's
// recommendation — no Bitwig synth has a Shot, it is F2's, and the card's
// tooltip says so). `segments` — the drawn shape, §2.9 — is built on all three
// since §curve: a Sweep over the rendered buffer, ONE-SHOT only, so the list is
// COMPLETE and no advertised envelope falls back on any unit any more.
~f2EnvBuilt = (
	polysynthU: #[\adsr, \ahdsr, \ar, \ad, \pluck, \shot, \segments],
	samplerU:   #[\ahdsr, \shot, \adsr, \ar, \ad, \pluck, \segments],
	polymerU:   #[\adsr, \ahdsr, \ar, \ad, \pluck, \shot, \segments]
);
// The model a variant builds: `env` out of opts, or the unit's default when the
// key is absent (chainSetOpt drops a value equal to the schema default, so a
// keyless save keeps resolving to `polysynthU__v1_4__v2_1`, `samplerU`,
// `polymerU`). A value without an arm falls back to the unit's first built
// model and says so ONCE per (unit, value), the §flt idiom, naming what brings
// it: «not built» alone reads as a bug to whoever hears an ADSR where they
// picked Pluck. The sampler's `gated` is its old spelling of `ahdsr` (§4.2).
~f2EnvResolve = { |unit, opts, name|
	var u = unit.asSymbol;
	var built = topEnvironment[\f2EnvBuilt][u] ? #[\adsr];
	var want = ((opts !? { |o| o[\env] ? o["env"] }) ? built.first).asSymbol;
	var tag = (polysynthU: "poly", polymerU: "pm", samplerU: "smp")[u] ? u.asString;
	if (want == 'gated') { want = 'ahdsr' };
	if (built.includes(want)) { want } {
		topEnvironment[\f2UnitWarnOnce].value((tag ++ "_env_" ++ want).asSymbol,
			"⚠ [f2 %] env: % is % — % is built as %".format(tag, want,
				if (topEnvironment[\f2EnvModels].includes(want))
					{ "advertised but has no arm on this unit (~f2EnvBuilt)" }
					{ "not an advertised value" },
				name, built.first));
		built.first
	}
};
// The schema of the block, ONE table all three ~f2UnitSpecs merge (§1.2 minus
// `vel`, which stays in OUT — §1.4). Defaults are NOT here: they come from each
// unit's SynthDesc and differ per unit (§1.3). Ranges are supersets of what any
// unit had, same meaning at every old value: atk / dec / hold 4 → 8 s on the
// two that had 4; the curve knobs are SC-native −8…8 everywhere (the sampler's
// units — polymerU's −1…1 storage is REINTERPRETED, not rewritten, §4.3).
~f2EnvSpecs = {
	var sp = ();
	sp[\atk]      = (min: 0.001, max: 8, warp: \exp, unit: "s", label: "A");
	sp[\hold]     = (min: 0.001, max: 8, warp: \exp, unit: "s", label: "H");
	sp[\dec]      = (min: 0.01, max: 8, warp: \exp, unit: "s", label: "D");
	sp[\sus]      = (min: 0, max: 1, warp: \lin, label: "S");
	sp[\rel]      = (min: 0.01, max: 8, warp: \exp, unit: "s", label: "R");
	sp[\atkC]     = (min: -8, max: 8, warp: \lin, label: "A curve");
	sp[\decC]     = (min: -8, max: 8, warp: \lin, label: "D curve");
	sp[\relC]     = (min: -8, max: 8, warp: \lin, label: "R curve");
	sp[\envModel] = (min: 0, max: 2, warp: \lin, label: "model", sel: #["A", "R", "D"]);
	sp[\envLoop]  = (min: 0, max: 1, warp: \lin, label: "loop", sel: #["—", "LOOP"]);
	sp[\fadeIn]   = (min: 0.001, max: 1, warp: \exp, unit: "s", label: "fade in");
	sp[\fadeOut]  = (min: 0.001, max: 1, warp: \exp, unit: "s", label: "fade out");
	sp
}.value;
// The curve of one stage under the A / R / D model (§2.5): A = Analog's fixed
// −4 on every stage (today's Env.adsr, bit for bit); R → D until Relative is
// built (§5 Q5 — D and not A, so a user who picked R and moved a curve knob
// hears the knob); D = the knob. A plain number when `model` is one, so the Env
// can be built outside a SynthDef for the A/B identity check (§4.7); a
// Select.kr per stage otherwise — an Env's curve may be a UGen, which is what
// lets `envModel` be a LIVE select that spends no variant, and EnvGen reads a
// segment's shape when it enters it, so a mod switching models mid-note lands
// on the next segment without a click.
~f2AegCurve = { |model, c|
	if (model.isNumber) { if (model < 0.5) { -4 } { c } }
	{ Select.kr(model.round(1).clip(0, 2), [-4, c, c]) }
};
// The trigger of the triggered models (ad, pluck, shot) — samplerU's shotT line
// lifted whole, one-block-late and all: an EnvGen reads its gate at the block
// edge, so a one-sample audio trigger inside the block is missed outright, and
// a trigger in the voice's FIRST block is compared against whatever the
// recycled node memory held and is missed about half the time (measured there,
// not to be re-learned on the synths). `birth * (gate > 0)`: a parked pool
// voice (spawned gate 0 by \f2voice) must not fire.
~f2AegTrig = { |gate, t_trig|
	TDelay.kr(Trig.kr(gate) + Trig.kr(t_trig) + (Impulse.kr(0) * (gate > 0)), ControlDur.ir)
};
// The Env(s) of a model, from the union's args `p` (an Event), the one-shot's
// `body` and Fragments' `tails` = [tailL, tailT, tailC] — the level-0 segment
// samplerU appends after the release so the envelope's OWN doneAction fires
// late (:tail*, «grains survive voice end»), #[[], [], []] everywhere else.
// Separate from ~f2Aeg so the A/B check can compare Env arrays with no server.
// Returns an Event: `env` is the Env every model has; `ad` adds `loop` (the
// gated, looping form, §2.6) and `pluck` adds `rls` (its gated release, §2.7).
~f2AegEnv = { |envM, p, body, tails|
	var m    = p[\envModel];
	var cA   = topEnvironment[\f2AegCurve].value(m, p[\atkC].clip(-8, 8));
	var cD   = topEnvironment[\f2AegCurve].value(m, p[\decC].clip(-8, 8));
	var cR   = topEnvironment[\f2AegCurve].value(m, p[\relC].clip(-8, 8));
	var atk  = p[\atk].clip(0.001, 8), hold = p[\hold].clip(0.001, 8);
	var dec  = p[\dec].clip(0.01, 8),  sus  = p[\sus].clip(0, 1), rel = p[\rel].clip(0.01, 8);
	var fIn  = p[\fadeIn].clip(0.001, 1), fOut = p[\fadeOut].clip(0.001, 1);
	var tL = tails[0], tT = tails[1], tC = tails[2];
	switch (envM,
		// four stages, gated; at A this is Env.adsr(atk, dec, sus, rel, 1, -4) by
		// Env.adsr's own definition — polysynthU's and polymerU's old graph
		'adsr',  { (env: Env([0, 1, sus, 0] ++ tL, [atk, dec, rel] ++ tT,
			[cA, cD, cR] ++ tC, releaseNode: 2)) },
		// five stages, gated; under D this IS samplerU's gated envelope — the hold
		// is flat (curve 0) and carries no knob
		'ahdsr', { (env: Env([0, 1, 1, sus, 0] ++ tL, [atk, hold, dec, rel] ++ tT,
			[cA, 0, cD, cR] ++ tC, releaseNode: 3)) },
		// «three-stage gated»: attack, sustain AT 1, release — no level, no decay
		'ar',    { (env: Env([0, 1, 0] ++ tL, [atk, rel] ++ tT,
			[cA, cR] ++ tC, releaseNode: 1)) },
		// «two-stage triggered»: no release node, so the gate is ignored after the
		// front and the voice frees at the decay's end. `loop` is EnvGen's own
		// loop — reaching node 2 while the gate is high jumps back to node 0, so
		// A→D repeats; note off enters the 1 ms fall (§2.6, §5 Q4)
		'ad',    { (env: Env([0, 1, 0] ++ tL, [atk, dec] ++ tT, [cA, cD] ++ tC),
			loop: Env([0, 1, 0, 0] ++ tL, [atk, dec, 0.001] ++ tT, [cA, cD, 0] ++ tC,
				releaseNode: 2, loopNode: 0)) },
		// the exponential string-style decay (fixed −8, F2's) and, beside it, the
		// gated release: WITHOUT its releaseNode the release Env would play through
		// in `rel` seconds and free the voice on its own, which is not Pluck. No
		// model, no curve knobs; `atk` is read (~ — Bitwig names no attack) so the
		// trigger stays click-free
		'pluck', { (env: Env([0, 1, 0] ++ tL, [atk, dec] ++ tT, [-4, -8] ++ tC),
			rls: Env([1, 1, 0] ++ tL, [0, rel] ++ tT, [0, -4] ++ tC, releaseNode: 1)) },
		// the one-shot: fade in · body · fade out, the curves ALWAYS read (no
		// model — the sampler's SHOT_SLIDERS today)
		'shot',  { (env: Env([0, 1, 1, 0] ++ tL, [fIn, body, fOut] ++ tT,
			[p[\atkC].clip(-8, 8), 0, p[\relC].clip(-8, 8)] ++ tC)) },
		// §curve the DRAWN shape (§2.9). What this Env is, is the POSITION RAMP —
		// a straight 0…1 over the drawn length — and the shape itself is a buffer
		// read at that position in ~f2Aeg. Putting the ramp in an EnvGen and not a
		// Sweep is what gives the model its doneAction: the ramp reaching 1 IS the
		// end of the one-shot, so the voice frees exactly there, which is what
		// «plays through once» means and what the row's `trig` driver promises.
		// `len` is `dec` relabelled (§3.5's one stated divergence): Rate and
		// Timebase are not in the union, and a shape with no length is not
		// playable — so the union's own 0.01…8 s control is the length, no control
		// is added, and a lock or a modulator aimed at `dec` keeps its target.
		// The Fragments tail is appended as a HOLD AT 1 and not at 0: the tail
		// exists to delay the envelope's own doneAction while grains drain, and a
		// level-0 tail here would run the position back down the shape and replay
		// it backwards.
		'segments', { (env: Env([0, 1] ++ (tL.collect { 1 }), [dec] ++ tT, [0] ++ tC)) }
	)
};
// The envelope itself, called from the three generators in place of their own.
// `envM` is the resolved opt (~f2EnvResolve); `gate` the \f2voice gate; `trig`
// the unit's one-block-late trigger — a UGen (samplerU's shotT, shared with its
// head anchor) or a FUNCTION building ~f2AegTrig, evaluated only by the arms
// that fire on a trigger (Trig / TDelay are not pure UGens, so a gated variant
// must not carry them dead); `p` the union's args; `body` what a one-shot holds
// at 1 between its fades — samplerU's shotLen, the synths' `hold` (§2.8);
// `i_free` the voice's doneAction — under 0 (a pooled voice) nothing frees, on
// every model. EnvGen.ar for every model on every unit (§2.1 / §4.5: a kr
// envelope multiplies audio once per 64-sample block, a zipper on a 1 ms
// attack); `aegK` is the kr copy for telemetry, the Fragments DelayN and
// polymerU's legato `held`, none of which wants an audio-rate wire.
~f2Aeg = { |envM, gate, trig, p, body, tails, i_free|
	var e   = topEnvironment[\f2AegEnv].value(envM, p, body, tails);
	var aeg = switch (envM,
		'adsr',  { EnvGen.ar(e[\env], gate, doneAction: i_free) },
		'ahdsr', { EnvGen.ar(e[\env], gate, doneAction: i_free) },
		'ar',    { EnvGen.ar(e[\env], gate, doneAction: i_free) },
		'ad',    {
			// `envLoop` is LIVE, so both forms run and a Select picks — and the
			// doneAction follows the pick: with both EnvGens freeing, the one-shot
			// would end the voice at the decay's end while the loop was still
			// cycling. EnvGen reads its doneAction input WHEN the envelope ends,
			// so a kr product is honoured (the pool check in envab.scd proves it)
			var loopOn = p[\envLoop].round(1).clip(0, 1);
			var one = EnvGen.ar(e[\env], trig.value, doneAction: i_free * (1 - loopOn));
			var lp  = EnvGen.ar(e[\loop], gate, doneAction: i_free * loopOn);
			Select.ar(loopOn, [one, lp])
		},
		'pluck', {
			// both free the voice, so WHICHEVER reaches zero first ends it — the
			// documented «whichever gets to zero first» for free (§2.7)
			var dcy = EnvGen.ar(e[\env], trig.value, doneAction: i_free);
			var rls = EnvGen.ar(e[\rls], gate, doneAction: i_free);
			dcy * rls
		},
		'shot',  { EnvGen.ar(e[\env], trig.value, doneAction: i_free) },
		'segments', {
			// §curve the ramp drives a read of the 16385-frame shape buffer the card's
			// `curve` opt resolved to (~f2CurveRes). Index ~f2CurveRender IS the GUARD
			// FRAME, so `pos` 1 lands on the terminal value exactly rather than one
			// sample short of it — the same frame that makes the oscillator's cycle
			// wrap seamlessly, read here as the envelope's endpoint.
			// `loop: 0` and cubic interpolation: the ramp crosses 17 frames a sample
			// at the shortest length the knob allows, so interpolation is what keeps
			// a drawn edge from stepping, and the clip is BufRd's own.
			// A shapeBuf of -1 is a card whose render has not landed (or a rig with no
			// server): reading buffer 0 would be an arbitrary sample played as an
			// envelope, so that case is a flat 1 — the voice sounds, undimmed, until
			// the swap moves it (~f2CurveSwap).
			var nR  = topEnvironment[\f2CurveRender] ? 16384;
			var pos = EnvGen.ar(e[\env], trig.value, doneAction: i_free);
			var sb  = p[\shapeBuf] ? -1;
			Select.ar(sb >= 0, [DC.ar(1), BufRd.ar(1, sb.max(0), pos * nR, 0, 2)])
		}
	);
	(aeg: aeg, aegK: A2K.kr(aeg))
};

// ── §poly Polysynth (docs/design/POLYSYNTH.md) ─────────────────────────────
// Bitwig-Polysynth copy as a SOURCE card (no chainIn). Two identical
// wavetable oscillators read the saw bank ~f2PolyTables with an AUDIO-RATE
// phase (Phasor → Osc), so hard sync and retrig are sample-exact; the pulse
// is two saw reads, the octave-up saw and the sub pulse read the neighbouring
// mip levels. The unison lane count per oscillator is STRUCTURAL (opts v1 /
// v2 ∈ {1, 2, 4, 8, 16} → SynthDef variant through ~f2UnitGen; the control
// list is identical for every variant), and so are the filter MODEL (`filt`,
// §flt above — def `poly`, the core this unit has always had) and the envelope
// MODEL (`env`, §env above — def `adsr`, the Env.adsr this unit has always
// had); everything else is a live kr control — the integer selects (oscNOct,
// oscNRetrig, blend, hpMode, filtOn, fltMode, shaperMode, envModel, envLoop)
// included, so mods / locks can target them.
//
// Schema for the front (ctx.unitOpts / ctx.unitSpecs, ~exportContext in
// f2dsl): a menu = values / def / label (the store drops an opt equal to
// def); a knob = min / max / warp (\lin | \exp) + optional unit / label / sel
// (option labels of an integer select, label index = value - min). Defaults
// come from the SynthDesc of the base def. One entry per user-facing control
// of POLYSYNTH.md §1 (+ freq); the plumbing controls out / gate / t_trig /
// i_free / tel_bus / telId have no range and none.
~f2UnitOpts = ~f2UnitOpts ? IdentityDictionary.new;
~f2UnitSpecs = ~f2UnitSpecs ? IdentityDictionary.new;
~f2UnitOpts[\polysynthU] = (
	v1: (values: #['1', '2', '4', '8', '16'], def: '1', label: "osc 1 voices"),
	v2: (values: #['1', '2', '4', '8', '16'], def: '1', label: "osc 2 voices"),
	// §flt the filter model — the same list in the same order as polymerU's. The
	// def MUST stay `poly` and the front's static POLYSYNTH_OPTS.filt.def must be
	// the same string: chainSetOpt drops a value equal to the schema default, and
	// a mismatch would save different opts either side of a boot.
	filt: (values: ~f2FltModels, def: 'poly', label: "filter"),
	// §env the envelope model — the same list in the same order as the other two
	// units'. The def MUST stay `adsr` (this unit's fixed graph IS adsr) and the
	// front's POLYSYNTH_OPTS.env.def the same string, for the reason above.
	env:  (values: ~f2EnvModels, def: 'adsr', label: "envelope"),
	// §curve `kind: \curve` = an opaque encoded point list — the drawn shape of
	// `env: segments` (ENVELOPE.md §2.9). ONE menu on three cards means one
	// RESOURCE on three cards: the opt is declared here in the same words
	// polymerU declares it, because a model the card offers and the engine cannot
	// feed is the silent fallback the §env union exists to end. No value list and
	// no range, so a front that does not know the kind renders nothing for it
	// rather than a broken menu; `max` is how many breakpoints the value may
	// carry. It changes no graph, so it never enters the variant name.
	curve: (values: #[], def: '', label: "curve", kind: \curve, res: true,
		max: (~f2CurveMax ? 64))
);
// §curve `curve` is a RESOURCE opt here for the same reason it is one on
// polymerU: it names a rendered BUFFER, not a graph, so polysynthU__env_segments
// is ONE def however many shapes the session draws.
~f2UnitOptsRes[\polysynthU] = #[\curve];
~f2UnitSpecs[\polysynthU] = {
	var sp = ();
	// oscillators 1 and 2 are identical (§1)
	[1, 2].do { |n|
		var p = "osc" ++ n;
		sp[(p ++ "Pitch").asSymbol]  = (min: -7, max: 7, warp: \lin, unit: "st", label: "pitch");
		sp[(p ++ "Oct").asSymbol]    = (min: -2, max: 3, warp: \lin, label: "oct", sel: #["32'", "16'", "8'", "4'", "2'", "1'"]);
		sp[(p ++ "Shape").asSymbol]  = (min: 0, max: 1, warp: \lin, label: "shape");
		sp[(p ++ "Pw").asSymbol]     = (min: 0.02, max: 0.98, warp: \lin, label: "pw");
		sp[(p ++ "Sub").asSymbol]    = (min: 0, max: 1, warp: \lin, label: "sub");
		sp[(p ++ "SubPw").asSymbol]  = (min: 0.02, max: 0.98, warp: \lin, label: "sub pw");
		sp[(p ++ "Sync").asSymbol]   = (min: 0, max: 60, warp: \lin, unit: "st", label: "sync");
		sp[(p ++ "Retrig").asSymbol] = (min: 0, max: 1, warp: \lin, label: "R", sel: #["—", "R"]);
		sp[(p ++ "Unison").asSymbol] = (min: 0, max: 100, warp: \lin, unit: "cent", label: "unison");
		sp[(p ++ "Width").asSymbol]  = (min: 0, max: 1, warp: \lin, label: "width");
		sp[(p ++ "Pan").asSymbol]    = (min: -1, max: 1, warp: \lin, label: "pan");
	};
	// mix (the high-pass row is in ~f2FltSpecs — the block's contract, drawn here)
	sp[\blend]  = (min: 0, max: 5, warp: \lin, label: "blend", sel: #["MIX", "NEG", "WIPE", "AM", "SIGN", "MAX"]);
	sp[\mix]    = (min: 0, max: 1, warp: \lin, label: "1/2");
	sp[\noise]  = (min: 0, max: 1, warp: \lin, label: "noise");
	sp[\pitch]  = (min: -36, max: 36, warp: \lin, unit: "st", label: "pitch");
	sp[\glide]  = (min: 0, max: 2, warp: \lin, unit: "s", label: "glide");
	sp[\fb]     = (min: 0, max: 1, warp: \lin, label: "fb");
	// §flt filter slot + high-pass + FEG: the shared table, so the two units'
	// schemas cannot drift (filtType is gone — `fltMode` + `filtOn` now)
	sp.putAll(topEnvironment[\f2FltSpecs]);
	// §env the amplitude envelope: the shared table (~f2EnvSpecs), so the three
	// units' schemas cannot drift — atk / dec widened 4 → 8 s, value untouched
	sp.putAll(topEnvironment[\f2EnvSpecs]);
	// output
	sp[\vel]  = (min: 0, max: 1, warp: \lin, label: "vel");
	sp[\gain] = (min: -24, max: 24, warp: \lin, unit: "dB", label: "gain");
	sp[\pan]  = (min: -1, max: 1, warp: \lin, label: "pan");
	sp[\amp]  = (min: 0, max: 1, warp: \lin, label: "out");
	// the note pitch (a group broadcast — no knob; exported for completeness)
	sp[\freq] = (min: 20, max: 20000, warp: \exp, unit: "Hz", label: "freq");
	sp
}.value;

// Generator: opts (v1: '4', v2: '1', filt: 'ld', env: 'pluck') → SynthDef
// `name` (~f2UnitVariantName: polysynthU__env_pluck__filt_ld__v1_4__v2_1;
// without `filt` / `env` — the defaults, `poly` / `adsr` — polysynthU__v1_4__v2_1,
// as before). Nothing but the lane count, the filter model and the envelope
// model differs between the variants. The def size
// is logged: beyond 16383 bytes sclang writes the def file and /d_load's it
// instead of /d_recv (local server) — the 8/16-lane variants need that path.
// Per voice (POLYSYNTH.md §2):
//   freqL = Lag(freq, glide) × pitch → per lane: silent master Phasor at the
//   lane pitch, its wrap (gated by sync > 0.005) + retrig reset the audible
//   Phasor running at pitch × 2^(sync/12); saw / pulse (two saw reads) /
//   octave-up saw blended by shape, sub pulse (own half-rate Phasor, retrig
//   only) blended by sub; lanes detuned ±unison cents and spread ±width
//   around pan, summed / sqrt(N). Blend op → noise → HP → drive → + feedback
//   → the §flt slot (cut × keytrack × FEG × filter FM → model → bypass →
//   shaper) → AEG × vel × gain × amp → Balance2(pan) → LeakDC → Sanitize → Out.
~f2UnitGen[\polysynthU] = { |opts, name|
	var v1 = ((opts !? { |o| o[\v1] }) ? '1').asString.asInteger.clip(1, 16);
	var v2 = ((opts !? { |o| o[\v2] }) ? '1').asString.asInteger.clip(1, 16);
	// §flt the model, resolved BEFORE the graph — a value without an arm builds
	// `poly` (this unit's own) and warns once
	var fltM = topEnvironment[\f2FltResolve].value(\polysynthU, opts, name);
	var fltSlot = topEnvironment[\f2FltSlot];
	var fegF = topEnvironment[\f2Feg];
	// §env the envelope model, resolved the same way — a value without an arm
	// builds `adsr` (this unit's own) and warns once
	var envM = topEnvironment[\f2EnvResolve].value(\polysynthU, opts, name);
	var aegF = topEnvironment[\f2Aeg];
	var trigF = topEnvironment[\f2AegTrig];
	var tbl = topEnvironment[\f2PolyTables];
	var tBase = ((tbl !? { tbl[\base] }) ? 0).asInteger;
	var tLast = (((tbl !? { tbl[\n] }) ? 12).asInteger - 1).max(0);
	var def, bytes;
	if (tbl.isNil) { "⚠ [f2 poly] ~f2PolyTables is not allocated — polysynthU reads buffer 0".postln };
	def = SynthDef(name.asSymbol, { |out = 0, gate = 0, t_trig = 0, amp = 0.5, i_free = 2, tel_bus = 0,
		telId = 0, freq = 220, vel = 1,
		// §curve `shapeBuf` is an ENGINE ARG, set by \f2voice from the card's `curve`
		// opt (~f2CurveRes) and never a knob: it names the 16385-frame rendered
		// drawing `env: segments` reads, so it joins tel_bus / telId and costs the
		// §env budget nothing. -1 is «not rendered yet» and the arm reads a flat 1.
		shapeBuf = -1,
		osc1Pitch = 0, osc1Oct = 0, osc1Shape = 0.5, osc1Pw = 0.5, osc1Sub = 0, osc1SubPw = 0.5,
		osc1Sync = 0, osc1Retrig = 0, osc1Unison = 0, osc1Width = 0, osc1Pan = 0,
		osc2Pitch = 0, osc2Oct = 0, osc2Shape = 0.5, osc2Pw = 0.5, osc2Sub = 0, osc2SubPw = 0.5,
		osc2Sync = 0, osc2Retrig = 0, osc2Unison = 0, osc2Width = 0, osc2Pan = 0,
		blend = 0, mix = 0.5, noise = 0, hpMode = 0, hpFreq = 20, hpRes = 0,
		pitch = 0, glide = 0, fb = 0,
		// §flt the shared filter slot — the same list polymerU declares, in the
		// signal order of the card. fltMode 1 = LP4, the old filtType default; the
		// cells from resLimit on are the Bitwig models' (FILTER.md §3), read by
		// their arms; bellGain by `poly` at BELL
		filtOn = 1, fltMode = 1, drive = 0, cut = 2000, res = 0, keytrack = 1, egAmt = 0, filtFm = 0,
		shaper = 0, shaperMode = 0, resLimit = 1, fltLin = 0, fltMode2 = 0,
		fltFbGain = 0, fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6,
		// §flt the shared FEG: fEnvModel is §6.5; fSubNoise is declared for the
		// contract and NOT wired — this unit's sub is a blend inside each lane and
		// its noise a crossfade after the blend operator, so there is no
		// pre-filter leg for the FEG to gate
		fAtk = 0.01, fDec = 0.3, fSus = 0.5, fRel = 0.3, fVel = 0, fEnvModel = 0, fSubNoise = 0,
		// §env the shared envelope block (ENVELOPE.md §1.3): atk dec sus rel are
		// this unit's own defaults; the eight from `hold` on are NEW args whose
		// defaults are exact no-ops on the old graph — envModel 0 (Analog) pins
		// every curve at the −4 Env.adsr fixed, and hold / fadeIn / fadeOut /
		// envLoop are read by no model a keyless save resolves to
		atk = 0.005, hold = 0.001, dec = 0.2, sus = 0.8, rel = 0.3,
		atkC = -4, decC = -4, relC = -4, envModel = 0, envLoop = 0, fadeIn = 0.001, fadeOut = 0.005,
		gain = 0, pan = 0|
		var g     = gate;
		var velC  = vel.clip(0, 1);
		// §env the AEG through the shared fragment (~f2Aeg): at `adsr` / A this is
		// the Env.adsr(atk, dec, sus, rel, 1, -4) this unit always built, now at
		// ar (§4.5); the trigger is built only by the triggered models; a synth
		// one-shot holds `hold` as its body (§2.8)
		var aegR  = aegF.(envM, g, { trigF.(g, t_trig) },
			(atk: atk, hold: hold, dec: dec, sus: sus, rel: rel, atkC: atkC, decC: decC, relC: relC,
				envModel: envModel, envLoop: envLoop, fadeIn: fadeIn, fadeOut: fadeOut,
				shapeBuf: shapeBuf),
			hold.clip(0.001, 8), #[[], [], []], i_free);
		var aeg   = aegR[\aeg];
		var aegK  = aegR[\aegK];
		// §flt the FEG, vel-scaled by fVel inside the fragment (~f2Feg)
		var feg   = fegF.(g, fAtk, fDec, fSus, fRel, fVel, vel);
		var freqG = Lag.kr(freq.max(1), glide.clip(0, 2));         // portamento on the freq bus
		var freqL = freqG * pitch.clip(-36, 36).midiratio;         // both oscillators
		var sdur  = SampleDur.ir;
		// retrig: a one-sample pulse on every gate front / t_trig (× oscNRetrig per osc)
		var rtA   = Trig1.ar(K2A.ar(Trig.kr(g) + Trig.kr(t_trig)), sdur);
		// one oscillator = n unison lanes → stereo, 1/sqrt(n) normalised
		var oscF  = { |n, oPitch, oOct, oShape, oPw, oSub, oSubPw, oSync, oRetrig, oUnison, oWidth, oPan|
			var baseF  = freqL * oPitch.clip(-7, 7).midiratio * (2 ** oOct.round(1).clip(-2, 3));
			var pw     = oPw.clip(0.02, 0.98);
			var spw    = oSubPw.clip(0.02, 0.98);
			var subA   = oSub.clip(0, 1);
			var shp    = oShape.clip(0, 1);
			var xa     = (shp * 2).clip(0, 1);              // 0 … 0.5: pulse → saw
			var xb     = ((shp - 0.5) * 2).clip(0, 1);      // 0.5 … 1: saw → saw one octave up
			var syncR  = oSync.clip(0, 60).midiratio;       // audible lane rate / master rate
			var syncOn = oSync > 0.005;
			var rt     = rtA * (oRetrig > 0.5);
			var lanes  = n.collect { |i|
				var d     = if (n > 1) { ((i / (n - 1)) * 2) - 1 } { 0 };       // −1 … 1 across the lanes
				var laneF = (baseF * (d * oUnison.clip(0, 100) * 0.01).midiratio).clip(1, 20000);
				var readF = laneF * syncR;
				var lvl   = ((readF / 27.5).log2).floor.clip(0, tLast);       // mip level → kr bufnum offset
				var tb    = tBase + lvl;
				var tbU   = tBase + (lvl + 1).min(tLast);
				var tbD   = tBase + (lvl - 1).max(0);
				var mph   = Phasor.ar(rt, laneF * sdur, 0, 1);                 // silent sync master at the lane pitch
				var wrap  = ((mph - Delay1.ar(mph)) < 0) * syncOn;             // its wrap resets the audible lane
				var ph    = Phasor.ar(rt + wrap, readF * sdur, 0, 1);
				var sph   = Phasor.ar(rt, laneF * 0.5 * sdur, 0, 1);           // sub: one octave down (retrig only)
				var saw   = Osc.ar(tb, 0, ph * 2pi);
				var pulse = saw - Osc.ar(tb, 0, ((ph + pw) % 1) * 2pi) - ((2 * pw) - 1);
				var sawO  = Osc.ar(tbU, 0, (((2 * ph) + pw - 0.5) % 1) * 2pi);
				var wave  = (pulse * (1 - xa)) + (saw * (xa - xb)) + (sawO * xb);
				var sub   = Osc.ar(tbD, 0, sph * 2pi) - Osc.ar(tbD, 0, ((sph + spw) % 1) * 2pi) - ((2 * spw) - 1);
				var lane  = (wave * (1 - subA)) + (sub * subA);
				Pan2.ar(lane, (oPan.clip(-1, 1) + (d * oWidth.clip(0, 1))).clip(-1, 1))
			};
			Mix(lanes) * (1 / n.sqrt)
		};
		var o1 = oscF.(v1, osc1Pitch, osc1Oct, osc1Shape, osc1Pw, osc1Sub, osc1SubPw, osc1Sync, osc1Retrig, osc1Unison, osc1Width, osc1Pan);
		var o2 = oscF.(v2, osc2Pitch, osc2Oct, osc2Shape, osc2Pw, osc2Sub, osc2SubPw, osc2Sync, osc2Retrig, osc2Unison, osc2Width, osc2Pan);
		// blend operators — Select order: MIX NEG WIPE AM SIGN MAX
		var m     = mix.clip(0, 1);
		var w     = m * m * (3 - (2 * m));                        // smoothstep wipe
		var sMix  = (o1 * (1 - m)) + (o2 * m);
		var sNeg  = (o1 * (1 - m)) - (o2 * m);
		var sWipe = (o1 * (1 - w)) + (o2 * w);
		var sAm   = o1 * ((1 - m) + (m * ((o2 * 0.5) + 0.5)));
		var sSign = (o1 * (1 - m)) + (o2.abs * o1.sign * m);
		var sMax  = (o1 * (1 - m)) + (o1.max(o2) * m);
		var mixed = Select.ar(blend.round(1).clip(0, 5), [sMix, sNeg, sWipe, sAm, sSign, sMax]);
		var nz    = noise.clip(0, 1);
		var nzMix = (mixed * (1 - nz)) + ({ WhiteNoise.ar }.dup * nz);
		// post-blend high-pass — Select order: off, 2-pole, 4-pole. The clip is
		// the shared 19.4…0.45·SR now (it was 20…8000): every value a save
		// carries passes unchanged, the extension is live.
		var hpF   = hpFreq.clip(19.4, SampleRate.ir * 0.45);
		var hpQ   = 1 - (hpRes.clip(0, 1) * 0.95);
		var hp2   = RHPF.ar(nzMix, hpF, hpQ);
		var hp4   = RHPF.ar(hp2, hpF, hpQ);
		var hpOut = Select.ar(hpMode.round(1).clip(0, 2), [nzMix, hp2, hp4]);
		var drv   = hpOut * drive.clip(-24, 24).dbamp;
		// feedback of the filter output into the pre-filter sum (LocalOut below).
		// polysynth-only, outside the §flt union: a SynthDef has ONE audio-rate
		// LocalIn, and whether `fb` joins Polymer is FILTER.md §6 Q13 (Comb no
		// longer needs the pair there; Ripple's interim form may).
		var pre   = drv + (Sanitize.ar(LocalIn.ar(2)) * fb.clip(0, 1));
		// §flt the cutoff BUS — this unit's own law, kept: factors in Hz, cut ×
		// (freqG / 261.63)^keytrack (the GLIDED freq BEFORE `pitch`, as always; the
		// clip widened 1 → 2 is a superset) × 2^(FEG octaves). egAmt is in
		// SEMITONES now (Bitwig's unit, shared with polymerU): st / 12 = octaves,
		// so at egAmt_st = 72 · egAmt_old this is the old egAmt_old × 6 × feg — the
		// store rescales a save by exactly that factor. The filter FM and the
		// 20…20000 clip are inside ~f2FltSlot.
		var fegD  = egAmt.clip(-120, 120) / 12 * feg;
		var cutK  = cut.clip(20, 20000) * ((freqG / 261.63) ** keytrack.clip(0, 2)) * (2 ** fegD);
		var flt   = fltSlot.(fltM, pre, cutK, 20, 20000, filtFm, res, fltMode, filtOn, shaper, shaperMode, false,
			fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain);
		var filt  = flt[\filt];
		var post  = flt[\post];
		var outLv = aeg * velC * gain.clip(-24, 24).dbamp * amp;
		var sig   = Balance2.ar(post[0], post[1], pan.clip(-1, 1), outLv);
		LocalOut.ar((filt * 0.5).tanh);   // bounded loop: fb × resonance cannot run away
		// the kr copy of the envelope: a reply must not carry an ar wire (§5 Q9)
		SendReply.kr(Impulse.kr(30) * (telId > 0) * ((aegK > 0.001) + (g > 0)).min(1), '/f2_chan', [aegK], telId);
		Out.ar(out, Sanitize.ar(LeakDC.ar(sig)));
	});
	bytes = def.asBytes.size;
	("[f2 poly] % (v1 % v2 % filt % env %): % bytes".format(def.name, v1, v2, fltM, envM, bytes)).postln;
	if (bytes > 16383) {
		("⚠ [f2 poly] % is % bytes > 16383 — sclang writes the def file and /d_load's it (local server)"
			.format(def.name, bytes)).postln;
	};
	def
};
// the base def (every menu at its default) — the SynthDesc the context export
// and \f2voice read; variants are built on demand by ~f2UnitDef / ~f2UnitEnsure
~f2UnitGen[\polysynthU].value((), \polysynthU).add;

// ── §smp samplerU (docs/design/SAMPLER.md) ────────────────────────────────
// STAGES 1–7 (§7.1–§7.7): all five play modes — Repitch, Cycles, Textures,
// Spectral and Fragments — Single AND Sliced, both roots. What is built here is
// the unit contract (§1 — 92 live controls + freq, the SAME list in every
// variant: the sampler's own plus the §flt block's core and the §env union),
// the shared phase engine (§2), the five engines, and the slice branch: the
// read window comes out of the slice TABLE instead of the play markers and
// `slicePlay` chooses what happens at its end. Only §7.8 is left — the resample
// stage that would give Spectral its own pitch, which decision 2 defers.
// Textures, Fragments and Cycles SHARE the §1.5 grain group, and they share it
// ONCE: Grain Size and the size unit are one pair of controls read by three
// branches ([RN]: «Grain Size and Motion are shared with Fragments so switching
// between the two modes preserves settings» — and Cycles lifts its next
// waveform every Grain Size, of which the Crossfade Two Voices time is the same
// number, §1.4), Motion, Grain Envelope and Repeats are read by the two clouds.
// The `grains` cap is a build constant of both of those, because GrainBuf's
// maxGrains is an instantiation argument.
//
// Structural opts → BUILD CONSTANTS (§1.0), never live controls, because they
// rebuild the graph: MODE (`play`), SLICED (`sl`), the envelope MODEL (`env`,
// §env — SHOT is the one value the rest of the graph reads, §2.10 there), the
// filter MODEL (`filt`, §flt), FROZEN (`freeze`, normalised off under Shot),
// ROOTAN (`rootMode`), NGRAIN (`grains`) and NFFT with its overlap (`qual`) —
// the last two for the same reason, that GrainBuf's maxGrains and an FFT's size
// are instantiation arguments and nothing can move them per block.
// `sample` and the five slicing parameters are RESOURCE opts
// (~f2UnitOptsRes): they change no graph, \f2voice resolves them to `buf` and
// `sliceBuf` at spawn (§6) and they never enter the variant name.
//
// ONE PHASE FOR EVERYTHING (§2). `raw` is a single signed accumulator anchored
// at every cell onset; `reverse` is its sign AND the end it starts from,
// `speed` is a positive multiplier (decision 1), the offsets move the window
// and the loop region, the loop mode folds it, `loopOff` releases the fold at
// the note off and the crossfade duplicates the reader. Repitch reads that head
// with a BufRd, Textures and Fragments spray a grain cloud around it, and Cycles
// lifts a waveform out of it and plays THAT at the note's pitch — there is no
// second transport anywhere in the unit.
~f2UnitOpts[\samplerU] = (
	// graph opts — this stage advertises only what it builds (§7 adds the rest);
	// `env` and `filt` advertise their whole shared lists and fall back to this
	// unit's default with one warning (~f2EnvResolve / ~f2FltResolve)
	play:     (values: #['repitch', 'cycles', 'textures', 'spectral', 'fragments'], def: 'repitch', label: "play mode"),
	sl:       (values: #['single', 'sliced'],    def: 'single',  label: "single / sliced"),
	// §env the envelope model — the union's seven, the sampler's `gated` renamed
	// `ahdsr` (ENVELOPE.md §4.2): the def MUST stay `ahdsr` and the front's
	// SAMPLER_OPTS.env.def the same string, or a keyless save stops resolving
	// to the base def `samplerU`. `gated` is still accepted (~f2EnvResolve,
	// ~f2UnitVariantName) and lands on that same base graph.
	env:      (values: ~f2EnvModels, def: 'ahdsr', label: "envelope"),
	// §flt the filter model — the same eleven as the synths', def `poly`: the
	// cascade + Bell this unit always had, index for index (FILTER.md §5)
	filt:     (values: ~f2FltModels, def: 'poly', label: "filter"),
	freeze:   (values: #['off', 'on'],           def: 'off',     label: "freeze"),
	rootMode: (values: #['manual','analyzed'],   def: 'manual',  label: "root"),
	grains:   (values: #['16', '32', '64', '128', '256'], def: '64', label: "max grains"),
	// §1.0 Spectral Quality / Cost — the FFT size and overlap behind [RN]'s four
	// names. Structural for the same reason `grains` is: NFFT is a LocalBuf size
	// and the hop a window argument, instantiation arguments on both sides of
	// the mode, so neither can be a live control. Read by `play: spectral`
	// alone; every other mode builds the same graph at any value of it.
	qual:     (values: #['low', 'medium', 'high', 'ultra'], def: 'medium', label: "quality"),
	// resource opts: no variant, resolved to BUFFERS at spawn (§3, §6).
	// `res: true` = not part of the variant name. `kind: \sample` = the value
	// list is not static — the front fills it from ctx.sampleNames. `kind: \num`
	// = a NUMERIC opt: still structural, rendered as a knob or a spinner and
	// committed ON POINTER RELEASE (debounced 150 ms), because every commit
	// re-runs an analysis (§6). The stored value is a string, as for every opt.
	sample:   (values: #[], def: '', label: "sample", kind: \sample, res: true),
	slicing:  (values: #['div', 'beats', 'onsets', 'pitch', 'manual'], def: 'div',
		label: "slicing", res: true),
	slices:   (kind: \num, min: 1, max: 64, step: 1, def: '8', label: "pieces", res: true),
	beatLen:  (values: #['1/1', '1/2', '1/4', '1/8', '1/16', '1/32',
		'1/4t', '1/8t', '1/16t', '1/32t', '1/4d', '1/8d', '1/16d'],
		def: '1/16', label: "beat", res: true),
	onsetSens: (kind: \num, min: 0, max: 100, step: 1, unit: "%", def: '100',
		label: "onset sens", res: true),
	pitchSens: (kind: \num, min: 0, max: 100, step: 1, unit: "%", def: '70',
		label: "pitch sens", res: true),
	bpm:      (values: #['auto', 'manual'], def: 'auto', label: "file bpm", res: true),
	// `kind: \cuts` = an opaque LIST opt: the card's manual boundaries, encoded by
	// ~f2SmpCuts above (ten-thousandths of the file joined by "_"). It is neither a
	// menu nor a number, so a front that does not know the kind renders nothing for
	// it rather than a broken menu; the empty default drops the key out of the card.
	cuts:     (values: #[], def: '', label: "manual cuts", kind: \cuts, res: true,
		max: (~f2SmpCutMax ? 63)),
	// §curve `kind: \curve` = an opaque encoded point list — the drawn shape of
	// `env: segments` (ENVELOPE.md §2.9). ONE menu on three cards means one
	// RESOURCE on three cards: the opt is declared here in the same words
	// polymerU declares it, because a model the card offers and the engine cannot
	// feed is the silent fallback the §env union exists to end. No value list and
	// no range, so a front that does not know the kind renders nothing for it
	// rather than a broken menu; `max` is how many breakpoints the value may
	// carry. It changes no graph, so it never enters the variant name.
	curve: (values: #[], def: '', label: "curve", kind: \curve, res: true,
		max: (~f2CurveMax ? 64))
);
~f2UnitSpecs[\samplerU] = {
	var sp = ();
	// §1.1 sample and window
	sp[\keytrack]   = (min: 0, max: 2, warp: \lin, label: "note");
	sp[\root]       = (min: 0, max: 127, warp: \lin, unit: "midi", label: "root");
	sp[\rootFine]   = (min: -100, max: 100, warp: \lin, unit: "ct", label: "fine");
	sp[\smpGain]    = (min: -12, max: 12, warp: \lin, unit: "dB", label: "gain");
	sp[\reverse]    = (min: 0, max: 1, warp: \lin, label: "dir", sel: #["—", "R"]);
	sp[\playStart]  = (min: 0, max: 1, warp: \lin, label: "start");
	sp[\playEnd]    = (min: 0, max: 1, warp: \lin, label: "end");
	sp[\loopMode]   = (min: 0, max: 2, warp: \lin, label: "loop", sel: #["OFF", "LOOP", "PP"]);
	sp[\loopStart]  = (min: 0, max: 1, warp: \lin, label: "loop start");
	sp[\loopEnd]    = (min: 0, max: 1, warp: \lin, label: "loop end");
	sp[\loopXfade]  = (min: 0, max: 1, warp: \lin, label: "xfade");
	sp[\loopOff]    = (min: 0, max: 2, warp: \lin, label: "at off", sel: #["STAY", "FREE", "EXIT"]);
	// §1.2 head
	sp[\slice]      = (min: 0, max: 63, warp: \lin, label: "slice");
	sp[\pitch]      = (min: -36, max: 36, warp: \lin, unit: "st", label: "pitch");
	sp[\glide]      = (min: 0, max: 2, warp: \lin, unit: "s", label: "glide");
	sp[\pos]        = (min: 0, max: 1, warp: \lin, label: "pos");
	sp[\offLoop]    = (min: -1, max: 1, warp: \lin, label: "loop");
	sp[\offLen]     = (min: 0, max: 1, warp: \lin, label: "len");
	sp[\speed]      = (min: 0.01, max: 4, warp: \exp, unit: "x", label: "speed");
	sp[\useBpm]     = (min: 0, max: 1, warp: \lin, label: "bpm", sel: #["—", "BPM"]);
	sp[\smpBpm]     = (min: 20, max: 300, warp: \lin, unit: "bpm", label: "file bpm");
	// §1.3 repitch
	sp[\character]  = (min: 0, max: 2, warp: \lin, label: "character", sel: #["CLEAN", "ANLG", "DIGI"]);
	sp[\dist]       = (min: 0, max: 1, warp: \lin, label: "dist");
	sp[\color]      = (min: -1, max: 1, warp: \lin, label: "color");
	sp[\varSR]      = (min: 0, max: 1, warp: \lin, label: "var SR", sel: #["—", "VSR"]);
	sp[\imgFilt]    = (min: 0, max: 1, warp: \lin, label: "imaging", sel: #["—", "IMG"]);
	// §1.4 cycles
	sp[\formant]    = (min: -24, max: 24, warp: \lin, unit: "st", label: "formant");
	sp[\cycChar]    = (min: 0, max: 2, warp: \lin, label: "character", sel: #["PULSE", "PART", "PHASE"]);
	sp[\width]      = (min: -1, max: 1, warp: \lin, label: "width");
	sp[\split]      = (min: -1, max: 1, warp: \lin, label: "split");
	sp[\fund]       = (min: 0, max: 1, warp: \lin, label: "fund");
	sp[\cycMod]     = (min: 0, max: 1, warp: \lin, label: "mod");
	sp[\cycHarm]    = (min: 0, max: 7, warp: \lin, label: "harm", sel: #["1", "2", "3", "4", "5", "6", "7", "8"]);
	sp[\xfade2]     = (min: 0, max: 1, warp: \lin, label: "2 voices", sel: #["—", "X2"]);
	// §1.5 grain / window group — shared by Textures, Fragments and Cycles
	sp[\grainSize]  = (min: 0.002, max: 2, warp: \exp, unit: "s", label: "size");
	sp[\sizeUnit]   = (min: 0, max: 1, warp: \lin, label: "unit", sel: #["SEC", "BEAT"]);
	sp[\motion]     = (min: 0, max: 8, warp: \lin, label: "motion");
	sp[\grainEnv]   = (min: 0, max: 1, warp: \lin, label: "env");
	sp[\repeats]    = (min: 1, max: 16, warp: \lin, label: "repeats");
	// §1.6 fragments
	sp[\coupled]    = (min: 0, max: 1, warp: \lin, label: "rate mode", sel: #["DENS", "RATE"]);
	sp[\density]    = (min: 0.1, max: 100, warp: \exp, label: "density");
	sp[\grainRate]  = (min: 0.1, max: 200, warp: \exp, unit: "Hz", label: "rate");
	sp[\repeatInit] = (min: 0, max: 1, warp: \lin, label: "init", sel: #["—", "INIT"]);
	sp[\grainDir]   = (min: 0, max: 3, warp: \lin, label: "grain dir", sel: #["SMPL", "HEAD", "RAND", "ALT"]);
	sp[\latchRate]  = (min: 0, max: 1, warp: \lin, label: "latch", sel: #["—", "LATCH"]);
	sp[\grainSurvive] = (min: 0, max: 1, warp: \lin, label: "survive", sel: #["—", "SURV"]);
	// §1.7 spectral
	sp[\spChar]     = (min: 0, max: 1, warp: \lin, label: "character", sel: #["PURE", "REHARM"]);
	sp[\preserveOnsets] = (min: 0, max: 1, warp: \lin, label: "onsets", sel: #["—", "ON"]);
	sp[\formantOn]  = (min: 0, max: 1, warp: \lin, label: "formant", sel: #["—", "ON"]);
	sp[\formantShift] = (min: -24, max: 24, warp: \lin, unit: "st", label: "shift");
	sp[\formantAmt] = (min: 0, max: 1, warp: \lin, label: "amount");
	sp[\relFormant] = (min: 0, max: 1, warp: \lin, label: "relative", sel: #["ABS", "REL"]);
	sp[\harmBend]   = (min: -24, max: 24, warp: \lin, unit: "st", label: "bend");
	sp[\harmQuant]  = (min: 0, max: 2, warp: \lin, label: "quantize", sel: #["OFF", "OCT", "KEY"]);
	sp[\harmQuantAmt] = (min: 0, max: 1, warp: \lin, label: "amount");
	sp[\key]        = (min: 0, max: 11, warp: \lin, label: "key",
		sel: #["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]);
	sp[\scale]      = (min: 0, max: 7, warp: \lin, label: "scale",
		sel: #["MAJ", "MIN", "DOR", "PHR", "LYD", "MIX", "LOC", "PENT"]);
	sp[\phaseDisp]  = (min: 0, max: 1, warp: \lin, label: "phase");
	sp[\livePerf]   = (min: 0, max: 1, warp: \lin, label: "live", sel: #["—", "LIVE"]);
	// §1.8 sliced (stage 3)
	sp[\sliceStart] = (min: 0, max: 1, warp: \lin, label: "slice start");
	sp[\sliceEnd]   = (min: 0, max: 1, warp: \lin, label: "slice end");
	sp[\slicePlay]  = (min: 0, max: 3, warp: \lin, label: "playback", sel: #["SLEND", "SMPEND", "LOOP", "PP"]);
	// §1.9 filter — the §flt block's CORE (~f2FltCore, FILTER.md §5.2): the
	// model, the switch, the bus knobs and the per-model cells out of the shared
	// table, so the three schemas cannot drift; `cut` widened 20…20000 →
	// 19.4…33500 with the graph clip kept (value untouched). filtType is gone —
	// `filtOn` + `fltMode` now, 0…7 index for index and OFF = filtOn 0. Not the
	// FEG, filtFm, the shaper pair or the high-pass: Bitwig's Sampler has none.
	// The keytrack ROLE lives under this unit's own key `filtKey` (~f2FltKeyMap):
	// `keytrack` is the sample's pitch keytrack here.
	topEnvironment[\f2FltCore].do { |k|
		var kk = (topEnvironment[\f2FltKeyMap][\samplerU] ? ())[k] ? k;
		sp[kk] = topEnvironment[\f2FltSpecs][k];
	};
	// §1.10 amp envelope — the §env union's table (~f2EnvSpecs): atk / hold /
	// dec widened 4 → 8 s, value untouched; envModel / envLoop new — and output
	sp.putAll(topEnvironment[\f2EnvSpecs]);
	sp[\vel]        = (min: 0, max: 1, warp: \lin, label: "vel");
	sp[\gain]       = (min: -24, max: 24, warp: \lin, unit: "dB", label: "gain");
	sp[\pan]        = (min: -1, max: 1, warp: \lin, label: "pan");
	sp[\amp]        = (min: 0, max: 1, warp: \lin, label: "out");
	// the note pitch (a group broadcast — no knob; exported for completeness)
	sp[\freq]       = (min: 20, max: 20000, warp: \exp, unit: "Hz", label: "freq");
	sp
}.value;

// ── §1.7 SPECTRAL, the arm (SAMPLER.md §1.7, §1.0 `qual`, §2, §6) ─────────
// A phase vocoder over PRE-ANALYSED frames. The file is analysed once per
// (sample, qual) into `fftBuf` (§6) and the voice resynthesises the frame the
// HEAD is standing on, so the stretch is the head's rate and the pitch is
// whatever the stored frame holds — the file's own. PITCH-LOCKED in v1
// (decision 2): `pitch`, `root` / `rootMode` and `keytrack` are not read here
// at all, and `rateH` never reaches the spectrum — it only moves the head.
//
// WHY FRAMES AND NOT A LIVE FFT of a varispeed read. The other construction —
// read at `rateH`, FFT that, undo the transposition with PV_BinShift(1/rateH)
// — cannot hold the pitch: PV_BinShift multiplies the INTEGER bin index and
// carries the sub-bin offset through unchanged, so a partial at bin i+f lands
// at i·r+f instead of (i+f)·r. Measured on a 220 Hz tone at 2048 bins, that
// came back at 203.7 Hz at speed 0.5 and 252.6 Hz at speed 2.0 — 0.7 and 1.4
// bins out, over a semitone, and a different error per harmonic. PV_BufRd
// moves no bin at all, and it takes a POSITION rather than owning a rate, which
// is also why it stands in for §2's sketched PV_PlayBuf: §2's rule is that
// there is no second transport in the unit, and PV_PlayBuf advances itself.
// The same tone through this arm measures 220.0 Hz at every speed.
//
// `livePerf` is NOT an argument. [RN]'s Live Performance Mode trades note-on
// cost against one window of latency; with the analysis done offline there is
// neither — the PV chain runs from the node's birth and the overlap-add never
// restarts when the head jumps — so both positions of the switch would produce
// the same samples and inventing a difference would be worse than reading
// nothing. It becomes real if §7.8's resample stage lands.
//
//   ~f2SmpSpectral.(nfft, hop, wtype, gain, smear, fftNull,
//       head, rateH, dur, buf, fftBuf, onsetBuf, pitchBuf, freqG, rootHz,
//       spChar, preserveOnsets, formantOn, formantShift, formantAmt, relFormant,
//       harmBend, harmQuant, harmQuantAmt, key, scale, phaseDisp)
//     → (sig: <2 ar>, span: <kr>)
//
// The first six are BUILD constants of the variant (~f2SmpFftOf of the `qual`
// opt, plus the null-analysis bufnum); everything from `head` on is a signal the
// generator already holds under exactly these names.
~f2SmpSpectral = { |nfft, hop, wtype, gain, smear, fftNull,
	head, rateH, dur, buf, fftBuf, onsetBuf, pitchBuf, freqG, rootHz,
	spChar, preserveOnsets, formantOn, formantShift, formantAmt, relFormant,
	harmBend, harmQuant, harmQuantAmt, key, scale, phaseDisp|

	var sr    = SampleRate.ir;
	// §6 `fftBuf` is -1 until the record pass has landed, and the bufnum handed
	// to the player is NEVER that -1: PV_BufRd on a bufnum that is not an
	// analysis takes the server down (see ~f2SmpFftNull). It reads the variant's
	// null analysis instead and the output is gated to digital silence, which is
	// what §6 asks a pending note to be.
	var aOk   = fftBuf >= 0;
	var aBuf  = Select.kr(aOk, [fftNull, fftBuf]);
	// the analysis is padded up to a whole number of windows (calcPVRecSize), so
	// 1.0 of the BUFFER is past the end of the FILE. `aLen` is the padded length
	// in server samples and `ptMax` is where the file ends inside it; the head —
	// which is 0…1 of the file — is scaled into that.
	var aLen  = ((BufFrames.kr(aBuf) - 3) * hop).max(1);
	var ptMax = ((dur * sr) / aLen).clip(0.001, 1);

	// ── Preserve Onsets (§1.7). [RN]: «the playback speed changes through onsets
	// so they keep their original character». Inside an onset window the read
	// runs at NATURAL speed whatever the head is doing, so the attack is
	// resynthesised at the rate it was analysed at instead of being spread over
	// the stretch; outside it the debt that ran up bleeds back to the head.
	// It is the DEBT that is carried and not a blend of two positions: blending
	// `head` towards a natural-speed run and back makes the read RETREAT in the
	// second half of the window — the weight's own derivative is a negative rate
	// bigger than the head's — and measured that way the transients came out
	// SOFTER with the switch on than off. A leaky integral of the excess rate
	// only ever adds the difference, then bleeds it off over `onTau`.
	var oOk   = onsetBuf >= 0;
	var oBuf  = Select.kr(oOk, [buf, onsetBuf]);
	var oHdr  = topEnvironment[\f2SmpOnsetHdr].value;
	var oN    = (topEnvironment[\f2SmpOnsetProx] ? 1024);
	var onTau = (topEnvironment[\f2SmpOnsetTau] ? 0.25);
	var onP   = (BufRd.ar(1, oBuf, (head.clip(0, 1) * (oN - 1)) + oHdr, 0, 1)
		* K2A.ar(oOk * preserveOnsets.round(1).clip(0, 1))).clip(0, 1);
	// natural speed in the head's OWN direction (`reverse` still decides which
	// way a transient is played through) minus the head's: positions per second
	// of excess, and exactly zero the moment the window closes
	var onExc = onP * K2A.ar((rateH.sign - rateH) / dur);
	var onOff = Integrator.ar(onExc * SampleDur.ir, (-1 / (onTau * sr)).exp);
	var ptF   = (head + onOff).clip(0, 1) * ptMax;

	// how fast the head is REALLY travelling, as a multiple of natural speed.
	// `rateH` is not that number: under `freeze` the advance branch is not built
	// at all and the head stands still while `rateH` still says whatever `speed`
	// says, and at a loop seam the head jumps. Measuring the head is one
	// subtraction and it is right in both cases.
	var hStep = A2K.kr((head - Delay1.ar(head)).abs) * sr * dur;
	// a head slower than the tape hands the SAME frame to two overlapping
	// windows, and the second copy carries the first's phase a hop late: a comb
	// at the frame rate. Dispersion does not touch it — PV_Diffuser's random
	// phases are per BIN and held ACROSS frames, so two copies of one frame stay
	// exactly as correlated as they were. Moving the read by up to half a hop
	// per frame makes them different frames again: measured at speed 0.5 with
	// the dispersion knob at zero, the frame-rate ripple fell 3.05 → 2.43 dB.
	// Scaled by how far under natural speed the head is, so at speed 1 the
	// dither is exactly zero and the tape stays the tape.
	var slow  = (1 - hStep).clip(0, 1);
	var hopPt = (nfft * hop) / aLen;
	// …and NOT through a transient: the dither is exactly what Preserve Onsets
	// exists to prevent, so inside an onset window it is faded out by the same
	// `onP` that drives the natural-speed run.
	var dith  = LFNoise0.ar(sr / (nfft * hop)) * 0.5 * slow * hopPt * (1 - onP);

	// ── the vocoder. ONE read: the frame the head stands on, resynthesised at
	// the synthesis hop. No transposition anywhere in it — that is the whole of
	// decision 2, and it is by construction rather than by cancellation.
	var ch0   = topEnvironment[\f2PvBufRd].(LocalBuf(nfft, 1), aBuf, (ptF + dith).clip(0, ptMax));

	// ── Phase Dispersion (§1.7, default 66.7 %). Frames that were not recorded
	// a hop apart do not overlap-add with the phase they were analysed with, and
	// the error shows as a comb at the frame rate; randomising each bin's phase
	// makes the overlap sum in POWER instead of cancelling. Scaled by the
	// STRETCH as well as by the knob (§2), off the head's own rate for the same
	// reason the dither is: at speed 1 the stored phases are exactly right — the
	// read IS the tape — and dispersing there would smear a passage that had
	// nothing wrong with it. One octave of stretch either way, or a stopped
	// head, reaches the knob's full value.
	var octs  = (hStep.max(0.03125)).log2.abs.clip(0, 1);
	var dAmt  = (phaseDisp.clip(0, 1) * octs).clip(0, 1);
	// PV_Diffuser re-rolls only while its trigger is HELD above zero — an
	// impulse train at the frame rate is sampled at the frame boundary and
	// missed outright (measured: the output was identical to no diffuser at
	// all) — so the trigger is a constant and the amount is the crossfade.
	var chD   = topEnvironment[\f2PvXFade].(ch0, PV_Diffuser(PV_Copy(ch0, LocalBuf(nfft, 1)), 1), dAmt);
	// PV_XFade is a LINEAR mix and the two chains are uncorrelated by
	// construction, so half of each is half the power: measured 3.2 dB down at
	// the middle of the travel, which would make [RN]'s 66.7 % default the
	// quietest setting of a control nobody expects to change the level. The
	// equal-power compensation puts it back and is exactly 1 at both ends.
	var dComp = (((dAmt * dAmt) + ((1 - dAmt) * (1 - dAmt))).max(0.5)).sqrt.reciprocal;

	// ── Formant Processing (§1.7). The envelope is estimated by smearing the
	// magnitudes across `smear` bins and moved ON ITS OWN; what the chain is
	// multiplied by is the CORRECTION envB/envA, so no partial moves —
	// PV_MagMul keeps the first chain's phases and bin positions, which is what
	// «formant shift» has to mean next to a pitch lock. PV_BinShift is exact
	// enough on an envelope (a box average of 2·smear+1 bins has no sub-bin
	// detail to lose) and it is the same UGen that cannot carry a partial.
	// Dividing the two ENVELOPES rather than the signal by its envelope is the
	// difference between a well-conditioned quotient and a wild one: envA and
	// envB are the same smooth curve one bin shift apart, where a whitened
	// spectrum is a peaky thing over a flat one — measured on a decaying
	// pink-noise transient, the whitening form peaked at 2409.
	var fSt   = formantShift.clip(-24, 24)
		// RELATIVE (§1.7 `relFormant`): «the shift takes pitch changes into
		// account». Nothing transposes in v1, but the note is still a note — REL
		// makes the formant follow the interval the cell plays above the sample's
		// root, which is the pitch change the card can see.
		+ (relFormant.round(1).clip(0, 1) * (freqG / rootHz).log2 * 12);
	var fAmt  = (formantAmt.clip(0, 1) * formantOn.round(1).clip(0, 1)).clip(0, 1);
	var envA  = PV_MagSmear(PV_Copy(chD, LocalBuf(nfft, 1)), smear);
	var envB  = PV_BinShift(PV_Copy(envA, LocalBuf(nfft, 1)), fSt.midiratio, 0, 1);
	// `zeroed` is the divisor SUBSTITUTED where the denominator is zero, not the
	// quotient. At 0 every silent bin divides by zero and the whole voice is NaN
	// a tenth of a second in — measured, with Sanitize then holding the output at
	// digital silence for the rest of the note. 0.01 is some 70 dB under a peak
	// bin at these window sizes and measured an exact round trip, where 0.0001
	// left 0.3 of broadband junk on a signal of 0.47.
	var corr  = PV_MagDiv(envB, envA, 0.01);
	var wet   = PV_MagMul(PV_Copy(chD, LocalBuf(nfft, 1)), corr);
	// [RN]: Amount is «a crossfade-type control (dry ↔ shifted)», and PV_XFade is
	// exactly linear with exact endpoints (measured), so Amount 0 — and the
	// formant switch OFF — is the chain that came in, bin for bin, and not a
	// round trip that happens to land close.
	var chF   = topEnvironment[\f2PvXFade].(chD, wet, fAmt);

	// ── REHARM (§1.7 `spChar`): Harmonic Bend and the quantization of it. [RN]:
	// the bend «shifts the harmonics and leaves the fundamental in place». A bin
	// stretch cannot leave anything exactly in place — its anchor is only good to
	// the nearest bin, and one bin at 220 Hz is 23 Hz, nearly two semitones — so
	// the fundamental is CARRIED rather than anchored: the chain is split at
	// 1.5 × the fundamental, the low side passes untouched and only what is above
	// it is stretched. Measured, the fundamental holds inside 0.1 cents through
	// every bend, quantization and amount.
	var pOk   = pitchBuf >= 0;
	var pBuf  = Select.kr(pOk, [buf, pitchBuf]);
	// the file's OWN pitch at the head, off the §6 curve — one BufRd instead of a
	// tracker in the voice
	var f0Hz  = (BufRd.kr(1, pBuf, A2K.kr(head).clip(0, 1) * (BufFrames.kr(pBuf) - 1).max(1), 0, 1)
		* pOk).max(20);
	var f0Bin = (f0Hz * nfft / sr);
	var stB   = harmBend.clip(-24, 24);
	// OCT snaps the bend to the nearest octave; KEY snaps the lowest partial the
	// bend MOVES — the second — onto the nearest step of the card's own key and
	// scale (there is no global key in F2, §1.7).
	var stO   = (stB / 12).round(1) * 12;
	var keyPc = key.round(1).clip(0, 11);
	var midi2 = ((2 * f0Hz * stB.midiratio).max(20)).cpsmidi;
	var kD    = midi2 - keyPc;
	var kOct  = (kD / 12).floor;
	var kPc   = (kD - (12 * kOct)).round(1).clip(0, 11);
	var kQ    = Select.kr((scale.round(1).clip(0, 7) * 12) + kPc, topEnvironment[\f2SmpScaleTab]);
	var stK   = (((keyPc + (12 * kOct) + kQ).midicps / (2 * f0Hz)).max(0.01)).log2 * 12;
	var stQ   = Select.kr(harmQuant.round(1).clip(0, 2), [stB, stO, stK]);
	// Quantize Amount attenuates the quantization ([RN]) — taken on the BEND
	// itself, not as a second bent chain to crossfade with: the two chains would
	// differ only in their stretch ratio, so REHARM costs one bin stretch instead
	// of two plus a copy and a fade, and the glide from the free bend to the
	// snapped one is the same.
	var stM   = stB + ((stQ - stB) * harmQuantAmt.clip(0, 1));
	var spC   = spChar.round(1).clip(0, 1);
	var bendR = Select.kr(spC, [1, stM.midiratio]);
	// the split point as PV_BrickWall's wipe. The two signs are NOT symmetric: a
	// positive wipe clears from the bottom UP TO wipe·nbins, a negative one from
	// the top DOWN TO (1−|wipe|)·nbins — so the low half of a split at `wipe` is
	// −(1 − wipe), and the obvious `wipe.neg` spelling passes the WHOLE spectrum
	// through and adds it to the bent copy (measured: the second partial stayed
	// put at full level and the mode was twice as loud).
	var wipe  = ((f0Bin * 1.5) / (nfft / 2)).clip(0.002, 0.98);
	var lowC  = PV_BrickWall(PV_Copy(chF, LocalBuf(nfft, 1)), (1 - wipe).neg);
	var hiC   = PV_BinShift(PV_BrickWall(PV_Copy(chF, LocalBuf(nfft, 1)), wipe), bendR, 0, 1);
	var chB   = PV_Add(lowC, hiC);
	// PURE has to be the chain that came IN, not a split and re-added copy of it,
	// and the choice is made in the SPECTRUM: a Select between two IFFTs would
	// build the most expensive UGen in the mode twice and run both. PV_XFade at
	// fade 0 is its first buffer exactly (measured), which is `chF`.
	var chX   = topEnvironment[\f2PvXFade].(chF, chB, spC);
	var sig   = IFFT(chX, wtype) * gain * dComp;
	// §5 what the card draws around a spectral head: the analysis window, in the
	// same 0…1 of the file the head is in
	var span  = ((nfft / (dur * sr)).clip(0, 1));
	(sig: (sig * aOk) ! 2, span: span)
};

// Generator: opts (play: 'textures', grains: '128') → SynthDef `name`
// (~f2UnitVariantName: samplerU__grains_128__play_textures). Every variant
// declares the same 107 controls (§1) — 92 user-facing + freq, the six contract
// args (out gate t_trig i_free tel_bus telId) and the eight engine args
// (vi ci tempo buf sliceBuf onsetBuf pitchBuf fftBuf, set by \f2voice, never
// knobs). The def size is logged; beyond 16383 bytes sclang writes the def file
// and /d_load's it instead of /d_recv (local server).
~f2UnitGen[\samplerU] = { |opts, name|
	var oget   = { |k, d| ((opts !? { |o| o[k] }) ? d).asSymbol };
	var warn   = topEnvironment[\f2UnitWarnOnce];
	var mode   = oget.(\play, 'repitch');
	var sliced = oget.(\sl, 'single') == 'sliced';
	// §env the envelope model through the shared resolver (`gated` → `ahdsr`, a
	// value without an arm → `ahdsr` with one warning); SHOT stays the one
	// structural predicate of this graph (ENVELOPE.md §2.10)
	var envM   = topEnvironment[\f2EnvResolve].value(\samplerU, opts, name);
	var shot   = envM == 'shot';
	var aegF   = topEnvironment[\f2Aeg];
	// §flt the filter model through the shared resolver — all eleven build here
	// with the arms the synths get (FILTER.md §5); a value outside the list
	// falls back to `poly` (this unit's own) with one warning
	var fltM   = topEnvironment[\f2FltResolve].value(\samplerU, opts, name);
	var fltSlot = topEnvironment[\f2FltSlot];
	var rootAn = oget.(\rootMode, 'manual') == 'analyzed';
	// Shot has no frozen head: `freeze` is normalised away here AND in
	// ~f2UnitVariantName, so the two spellings never make a duplicate variant
	var frozen = (oget.(\freeze, 'off') == 'on') and: { shot.not };
	var nGrain = oget.(\grains, '64').asString.asInteger.clip(16, 256);
	// §1.0 `qual` → NFFT, hop, window type, the overlap gain and the envelope
	// smear: the FFT size is a LocalBuf size and the hop a window argument, so
	// both are instantiation arguments and the menu is structural like `grains`.
	// Read by the spectral branch alone — in every other variant the `if` below
	// folds at BUILD time and not one of these numbers reaches a UGen.
	var qual   = oget.(\qual, 'medium');
	var fftQ   = topEnvironment[\f2SmpFftOf].(qual);
	// §6 the analysis of silence this variant reads while the file's own is
	// still being recorded. A build constant, like ~f2SmpWins' base, because the
	// graph must never hand PV_BufRd a bufnum that is not an analysis.
	var fftNull = ((topEnvironment[\f2SmpFftNull] ? IdentityDictionary.new)[qual] ? -1);
	// §3 / §702 the spectral graph needs sc3-plugins AND that null analysis. With
	// either missing the mode is built as the Warp1 fallback of §2 — a
	// time-stretch with no spectrum to shape, so the whole §1.7 set is inert
	// there, which is what the reduced-capability warning says.
	var specPV = (topEnvironment[\f2SmpPV] ? false) and: { fftNull >= 0 };
	// §ptrs how many read pointers BESIDES the main head this variant reports on
	// '/f2_head' (§5). A voice does not read the file in one place: Repitch runs a
	// second reader across a loop seam, Cycles lifts its waveform with two lanes,
	// and a grain cloud has one pointer PER SOUNDING GRAIN — several at once, each
	// with its own position and its own direction. The card draws what is really
	// there, so the graph has to say. Six is what a cloud gets: enough to read as
	// a cloud on a card-wide plot, and six kr latches is nothing per voice.
	var nPtr;
	var wins   = topEnvironment[\f2SmpWins];
	var wBase  = ((wins !? { wins[\base] }) ? -1).asInteger;
	var wN     = ((wins !? { wins[\n] }) ? 16).asInteger;
	var def, bytes;
	// A value from a later stage must not build a silent or wrong graph: fall
	// back to the nearest built one and say so once (§7).
	if (#['repitch', 'cycles', 'textures', 'spectral', 'fragments'].includes(mode).not) {
		warn.value(("smp_play_" ++ mode).asSymbol,
			"⚠ [f2 smp] play: % is a later stage (SAMPLER.md §7) — % built as repitch".format(mode, name));
		mode = 'repitch';
	};
	// …and the one value that can be advertised and still not buildable: without
	// sc3-plugins there is no phase vocoder to build at all (§3, §6). The variant
	// keeps its NAME — a saved card must resolve to the def it asks for — and
	// gets the Warp1 stretch instead, said once.
	if ((mode == 'spectral') and: { specPV.not }) {
		warn.value(\smp_play_spectral_pv,
			"⚠ [f2 smp] play: spectral has no PV chain here (sc3-plugins %, null analysis %) — % is built on Warp1 and reads none of §1.7".format(
				topEnvironment[\f2SmpPV] ? false, fftNull, name));
	};
	// …and the pointer count follows the mode as BUILT, not as asked for
	nPtr = switch (mode,
		'repitch',   { 1 },
		'cycles',    { 2 },
		'textures',  { 6 },
		'fragments', { 6 },
		// §5 spectral has NO second pointer: the frame the vocoder plays IS the
		// head, so there is nothing to draw beside it that `pos` does not say
		'spectral',  { 0 },
		{ 0 });
	if (wBase < 0) { "⚠ [f2 smp] ~f2SmpWins is not allocated — grainEnv falls back to the built-in Hann".postln };
	def = SynthDef(name.asSymbol, { |out = 0, gate = 0, t_trig = 0, amp = 0.5, i_free = 2,
		tel_bus = 0, telId = 0, freq = 220, vel = 1,
		// engine args (§1): set by \f2voice, never knobs, never compiled into params.
		// `vi` is the voice index and `ci` the CARD index in the strip — together
		// they name the writer of a '/f2_head' packet, so two samplerU cards of one
		// preset (§8 decision 4) never draw each other's playheads (§5).
		vi = 0, ci = 0, tempo = 2, buf = 0, sliceBuf = -1, onsetBuf = -1, pitchBuf = -1, fftBuf = -1,
		// §curve the rendered drawing `env: segments` reads — the same class of arg
		// as the four above, resolved at spawn from the card's `curve` opt
		// (~f2CurveRes), never a knob, never compiled into params
		shapeBuf = -1,
		// §1.1 sample and window
		keytrack = 0, root = 60, rootFine = 0, smpGain = 0, reverse = 0,
		playStart = 0, playEnd = 1, loopMode = 0, loopStart = 0, loopEnd = 1, loopXfade = 0, loopOff = 0,
		// §1.2 head
		slice = 0, pitch = 0, glide = 0, pos = 0, offLoop = 0, offLen = 0,
		speed = 1, useBpm = 0, smpBpm = 120,
		// §1.3 repitch
		character = 0, dist = 0, color = 0, varSR = 1, imgFilt = 0,
		// §1.4 cycles
		formant = 0, cycChar = 0, width = 0, split = 0, fund = 0, cycMod = 0, cycHarm = 0, xfade2 = 0,
		// §1.5 grain / window group
		grainSize = 0.08, sizeUnit = 0, motion = 0, grainEnv = 0, repeats = 1,
		// §1.6 fragments
		coupled = 0, density = 10, grainRate = 12.5, repeatInit = 0, grainDir = 1,
		latchRate = 0, grainSurvive = 0,
		// §1.7 spectral
		spChar = 0, preserveOnsets = 0, formantOn = 0, formantShift = 0, formantAmt = 1, relFormant = 0,
		harmBend = 0, harmQuant = 0, harmQuantAmt = 1, key = 0, scale = 0, phaseDisp = 0.667, livePerf = 1,
		// §1.8 sliced (stage 3)
		sliceStart = 0, sliceEnd = 1, slicePlay = 0,
		// §1.9 filter — the §flt block's core (FILTER.md §5.2). filtOn 0 is this
		// unit's own default (Bitwig's Sampler filter is off), fltMode 1 = LP4
		// (what an old OFF save carries under it, §5.3); drive 0 dB and every
		// cell from resLimit on arrive at the block's defaults, exact no-ops on
		// `poly`; bellGain 6 is read at fltMode 7 only
		filtOn = 0, fltMode = 1, drive = 0, cut = 2000, res = 0, filtKey = 1, bellGain = 6,
		resLimit = 1, fltLin = 0, fltMode2 = 0, fltFbGain = 0, fltFbCut = 0.5, fltColor = 0, fltVowel = 0,
		// §1.10 amp envelope and output — the §env union: envModel 2 (Digital) is
		// this unit's own default, because its curve knobs were always read
		atk = 0.002, hold = 0.001, dec = 1.0, sus = 1, rel = 0.05,
		atkC = 0, decC = -4, relC = -4, envModel = 2, envLoop = 0, fadeIn = 0.001, fadeOut = 0.005,
		gain = 0, pan = 0|
		var g      = gate;
		var sdur   = SampleDur.ir;
		var frames = BufFrames.kr(buf).max(1);
		var dur    = BufDur.kr(buf).max(0.001);
		var velC   = vel.clip(0, 1);
		// ── rate (§2). ROOTAN reads rootHz off the PITCH CURVE at the head
		// instead of the two knobs ([RN] Analyzed Root Key), and compensates the
		// playback speed with it where the mode couples the two.
		//   pAt(x)  Hz at position x of the file — the curve is one buffer per
		//           FILE (~f2SmpPitchBufAt), Hz per frame, back-filled at its head
		//           so pAt(0) is the file's FIRST detected pitch, not its silence.
		//   pOk     the curve exists. It is resolved at SPAWN and can be -1 (the
		//           offline pass has not landed), so the fallback to the manual
		//           root is a live Select, not a build branch (§6).
		var pOk    = if (rootAn) { pitchBuf >= 0 } { 0 };
		var pBn    = if (rootAn) { Select.kr(pOk, [buf, pitchBuf]) } { buf };
		var pLast  = if (rootAn) { (BufFrames.kr(pBn) - 1).max(1) } { 1 };
		var pAt    = { |x| (BufRd.kr(1, pBn, x.clip(0, 1) * pLast, 0, 1) * pOk).max(20) };
		// §4 the same read at audio rate, for a grain that is sprayed AWAY from
		// the head: GrainBuf samples both `pos` and `rate` on the trigger, so the
		// two land on the same grain.
		var pAtA   = { |x| (BufRd.ar(1, pBn, x.clip(0, 1) * pLast, 0, 1) * pOk).max(20) };
		// §4 a grain's own rate correction: the voice rate was built from the
		// pitch AT THE HEAD, and a grain reading somewhere else has to divide by
		// the pitch THERE instead. `keytrack` is the exponent for the same reason
		// it is one in `keyR` — at keytrack 0 the material plays at its natural
		// pitch, and flattening the file's own pitch drift would be the opposite
		// of that. 1 (a plain number, nothing in the graph) without the curve.
		var pGrain = { |gp| if (rootAn) {
			Select.ar(K2A.ar(pOk), [DC.ar(1), (rootHz / pAtA.(gp)) ** keytrack.clip(0, 2)])
		} { 1 } };
		var rootKn = ((root.clip(0, 127) + (rootFine.clip(-100, 100) * 0.01)).midicps).max(1);
		// §4 the head is what the curve is read AT, and in Repitch the head rate
		// is built FROM the root: a direct read would be a cycle in the graph.
		// One block of feedback breaks it — the curve is sampled every 1.5 ms of
		// material and lagged into the bargain, so a 1.3 ms old head position is
		// far inside its own resolution. LocalIn's first block is 0 ⇒ pAt(0),
		// which is exactly the reference the compensation wants anyway.
		var headFb = if (rootAn) { LocalIn.kr(1) } { 0 };
		var rootHz = if (rootAn) { Select.kr(pOk, [rootKn, pAt.(headFb)]) } { rootKn };
		var freqG  = Lag.kr(freq.max(1), glide.clip(0, 2));
		var keyR   = (freqG / rootHz) ** keytrack.clip(0, 2);       // keytrack 0 ⇒ 1 (natural pitch)
		var rateP  = pitch.clip(-36, 36).midiratio * keyR;          // PITCH of the material
		var bpmR   = Select.kr(useBpm.round(1).clip(0, 1), [1, (tempo * 60) / smpBpm.max(1)]);
		var revB   = reverse.round(1).clip(0, 1);
		var dirC   = 1 - (2 * revB);                                // ± direction: the R toggle ONLY
		// [RN] «and, when appropriate, the playback speed is compensated». WHERE
		// it is appropriate is the whole of that sentence, and in F2 that is the
		// three modes whose head rate does not carry the pitch — Cycles, Textures
		// and Fragments — where it costs nothing because the two were never
		// coupled: the head keeps travelling at `speed` while the analyzed root
		// flattens the cycle / grain pitch.
		// REPITCH is the one mode where rate IS pitch, by definition, so the two
		// cannot both be held: dividing the head rate back by the local pitch
		// would restore the timing by cancelling the pitch tracking exactly
		// (rateP ∝ pAt(head)^-keytrack against a compensation of pAt(head)), and
		// an analyzed root would do nothing at all. So Repitch keeps the FLAT
		// PITCH and lets the timing follow it, which is what a resampler does and
		// what the feature is for; holding both needs a granular re-pitch of the
		// read itself, the same engine §7.8 defers for Spectral. F2's reading
		// (`~`, SAMPLER.md §2).
		// speed is a positive multiplier and never flips the head (decision 1);
		// only Repitch folds the material pitch into the head rate — that IS the
		// definition of the mode
		var rateH  = speed.clip(0, 4) * bpmR * dirC * if (mode == 'repitch') { rateP } { 1 };
		// ── the anchor. §cell-trig: \f2voice pulses t_trig on EVERY cell event of
		// the strip, so a cell onset always re-latches the start — and, in Sliced,
		// the slice index with it. Sample-vs-grid drift is bounded to one cell,
		// exactly like the grainU tape motor.
		// The anchor is a CONTROL trigger — the head is latched at control rate
		// and only the Sweep reset is placed sample-exactly (T2A), the grainU
		// motor idiom. A K2A of the raw trigger would ramp across the block and
		// an ar Latch would grab a sixty-fourth of the start position instead of
		// the position itself: silent reverse playback, and every non-zero start
		// off by a block. The head also anchors at the voice's BIRTH
		// (Impulse.kr(0), as the grainU motor does), so a voice spawned with its
		// gate already open never starts from a stale zero.
		var trigK  = Trig.kr(g) + Trig.kr(t_trig);
		var birth  = Impulse.kr(0);
		var anchorK = trigK + birth;
		var anchor = T2A.ar(anchorK);
		// Shot fires on note events only — plus that same birth WHEN THE GATE IS
		// ALREADY OPEN (a parked pool voice, spawned gate 0 by \f2voice, must
		// stay silent until its first real note). CONTROL rate, one block late,
		// both deliberate: an EnvGen reads its gate at the block edge, so a
		// one-sample audio trigger inside the block is missed outright, and a
		// trigger that arrives in the voice's FIRST block is compared against
		// whatever the recycled node memory held and is missed about half the
		// time. Measured both ways — the one-shot stayed silent for a fresh node
		// spawned after ~30 voices had come and gone, and sounded in an
		// otherwise empty server. This costs 1.3 ms and always fires.
		var shotT  = TDelay.kr(trigK + (birth * (g > 0)), ControlDur.ir);
		// ── read window (§2): the yellow PLAY markers in Single, the SELECTED
		// SLICE in Sliced. Either pair is sorted, so either can be dragged past
		// itself; the blue Slicing Start / End pair bounds the region that was
		// sliced (§1.8), exactly as the yellow pair bounds Single's play region.
		var pS = playStart.clip(0, 1);
		var pE = playEnd.clip(0, 1);
		var bS = sliceStart.clip(0, 1);
		var bE = sliceEnd.clip(0, 1);
		var blA = bS.min(bE);
		var blB = bS.max(bE);
		var spR = if (sliced) { slicePlay.round(1).clip(0, 3) } { 0 };
		// SLICED: the window comes out of the slice TABLE — `[n, b0 … bn]` in one
		// buffer (§6), so the graph has a SINGLE code path whatever produced the
		// boundaries. `n` is read from the header every block, so a re-analysis
		// that refills the table in place moves the grid under a sounding note.
		// sliceBuf = -1 (nothing resolved yet) means one slice over the whole blue
		// region, and the bufnum read falls back to `buf` so an unallocated buffer
		// is never touched.
		var slT = if (sliced) {
			var ok = sliceBuf >= 0;
			var bn = Select.kr(ok, [buf, sliceBuf]);
			var n  = (BufRd.kr(1, bn, 0, 0, 1) * ok).round(1).clip(1, 64);
			// [RN]: the Select value AT NOTE ON chooses which slice is triggered —
			// latched on the very trigger the head anchors on (§2), then wrapped to
			// the LIVE count of the table (`mod`, so 8 of 8 slices is slice 0).
			var k  = Latch.kr(slice.clip(0, 63).round(1), anchorK).mod(n);
			var t0 = (BufRd.kr(1, bn, k + 1, 0, 1) * ok).clip(0, 1);
			var t1 = ((BufRd.kr(1, bn, k + 2, 0, 1) * ok) + (1 - ok)).clip(0, 1);
			// the grid of the table is stretched into the blue markers (§1.8): they
			// are LIVE controls, so an analysis can never be keyed on them — at the
			// default 0…1 the boundaries sit exactly where the analysis put them
			[k, blA + (t0 * (blB - blA)), blA + (t1 * (blB - blA))]
		} { [0, 0, 1] };
		var kSel = slT[0];
		var wA = if (sliced) { slT[1] } { pS.min(pE) };
		// `to Sample end` extends the window from the slice boundary to the blue
		// END marker — the blue pair bounds the sliced region by definition (§1.8),
		// it is not the raw end of the file
		var wB0 = if (sliced) { Select.kr((spR - 1).abs < 0.5, [slT[2], blB]) } { pS.max(pE) };
		var wB = wB0.max(wA + frames.reciprocal);            // never a window of no length
		var wL = wB - wA;
		// ── loop region: absolute in Single, RELATIVE TO THE SLICE in Sliced
		// (§1.1 — and so is OFFSETS LOOP, so the same gesture means the same thing
		// in both), shortened from its end by OFFSETS LEN.
		// Which loop is running: `loopMode` in Single, `slicePlay` in Sliced
		// (§1.8 — `loopMode` is ignored there). [RN]: the two looping playback
		// modes «require the Gated envelope» — any envelope but SHOT, now that
		// there are six (ENVELOPE.md §2.10) — so under `env: shot` a sliced variant
		// does not BUILD the fold at all and LOOP / PP fall back to `to Slice end`.
		var loopBuilt = sliced.not or: { shot.not };
		var loopM  = if (sliced) { 0 } { loopMode.round(1).clip(0, 2) };
		var loopOn = if (sliced) { if (shot) { 0 } { spR > 1.5 } } { loopM > 0.5 };
		var ppOn   = if (sliced) { if (shot) { 0 } { spR > 2.5 } } { loopM > 1.5 };
		var loopR  = if (loopBuilt) {
			var oL = offLoop.clip(-1, 1);
			var r0 = if (sliced) { wA + ((loopStart.clip(0, 1) + oL) * wL) }
				{ loopStart.clip(0, 1) + oL };
			var r1 = if (sliced) { wA + ((loopEnd.clip(0, 1) + oL) * wL) }
				{ loopEnd.clip(0, 1) + oL };
			var r1b = r1 - (offLen.clip(0, 1) * (r1 - r0));
			var a = r0.min(r1b).clip(wA, wB);
			var b = r0.max(r1b).clip(wA, wB);
			[a, b, (b - a).max(frames.reciprocal)]
		} { [0, 0, 1] };
		var lA = loopR[0];
		var lB = loopR[1];
		var lL = loopR[2];
		// OFFSETS PLAY moves the head INTO the window along the direction of
		// travel (reverse starts at wB and counts down), so the same gesture
		// means the same thing in both directions.
		var startV = Select.kr(revB, [wA, wB]) + (dirC * pos.clip(0, 1) * wL);
		var start  = K2A.ar(Latch.kr(startV, anchorK));   // one block of blend at the splice
		// normalised positions per second. `dur` is the buffer's OWN duration
		// (BufDur reads the file's sample rate, not the server's), and Sweep counts
		// seconds, so 1/dur is natural speed on any file. BufRateScale does not
		// belong here — and, measured since (sc/nrt/rootkey.scd), it does not
		// belong on GrainBuf's `rate` either: that rate is already relative to the
		// buffer's own sample rate. Either way the factor detuned every sample
		// whose rate differed from the server's by exactly their ratio: 44.1 kHz
		// material on a 48 kHz server played 8.1 % flat.
		var adv    = rateH / dur;
		var raw    = start + Sweep.ar(anchor, adv);                 // free-running, unbounded, signed
		// no loop: the head stops at the window edge — one frame INSIDE it, because
		// the boundary sample already belongs to the next slice. Parking ON it holds
		// that sample as DC, which is a click on any grid whose slices do not start
		// at a zero crossing (measured: `to Slice end` on a hat clicked with the
		// snare's first sample, sc/nrt/sliced.scd)
		var headOff = raw.clip(wA, wB - frames.reciprocal);
		// the fold and its escape exist only where a loop can: `0` here is a plain
		// number, not a UGen, and nothing downstream reads it in that case
		var u     = if (loopBuilt) { (raw - lA).mod(lL) } { 0 };
		var off   = if (loopBuilt) { 1 - (g > 0) } { 0 };           // 1 after the note off
		var escOn = if (loopBuilt) { off * (loopOff > 0.5) } { 0 };
		var headRun = if (loopBuilt) {
			var fold   = (raw - lA).mod(2 * lL);
			var headLp = lA + u;                                    // one-way
			var headPp = lA + (lL - (fold - lL).abs);               // ping-pong: triangle fold
			var dirPp  = ((fold < lL) * 2) - 1;                     // ±1: which leg of the fold
			var headFd = Select.ar(ppOn, [headLp, headPp]);
			var dirFd  = Select.ar(ppOn, [DC.ar(1), dirPp]);        // direction RELATIVE to raw
			// ── At Note Off (§1.1 loopOff): STAY keeps folding, FREE continues from
			// where the fold was, EXIT from the loop boundary the head was heading
			// for. Both add a latched escape offset to the free accumulator, so the
			// head continues with no jump in speed or direction. It applies to the
			// Single loop and to the two looping `slicePlay` values alike (§1.1).
			var nOff   = T2A.ar(Trig.kr(off));         // block start: with escOn, not a sample later
			var hOff   = Latch.ar(headFd, nOff);
			var rOff   = Latch.ar(raw, nOff);
			var dOff   = Latch.ar(dirFd, nOff);
			var escEnd = Select.ar((K2A.ar(dirC) * dOff) > 0, [K2A.ar(lA), K2A.ar(lB)]);
			var esc    = Select.ar(loopOff.round(1).clip(0, 2), [DC.ar(0), hOff, escEnd]);
			var headFr = esc + (dOff * (raw - rOff));
			Select.ar(loopOn, [headOff, Select.ar(escOn, [headFd, headFr.clip(wA, wB)])])
		} { headOff };
		// freeze is STRUCTURAL: the advance branch is not built at all and `pos`
		// is the head. The grain engines keep spraying around it — that is the
		// point of freeze in Textures.
		var head   = if (frozen) { K2A.ar(wA + (pos.clip(0, 1) * wL)) } { headRun };
		// §4 close the one-block loop the analyzed root reads the curve through
		// (see `headFb` above). Built only in a ROOTAN variant, so the manual
		// root pays neither the LocalIn/LocalOut pair nor the A2K.
		var headFbOut = if (rootAn) { LocalOut.kr(A2K.kr(head).clip(0, 1)) } { 0 };
		// ── loop crossfade: a second reader one loop AHEAD IN TRAVEL — the
		// material that continues past the seam — faded out over the first `xf`
		// of the new lap. Held at a single reader (xw = 1) when the fade is 0,
		// when the loop is off, in ping-pong (its seam is a direction reversal:
		// the signal is continuous, there is nothing to splice) and once the
		// head has escaped the loop at the note off — and it is not built at all
		// where no loop is (a sliced one-shot).
		var head2 = if (loopBuilt) { head + Select.kr(revB, [lL, lL.neg]) } { head };
		var xw    = if (loopBuilt) {
			var xf    = (loopXfade.clip(0, 0.5) * lL).max(frames.reciprocal);
			var uSeam = Select.ar(revB, [u, lL - u]);               // travelled since the seam
			var xfOn  = loopOn * (loopXfade > 0.001) * (1 - ppOn) * (1 - escOn);
			((uSeam / xf) + (1 - xfOn)).clip(0, 1)
		} { 1.0 };
		// ── grain size unit (§1.5): seconds, or beats snapped to the grid and
		// divided by the tempo bus (beats/sec) to get seconds. The grid stays the
		// 16th note ([RN]'s default unit): `beatLen` is a RESOURCE opt (§1.0) — it
		// changes no graph by definition, so it cannot be the snap grid of a build
		// constant. It bounds slices, not grains.
		var gBeat = (grainSize / 0.25).round(1).max(1) * 0.25;
		var gsz   = Select.kr(sizeUnit.round(1).clip(0, 1),
			[grainSize, gBeat / tempo.max(0.01)]).clip(0.002, 2);
		// §ptrs the last `nPtr` GRAIN read positions, each signed by the direction
		// that grain reads in: a shift register clocked by the grain trigger, so
		// every slot holds a position a grain really started at. A slot is live
		// only while a grain is still sounding in it — the overlap is rate · size
		// by definition, so slot i is alive while `i < rate·size` and while the
		// voice has fired that many grains at all. A dead slot sends -2, which is
		// outside every real position and is how the card knows to draw nothing.
		var grainPtrs = { |trg, gp, gdir, rHz|
			var ovl = rHz * gsz;
			var cnt = A2K.kr(PulseCount.ar(trg, anchor));
			var prev = gp * gdir, out = [];
			nPtr.do { |i|
				var lat = Latch.ar(prev, trg);
				var ok  = (cnt > i) * (ovl > i);
				out = out.add((A2K.kr(lat).clip(-1, 1) * ok) - (2 * (1 - ok)));
				prev = Delay1.ar(lat);
			};
			out
		};
		// Grain Envelope is a curve MORPH, not a menu: a kr offset into the
		// 16-window bank ~f2SmpWins (§3), so it stays a live control.
		var wIdx  = if (wBase < 0) { -1 } { wBase + (grainEnv.clip(0, 1) * (wN - 1)).round(1) };
		// ── §1.4 CYCLES, the two numbers the mode is built on. They are hoisted
		// out of the engine branch because the '/f2_head' span (§5) draws the
		// cycle window; in every other variant the `if` folds to a plain 0 at
		// BUILD time and not a single UGen is made.
		// `cycF` is the rate the extracted waveform is played at — the NOTE, not
		// the head: `speed` never appears in it, which is the whole definition of
		// the mode ([RN]: Speed does not move the pitch). At keytrack 0 that is
		// the root, at 1 it is `freq` itself; `pitch` transposes the material as
		// everywhere else. `cycLen` is one cycle of it as a FRACTION of the file,
		// scaled by Formant: the lanes read `cycLen` of material per cycle, so a
		// formant of +12 st reads the extracted cycle twice as fast (formants up)
		// while the cycle rate stays put. §2's sketch divided by that ratio; a
		// window that shrinks as the formant rises reads the material SLOWER and
		// moves the formants DOWN, so the multiplication is the one that matches
		// the control's name (§8 b, F2's polarity).
		var cycF   = if (mode == 'cycles') { (rootHz * rateP).clip(8, 12000) } { 0 };
		var cycLen = if (mode == 'cycles') {
			(formant.clip(-24, 24).midiratio / (dur * cycF)).clip(frames.reciprocal, 0.45)
		} { 0 };
		// §1.6 GRAINS SURVIVE VOICE END, the time it is worth: one grain group,
		// `grainSize · repeats` (§1.6). Zero in every other mode and whenever the
		// switch is off, and capped at 2 s so the extreme corner of the two knobs
		// (2 s × 16 repeats = half a minute) cannot park a voice in the pool —
		// F2's cap, the release notes give none (`~`).
		var fragTail = if (mode == 'fragments') {
			(gsz * repeats.clip(1, 16).round(1) * grainSurvive.round(1).clip(0, 1)).clip(0, 2)
		} { 0 };
		// … and how it is spent: a level-0 segment appended to whichever envelope
		// the variant builds, so the ENVELOPE's own doneAction is what fires late
		// and no second free path has to agree with it.
		var tailL = if (mode == 'fragments') { [0] } { [] };
		var tailT = if (mode == 'fragments') { [fragTail] } { [] };
		var tailC = if (mode == 'fragments') { [0] } { [] };
		// §ptrs filled by the engine branch below with its OWN read pointers, in
		// the units '/f2_head' sends them: |value| is the position in 0…1 of the
		// file and its SIGN is the direction that pointer reads in, so two grains
		// walking opposite ways read as two opposite pointers on the card. -2 is
		// «no pointer here».
		var ptrs = nil;
		// §5 the span a spectral head draws: the analysis window, filled in by the
		// branch below because only it knows the FFT size. 0 in every other
		// variant, where the `if` folds at build time.
		var specSpan = 0;
		// ── the engine: exactly ONE branch is built, the others are absent from
		// the variant (§2).
		var sig = if (mode == 'repitch') {
			// tape machine: rateH already carries the material pitch
			var rdA  = BufRd.ar(1, buf, head * frames, 0, 4);       // cubic
			// the second reader exists only where the crossfade does
			var raw0 = if (loopBuilt) {
				(rdA * xw) + (BufRd.ar(1, buf, head2 * frames, 0, 4) * (1 - xw))
			} { rdA };
			// §ptrs it is a REAL second read pointer while the fade is running —
			// the material that continues past the loop seam, one loop ahead in
			// travel — so the card draws it beside the head instead of pretending
			// the voice reads the file in one place. Silent at xw = 1 (no fade,
			// no loop, ping-pong, escaped): the reader is there but contributes
			// nothing, and a pointer that is not heard is not drawn.
			var pLive = if (loopBuilt) { A2K.kr(xw) < 0.999 } { 0 };
			var pSet = ptrs = [((A2K.kr(head2).clip(0, 1) * dirC) * pLive) - (2 * (1 - pLive))];
			var r    = rateH.abs.clip(0.25, 4);                     // the rate the character follows
			var dA   = dist.clip(0, 1);
			var cA   = color.clip(-1, 1);
			var eqF  = (1200 * r).clip(200, 12000);
			// ANLG — Crunch between a rate-dependent pre- and post-EQ, so every
			// note of a chord gets its own flavour
			var pre  = MidEQ.ar(raw0, eqF, 0.8, dA * 10);
			var cru  = (pre * (1 + (dA * 8))).tanh / (1 + (dA * 2));
			var post = MidEQ.ar(cru, eqF, 0.8, dA * -10);
			// Color + pushes the high end and lowers the mids, − the low-mids
			var tilt = post + (cA * (HPF.ar(post, 3000) - LPF.ar(post, 700)));
			// … and shapes the transients with it: + flattens, − expands
			var fastE = Amplitude.ar(tilt, 0.001, 0.02);
			var slowE = LagUD.ar(fastE, 0.05, 0.15);
			var tGain = ((fastE / slowE.max(0.0001)).max(0.001) ** (cA * -0.5)).clip(0.25, 4);
			var anlg  = tilt * tGain;
			// DIGI — bit reduction plus sample-rate reduction. Color + makes
			// more "mistakes" (heavier aliasing), − stays smoother and darker;
			// Variable Sample Rate lets the decimation follow the playback rate.
			// The top of the range stays just BELOW the sample rate on purpose:
			// an Impulse at exactly SR never fires and the decimator would then
			// latch silence for the whole note.
			var srD  = (SampleRate.ir / (1 + (cA.max(0) * 63) + (cA.neg.max(0) * 15))
				* Select.kr(varSR.round(1).clip(0, 1), [1, r])).clip(100, SampleRate.ir * 0.999);
			var bitQ = (2 ** (12 - (dA * 8))).reciprocal;           // 12 bits … 4 bits
			var dec0 = Latch.ar(raw0.round(bitQ), Impulse.ar(srD));
			var dec1 = LPF.ar(dec0, (18000 * (1 - (cA.neg.max(0) * 0.92))).clip(1400, 18000));
			// Digital Imaging Filter — a rate-dependent output filter
			var digi = Select.ar(imgFilt.round(1).clip(0, 1),
				[dec1, LPF.ar(dec1, (srD * 0.45).clip(200, 18000))]);
			Select.ar(character.round(1).clip(0, 2), [raw0, anlg, digi]) ! 2
		} { if (mode == 'cycles') {
			// ── §1.4 CYCLES: single waveforms lifted out of the file as pseudo
			// wavetables and played at the note pitch. The head of §2 only says
			// WHERE the waveform is lifted from — the pitch is `cycF` alone, so
			// `speed`, `useBpm` and `reverse` move the extraction point through
			// the file and never touch the note.
			//
			// ONE waveform is read by TWO lanes a cycle apart, windowed with a
			// raised cosine that spans two cycles and hops one, so the pair sums
			// to exactly 1 at every phase (win(x) + win(x+1) = 1) and the seam of
			// each lane is covered by the other's full amplitude. That is what
			// makes the output periodic at `cycF` to the sample whatever the
			// material is: inside a snapshot the wavetable does not move, so the
			// only period in the signal is the phasor's.
			var x2   = xfade2.round(1).clip(0, 1);
			var cl   = cycLen;
			var ph   = Phasor.ar(anchor, cycF * sdur, 0, 1);       // ONE phase for both readers
			// The snapshot clock — `gsz`, the §1.5 grain size in seconds or beats,
			// which [RN] makes the CROSSFADE TIME. It is the one number the mode
			// needs and it is read whether or not the crossfade is on (§1.4, F2's
			// construction): a waveform lifted anew every CYCLE is no waveform at
			// all — the head advances `speed/formant` of a cycle in that time, and
			// at 100 % speed with no formant shift that is exactly the cycle the
			// lanes read, so the reader would walk straight through the file and
			// hand back the tape with the note's pitch nowhere in it. Held for
			// `gsz` the table is a real wavetable: the phasor is then the ONLY
			// period in the signal, which is why the pitch is the note's whatever
			// the head does.
			// With Crossfade Two Voices OFF one reader lifts a table every `gsz`
			// and jumps to it — the step §7.5 calls the discontinuity at the cycle
			// boundary. With it ON two readers lift one half a period apart and
			// each one's gain is exactly 0 at its own snapshot, so nothing of the
			// jump reaches the output.
			var xph  = Phasor.ar(anchor, sdur / gsz, 0, 1);
			var wrapT = { |p| HPZ1.ar(p) < -0.25 };                // the sample after a phasor wraps
			var trA  = wrapT.(xph) + anchor;
			var trB  = wrapT.((xph + 0.5).wrap(0, 1)) + anchor;
			// the two lanes read up to two cycles past the snapshot, so the
			// snapshot is held that far from the end of the file: BufRd would
			// otherwise clamp on the last frame and hold it as DC
			var hMax = (1 - (2 * cl)).max(0);
			var hA   = Latch.ar(head, trA).clip(0, hMax);
			var hB   = Latch.ar(head, trB).clip(0, hMax);
			// §ptrs the two lanes lift their waveform HERE — the snapshot a lane
			// is reading, held for `gsz` and then jumping on. That is where the
			// sound of this voice is coming out of the file, so both are pointers.
			// Forward by construction: a lane reads its cycle at cycF, whatever
			// the head does. With the crossfade off the two coincide half the
			// time, which is exactly what the mode does.
			var pSet = ptrs = [A2K.kr(hA).clip(0, 1), A2K.kr(hB).clip(0, 1)];
			var gA   = Select.ar(x2, [DC.ar(1), 0.5 - (0.5 * cos(2pi * xph))]);
			// ── the characters (§1.4). PULSE and PHASE reshape the phase the
			// lanes read the waveform with; PART works on the signal.
			// PULSE — the width moves the BREAKPOINT at which the read reaches the
			// middle of the extracted waveform: at +1 the first half of the cycle
			// is stretched over 95 % of the period and the second crammed into the
			// rest, at −1 the other way round. That is a pulse width, not a
			// filter: the two ends of the cycle stay where they are (so the
			// boundary is as continuous as it was) and only the duty changes.
			// `~` scale, §8 b.
			var wD   = 0.5 + (width.clip(-1, 1) * 0.45);
			var pw   = Select.ar(ph < wD,
				[0.5 + (0.5 * (ph - wD) / (1 - wD)), 0.5 * ph / wD]);
			// PHASE — a dirty sine modulator: a partial at a whole ratio of the
			// played pitch plus a quieter one just off twice that, which is what
			// makes it dirty. Both are locked to the cycle phase, so the clean
			// half stays harmonic. `cycHarm` steps the ratio 1…8 (`~`, §8 b).
			var hRat = cycHarm.round(1).clip(0, 7) + 1;
			var md   = cycMod.clip(0, 1) * (SinOsc.ar(0, ph * 2pi * hRat)
				+ (0.15 * SinOsc.ar(0, ph * 2pi * hRat * 2.01)));
			var q    = Select.ar(cycChar.round(1).clip(0, 2), [pw, ph, (ph + md).wrap(0, 1)]);
			var lane = { |h, o|
				var x = q + o;
				BufRd.ar(1, buf, (h + (x * cl)) * frames, 0, 4) * (0.5 - (0.5 * cos(pi * x)))
			};
			var cyc  = ((lane.(hA, 0) + lane.(hA, 1)) * gA)
				+ ((lane.(hB, 0) + lane.(hB, 1)) * (1 - gA));
			// PART — Split isolates the odd or the even harmonics of the played
			// pitch. Half a period of delay is all it takes: the signal is
			// periodic at `cycF` by construction, so (x − x delayed by T/2) is
			// exactly its odd harmonics and (x + x delayed by T/2) its even ones,
			// with no filter and no second pair of lanes.
			var sh   = DelayC.ar(cyc, 0.034, (0.5 / cycF).clip(0.0002, 0.033));
			var sp   = split.clip(-1, 1);
			var prt  = (XFade2.ar((cyc - sh) * 0.5, (cyc + sh) * 0.5, sp) * sp.abs)
				+ (cyc * (1 - sp.abs));
			// … and Fund puts a sine back at the played pitch, phase-locked to
			// the cycle and following the voice's current level ([RN]) — F2 reads
			// that as the level of the cycle signal itself, so the sine breathes
			// with the material and not with the envelope that scales both
			prt = prt + (fund.clip(0, 1) * SinOsc.ar(0, ph * 2pi)
				* Lag.kr(Amplitude.kr(cyc), 0.01));
			Select.ar(cycChar.round(1).clip(0, 2), [cyc, prt, cyc]) ! 2
		} { if (mode == 'spectral') {
			// §1.7 SPECTRAL: the phase vocoder of ~f2SmpSpectral above,
			// PITCH-LOCKED (decision 2). The head is a FRAME POSITION in the
			// file's own analysis and nothing else in this graph reaches the
			// spectrum — `rateP` is not read here at all, which is why the whole
			// first row of §1.11 is dead in this mode.
			if (specPV) {
				var spec = topEnvironment[\f2SmpSpectral].(fftQ[\nfft], fftQ[\hop],
					fftQ[\wintype], fftQ[\gain], fftQ[\smear], fftNull,
					head, rateH, dur, buf, fftBuf, onsetBuf, pitchBuf, freqG, rootHz,
					spChar, preserveOnsets, formantOn, formantShift, formantAmt, relFormant,
					harmBend, harmQuant, harmQuantAmt, key, scale, phaseDisp);
				specSpan = spec[\span];
				spec[\sig]
			} {
				// §2 / §702 the fallback: with no sc3-plugins there is no spectrum
				// to read, and Warp1 is the one stretch in the core that takes a
				// POSITION rather than a rate — so the head still drives it and the
				// mode is still a time machine, with none of §1.7 behind it. Its
				// window is the span the card draws, as the FFT window is above.
				var wSz = 0.1;
				specSpan = (wSz / dur.max(0.001)).clip(0, 1);
				Warp1.ar(1, buf, head.clip(0, 1), 1, wSz, -1, 4, 0.1, 2) ! 2
			}
		} { if (mode == 'fragments') {
			// §1.6 FRAGMENTS: the richer cloud. Textures sprays ONE grain stream
			// whose rate IS the repeat rate; here the rate is its own control and
			// every grain carries its own position, direction and (latched) rate.
			// Grain Size and Motion are the SAME §1.5 controls Textures reads —
			// [RN] shares them between the two modes so switching preserves the
			// settings, so there is one group in the schema and one here.
			var rp   = repeats.clip(1, 16).round(1);
			// the trigger rate: DENS is relative to the grain size — density 10
			// means ten overlapping grains, so the rate is density / gsz ([RN]) —
			// RATE is the uncoupled absolute alternative and follows `sizeUnit`
			// exactly as the size does (Hz, or grains per beat × the tempo bus)
			var grU  = grainRate.clip(0.1, 200);            // Hz, or grains per BEAT
			var rHz  = Select.kr(coupled.round(1).clip(0, 1),
				[density.clip(0.1, 100) / gsz,
					Select.kr(sizeUnit.round(1).clip(0, 1), [grU, grU * tempo.max(0.01)])]);
			// MAXIMUM GRAINS PER VOICE (the `grains` opt, §1.0) is GrainBuf's
			// maxGrains — an instantiation argument, so it is structural and the
			// graph has to live inside it. Overlap is rate · gsz by definition,
			// so the ceiling is a ceiling ON THE RATE: clamped here, the engine
			// never asks for a grain it has no slot for. Left unclamped GrainBuf
			// drops every grain past the cap and prints «Too many grains!» per
			// drop — a console flood and a cloud that thins out instead of
			// holding its density. The ceiling is nGrain − 2 rather than nGrain:
			// GrainBuf refuses a trigger that arrives while its slots are FULL,
			// so one slot has to be standing by at every trigger, and the live
			// count is not steady — the impulse period is rarely a whole number
			// of samples, so an overlap of exactly nGrain − 1 still touches the
			// rim now and then. Measured on the live server, 8 voices each:
			// nGrain·0.98 → 490 «Too many grains!» in one pass, nGrain − 1 → 490
			// again at the two settings that sit exactly on it, nGrain − 2 → none
			// at any setting. F2's reading of the cap (`~`).
			var rCap = ((nGrain - 2).max(1) / gsz).max(0.1);
			var trg  = Impulse.ar(rHz.min(rCap));
			var gHld = PulseDivider.ar(trg, rp);                    // one position per repeat group
			var mo   = motion.clip(0, 8);
			// Motion randomises each grain's playhead (± motion · grain size) and
			// its stereo position (motion / 8). The playhead throw is rolled once
			// per repeat GROUP — that is what makes a group a group; at the
			// default `repeats` of 1 the group IS one grain and the throw is per
			// grain, exactly as in Textures.
			var gJit = TRand.ar(mo.neg, mo, gHld) * gsz / dur;
			// REPEAT AT INITIAL POSITION [RN]: on, every repeat of a group replays
			// the FIRST grain's position — head and throw both latched at the
			// group's first grain; off, the repeats keep the group's throw but
			// FOLLOW THE ADVANCING HEAD. GrainBuf samples `pos` at the trigger, so
			// the un-latched branch is already one position per grain.
			// §2's sketch latched the throw on the same trigger as the position,
			// which left `repeats` doing nothing at all at `repeatInit: —` — its
			// own default. Rolling the throw per group instead is what gives the
			// control an effect on BOTH sides of the switch, and it is what makes
			// consecutive grains «repeat the same snippet» (§1.5) while the head
			// is frozen or slow. F2's reading (`~`, §1.6).
			var gpos = Select.ar(repeatInit.round(1).clip(0, 1),
				[head + gJit, Latch.ar(head + gJit, gHld)]).wrap(wA, wB);
			var gpan = TRand.ar(-1, 1, trg) * (mo / 8).clip(0, 1);
			// GRAIN PLAYBACK DIRECTION (inspector, [RN]): SMPL reads the material
			// the way it lies, HEAD (the default) reads it the way the playhead
			// travels — the two differ only under `reverse` — RAND picks per
			// grain, ALT flips every grain
			var gDir = Select.ar(grainDir.round(1).clip(0, 3),
				[DC.ar(1), K2A.ar(dirC),
					((TRand.ar(0, 1, trg) > 0.5) * 2) - 1,
					(ToggleFF.ar(trg) * 2) - 1]);
			// LATCH INITIAL RATE: the grain rate is frozen at the voice's FIRST
			// grain (F2's reading of the latch point, §8 b), so pitch modulation
			// after that moves the head and leaves the grains where they were.
			// The anchor latches too, so the value is sane in the blocks before
			// that first grain exists.
			var gOne = trg * (PulseCount.ar(trg, anchor) < 1.5);
			var gRt  = Select.ar(latchRate.round(1).clip(0, 1),
				[K2A.ar(rateP), Latch.ar(K2A.ar(rateP), anchor + gOne)]);
			// §ptrs every sounding grain is its own read pointer, and in Fragments
			// they need not agree on a direction: GRAIN PLAYBACK DIRECTION reads
			// per grain (RAND rolls it, ALT flips it), so the signed slots below
			// really do walk opposite ways on the card.
			ptrs = grainPtrs.(trg, gpos, gDir, rHz.min(rCap));
			GrainBuf.ar(2, trg, gsz, buf, gRt * pGrain.(gpos) * gDir, gpos, 2, gpan, wIdx, nGrain)
		} {
			// textures: one cloud at the head. Size, Motion, Grain Envelope and
			// Repeats are the shared §1.5 group; the loop seam needs no
			// crossfade here — the grain windows already cover it.
			var rp   = repeats.clip(1, 16).round(1);
			var trg  = Impulse.ar(rp / gsz);
			var gHld = PulseDivider.ar(trg, rp);                    // one position per repeat group
			var mo   = motion.clip(0, 8);
			// Motion randomises the playhead (± motion · grain size) and the
			// stereo position (motion / 8) of every grain group
			var gpos = Latch.ar(head + (TRand.ar(mo.neg, mo, gHld) * gsz / dur), gHld).wrap(wA, wB);
			var gpan = TRand.ar(-1, 1, trg) * (mo / 8).clip(0, 1);
			// §ptrs the cloud's grains, same shift register as Fragments. Textures
			// reads every grain forward (`reverse` moves the HEAD, not the grain),
			// so the slots are all positive — they spread around the head by
			// Motion instead of by direction.
			ptrs = grainPtrs.(trg, gpos, DC.ar(1), rp / gsz);
			GrainBuf.ar(2, trg, gsz, buf, rateP * pGrain.(gpos), gpos, 2, gpan, wIdx, nGrain)
		} } } };
		// ── filter (§1.9): the §flt slot on this unit's OWN cutoff bus (FILTER.md
		// §5.2) — cut × (freqG / rootHz)^filtKey against the sample ROOT, not
		// 261.63, formed as it always was, under the 20…20000 clip the slot keeps
		// for this unit. Drive multiplies in before the slot (0 dB = ×1 exactly);
		// filtFm, shaper and shaperMode are PLAIN ZEROS — no FM, no shaper on a
		// sampler — so the slot builds those paths out. At `poly` this is the old
		// cascade + BELL UGen for UGen: filtType 0…7 = fltMode 0…7, OFF = filtOn 0.
		var cutK = cut.clip(20, 20000) * ((freqG / rootHz) ** filtKey.clip(0, 2));
		var pre  = sig * drive.clip(-24, 24).dbamp;
		var flt  = fltSlot.(fltM, pre, cutK, 20, 20000, 0, res, fltMode, filtOn, 0, 0, false,
			fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain);
		var filt = flt[\filt];
		// ── amp envelope (§1.10). Shot plays the window through once from the
		// anchor: its length is the window at the current head rate.
		var shotLen = ((wL * dur / rateH.abs.max(0.01))          // = wL / adv
			- fadeIn.clip(0.001, 1) - fadeOut.clip(0.001, 1)).max(0.001);
		// … and the Fragments tail rides on the END of it (the `tail*` arrays are
		// empty in every other mode, so those envelopes are the ones they were).
		// §env the envelope through the shared fragment (~f2Aeg, ENVELOPE.md §2):
		// `ahdsr` under this unit's default D IS the gated Env this unit always
		// built, now at ar (§4.5); `shot` is its one-shot unchanged, driven by
		// shotT with the window as the body; the other models are the union's.
		var aegR = aegF.(envM, g, shotT,
			(atk: atk, hold: hold, dec: dec, sus: sus, rel: rel, atkC: atkC, decC: decC, relC: relC,
				envModel: envModel, envLoop: envLoop, fadeIn: fadeIn, fadeOut: fadeOut,
				shapeBuf: shapeBuf),
			shotLen, [tailL, tailT, tailC], i_free);
		var aeg  = aegR[\aeg];
		var aegK = aegR[\aegK];
		// §1.6 the LEVEL side of Grains Survive Voice End. The node now outlives
		// its envelope by `fragTail`, but the envelope multiplies the cloud, so
		// on its own that only buys a longer silence. Holding the level up for
		// exactly the same span is what makes the last grain group audible:
		// max(now, `fragTail` ago) keeps the pre-release level through the
		// release and then plays the release curve out over the tail, reaching
		// zero at the very sample the envelope frees the node — one grain group
		// of ring-out, no step to click on. With the switch off `fragTail` is 0
		// and the max is the envelope itself.
		var aegOut = if (mode == 'fragments') { aegK.max(DelayN.kr(aegK, 2, fragTail)) } { aeg };
		// §smp declick, the grainU `dip`: every head discontinuity — the cell
		// re-anchor, a loop seam without a crossfade, a jumped `pos` — is
		// covered by a 3 ms dip. The threshold is RELATIVE to the natural
		// per-sample advance, so fast varispeed never ducks itself and a
		// ping-pong fold (two steps wide) does not count as a splice.
		var step  = (adv * sdur).abs;
		var jump  = (head - Delay1.ar(head)).abs;
		var dip   = 1 - LagUD.ar(Trig1.ar(jump > (step * 4).max(0.002), 0.003), 0.0002, 0.003);
		var outLv = aegOut * velC * smpGain.clip(-12, 12).dbamp * gain.clip(-24, 24).dbamp * amp;
		var sigO  = Balance2.ar(filt[0] * dip, filt[1] * dip, pan.clip(-1, 1), outLv);
		// ── telemetry (§5). ONE 30 Hz clock and ONE audibility gate feed both
		// replies, so the level and the playhead of a voice always describe the
		// same instant. The gate is the §synth-mod one: a telId of 0 (no telOut on
		// the preset) sends nothing at all, and a voice that neither sounds nor
		// holds its gate is silent on the wire too.
		var telG = Impulse.kr(30) * (telId > 0) * ((aegK > 0.001) + (g > 0)).min(1);
		// §smp PLAYHEAD (SAMPLER.md §5, CARDS.md §8): [vi, ci, pos, span, mode]
		// with replyID = telId. The reply id names the PRESET, so the packet has to
		// name the writer inside it: `vi` the voice and `ci` the card of the strip —
		// without the card index the two samplerU cards a strip may hold (§8
		// decision 4) would land in one bucket and draw each other's heads.
		// `pos` is the head in 0…1 of the WHOLE sample, so the front places it
		// without knowing a single marker; `span` is what to draw
		// AROUND it in the same units — 0 for a tape head and for a frozen one,
		// the grain window for the clouds (Textures and Fragments spray the same
		// §1.5 size, so ONE expression serves both), the two cycles the Cycles lanes
		// read and the analysis window for spectral; a FROZEN Cycles head still has a
		// window, because the mode keeps sounding with the head standing still — it
		// is only the tape reader and the grain cloud that have nothing left to draw;
		// `mode` is the drawing style as a bitfield, playCode + 8·SLICED
		// + 16·FROZEN. Every term of `mode` is a BUILD constant of the variant, so
		// the field is one literal in the graph and costs nothing per block.
		// Both are CLIPPED to 0…1 in the graph: a card with no sample yet reads an
		// empty buffer (BufFrames 1, BufDur 0.001) and would otherwise send a head
		// past the end of the plot and a span wider than the file.
		var posN  = A2K.kr(head).clip(0, 1);
		var spanN = case
			{ mode == 'cycles' } { (2 * cycLen).clip(0, 1) }
			// §5 spectral: the ANALYSIS WINDOW, which a frozen head keeps for the
			// reason a frozen Cycles head keeps its own — the vocoder goes on
			// resynthesising that window with the head standing still
			{ mode == 'spectral' } { specSpan }
			{ frozen or: { #['textures', 'fragments'].includes(mode).not } } { 0 }
			{ ((motion.clip(0, 8) + 1) * gsz / dur).clip(0, 1) };
		var modeC = (#['repitch', 'cycles', 'textures', 'spectral', 'fragments'].indexOf(mode) ? 0)
			+ if (sliced) { 8 } { 0 } + if (frozen) { 16 } { 0 };
		// … and, ABOVE bit 5, the slice the voice actually latched, so the card can
		// light the right cell of its grid without guessing which boundary pair the
		// head is between (`to Sample end` runs the head clean through the others).
		// `mode >> 5` is the slice index, `mode & 8` says whether to read it. Every
		// other term stays a BUILD constant, so the field costs one add per block in
		// a sliced variant and nothing at all anywhere else.
		var modeN = if (sliced) { modeC + (kSel * 32) } { modeC };
		// §ptrs …and after the five fixed values, the variant's OWN read pointers
		// (`nPtr` of them, a build constant): |v| the position, sign(v) the
		// direction, -2 for a slot with nothing sounding in it. The packet is a
		// fixed length per VARIANT, so the forwarder simply passes the tail on and
		// the card draws as many pointers as it is given.
		SendReply.kr(telG, '/f2_head', [vi, ci, posN, spanN, modeN] ++ (ptrs ? []), telId);
		// The level channel stays a ONE-writer channel: every voice of every sampler
		// card now carries telId (it has to, or the heads could not be told apart),
		// but `sc:<dk>` is a single value, so only voice 0 of the FIRST card reports
		// the level — exactly as before this unit existed. Without the factor the
		// channel would show whichever voice of whichever card fired last instead of
		// the preset's own level.
		SendReply.kr(telG * (vi < 0.5) * (ci < 0.5), '/f2_chan', [aegK], telId);
		Out.ar(out, Sanitize.ar(LeakDC.ar(sigO)));
	});
	bytes = def.asBytes.size;
	("[f2 smp] % (play % sl % env % freeze % root % grains % qual %): % bytes".format(def.name, mode,
		if (sliced) { 'sliced' } { 'single' }, envM,
		if (frozen) { 'on' } { 'off' }, if (rootAn) { 'analyzed' } { 'manual' }, nGrain,
		// the FFT pair the spectral branch was built on; '—' where no branch reads it
		if (mode == 'spectral') { "%×%".format(fftQ[\nfft], fftQ[\ovl]) } { '—' }, bytes)).postln;
	if (bytes > 16383) {
		("⚠ [f2 smp] % is % bytes > 16383 — sclang writes the def file and /d_load's it (local server)"
			.format(def.name, bytes)).postln;
	};
	def
};
// the base def (every menu at its default) — the SynthDesc the context export
// and \f2voice read; variants are built on demand by ~f2UnitDef / ~f2UnitEnsure
~f2UnitGen[\samplerU].value((), \samplerU).add;

// ── §pm Polymer (docs/design/POLYMER.md) ──────────────────────────────────
// STAGE 1 (§6.1): the shell. Bitwig-Polymer copy as a SOURCE card (no
// chainIn), and the difference from polysynthU is the whole point — Polysynth
// has two FIXED oscillators, Polymer has one SWAPPABLE slot, three of them:
// oscillator (9 models), filter (11: Bitwig's ten + `poly`, §flt) and envelope
// (7: Polymer's five + the sampler's `ahdsr` / `shot`, §env). Those three menus
// are STRUCTURAL (opts → a SynthDef variant, 9 × 11 × 7 = 693 nominal),
// everything else is live, the two per-model mode selects (fltMode / fltMode2),
// the envelope's A/R/D and loop and the sub waveform included: a model's own
// configuration list picks a TAP of a graph that is already built, and making
// it structural would multiply 693 by 16.
// A variant builds ONE oscillator, ONE filter and ONE envelope, so unlike
// Polysynth the def stays small however exotic the combination — Polymer's cost
// is the NUMBER of variants, not their size.
//
// THE 81 LIVE CONTROLS — §1.9's 71, the six the §flt union brings from
// Polysynth (fVel, filtFm, shaper, shaperMode, hpMode, hpRes), the block's
// `bellGain` and the §env union's `hold` / `fadeIn` / `fadeOut` — ARE DECLARED
// BY EVERY VARIANT, including the ones only an unbuilt model reads. The list
// is fixed the moment this def is added: a variant that dropped or renamed an
// arg would make the card's knobs vanish and reappear as the user swaps
// models, and every lock and every mod addressing them would break (§1.0,
// CARDS.md §5). The budget is 77 and not 146 because a control is named per
// ROLE and not per module — `oscPw` is Union's, Pulse's and Bite's pulse
// width, `oscSkew` is Sine's and Triangle's Skew and Saw's Shape, and the card
// prints Bitwig's own label per model.
//
// What is built so far: all nine oscillators — the five geometric of
// §6.2 (`osc: saw`, `sine`, `tri`, `pulse` and `union`, the schema default and
// Bitwig's own) on the saw bank and the triangle bank of ~f2PolymerTables, plus
// §6.6's `phase1` and `swarm`, §6.7's `bite` and §6.8's `scrawl` — the whole
// §1.3 sub and noise block behind them, `filt: ld` (and `poly`,
// Polysynth's core, through the shared ~f2FltSlot), and the §env union's whole
// seven — `adsr ahdsr ar ad pluck shot segments` — with the A/R/D model, its
// curve knobs and the AD loop through the shared ~f2Aeg. NO advertised value
// falls back on this unit any more: every one of the 693 is the graph its menus
// name, and the two ~f2UnitWarnOnce lines that said otherwise are gone with the
// stage. The seams are marked «stage N» in the code
// below. The sub, the noise leg, PM and hard sync are BUILT and are fixed
// hardware — no menu, no variant, on every one of the 693. The six Polysynth
// controls of the §flt
// union arrive at defaults that are exact no-ops on this graph: hpMode 1 keeps
// the HPF in circuit, hpRes 0 IS stage 1's HPF.ar, the other four multiply by
// one.
~f2UnitOpts[\polymerU] = (
	osc:   (values: #['sine', 'tri', 'pulse', 'saw', 'union', 'phase1', 'swarm', 'bite', 'scrawl'],
		def: 'union', label: "oscillator"),
	// §flt the shared model list (Bitwig's ten + `poly`), def `ld` — Polymer's own
	filt:  (values: ~f2FltModels, def: 'ld', label: "filter"),
	// §env the shared model list (Polymer's five + `ahdsr` / `shot`), def `adsr`
	env:   (values: ~f2EnvModels, def: 'adsr', label: "envelope"),
	// `kind: \curve` = an opaque encoded point list — the drawn cycle of
	// `osc: scrawl` and the drawn shape of `env: segments` (§6.8), the same class
	// of opt as samplerU's `cuts`. No value list and no range, so a front that
	// does not know the kind renders nothing for it rather than a broken menu;
	// `max` is how many breakpoints the value may carry.
	curve: (values: #[], def: '', label: "curve", kind: \curve, res: true, max: 64)
);
~f2UnitSpecs[\polymerU] = {
	var sp = ();
	// §1.1 the oscillator slot's shared block — all nine models carry it
	sp[\oscRatioN]  = (min: 0, max: 99, warp: \lin, label: "ratio n");
	sp[\oscRatioD]  = (min: 1, max: 99, warp: \lin, label: "ratio d");
	sp[\oscPitch]   = (min: -48, max: 48, warp: \lin, unit: "st", label: "pitch");
	sp[\oscHz]      = (min: -100, max: 100, warp: \lin, unit: "Hz", label: "detune");
	sp[\oscStereo]  = (min: 0, max: 1, warp: \lin, label: "stereo", sel: #["—", "±"]);
	sp[\oscRetrig]  = (min: 0, max: 1, warp: \lin, label: "retrig", sel: #["—", "R"]);
	// §1.2 the module roles: 22 controls for nine oscillators, because five roles
	// are shared by two or three modules each. oscMode / oscModeB ship GENERIC
	// labels — unitSpecs is keyed by UNIT, not by variant, so one entry cannot
	// carry nine label sets and the card relabels them from §1.2 per `osc`.
	sp[\oscPw]      = (min: 0.02, max: 0.98, warp: \lin, label: "pw");
	sp[\oscPwB]     = (min: 0.02, max: 0.98, warp: \lin, label: "pw B");
	sp[\oscSkew]    = (min: -1, max: 1, warp: \lin, label: "skew");
	sp[\oscFold]    = (min: 0, max: 1, warp: \lin, label: "fold");
	sp[\oscSync]    = (min: 0, max: 60, warp: \lin, unit: "st", label: "sync");
	sp[\oscPulse]   = (min: 0, max: 1, warp: \lin, label: "pulse");
	sp[\oscSaw]     = (min: 0, max: 1, warp: \lin, label: "saw");
	sp[\oscTri]     = (min: 0, max: 1, warp: \lin, label: "tri");
	sp[\oscMode]    = (min: 0, max: 8, warp: \lin, label: "wave",
		sel: #["0", "1", "2", "3", "4", "5", "6", "7", "8"]);
	sp[\oscModeB]   = (min: 0, max: 8, warp: \lin, label: "wave B",
		sel: #["0", "1", "2", "3", "4", "5", "6", "7", "8"]);
	sp[\oscShape]   = (min: 0, max: 1, warp: \lin, label: "shape");
	sp[\oscFormant] = (min: 1, max: 9, warp: \lin, label: "formant");
	sp[\oscFb]      = (min: 0, max: 1, warp: \lin, label: "feedback");
	sp[\oscDetune]  = (min: 0, max: 1, warp: \lin, label: "spread");
	sp[\oscSkirt]   = (min: 0, max: 1, warp: \lin, label: "skirt");
	// Swarm's Waveform is a CHOOSER applied to all eight voices, not a saw↔sine
	// morph; the entries are invented, Bitwig prints «[various waves]»
	sp[\oscWave]    = (min: 0, max: 7, warp: \lin, label: "wave",
		sel: #["0", "1", "2", "3", "4", "5", "6", "7"]);
	sp[\oscFm]      = (min: 0, max: 1, warp: \lin, label: "fm");
	sp[\oscPwm]     = (min: 0, max: 1, warp: \lin, label: "pwm");
	sp[\oscPitchB]  = (min: -48, max: 48, warp: \lin, unit: "st", label: "pitch B");
	sp[\oscLvlA]    = (min: 0, max: 1, warp: \lin, label: "A");
	sp[\oscLvlB]    = (min: 0, max: 1, warp: \lin, label: "B");
	sp[\oscLvlRm]   = (min: 0, max: 1, warp: \lin, label: "RM");
	// §1.3 sub and noise — both blends are CROSSFADES, not sums
	sp[\sub]        = (min: 0, max: 1, warp: \lin, label: "sub");
	sp[\subWave]    = (min: 0, max: 4, warp: \lin, label: "sub wave",
		sel: #["SIN", "HALF", "TRI", "P50", "P25"]);
	sp[\subOct]     = (min: 0, max: 2, warp: \lin, label: "oct", sel: #["0", "−1", "−2"]);
	sp[\subSync]    = (min: 0, max: 1, warp: \lin, label: "sync", sel: #["—", "SYNC"]);
	sp[\pm]         = (min: 0, max: 8, warp: \lin, label: "pm");          // shown as 0…800 %
	sp[\noise]      = (min: 0, max: 1, warp: \lin, label: "noise");
	// §1.4 high-pass, §1.5 filter slot, §1.6 FEG: the §flt table shared with
	// polysynthU (~f2FltSpecs), so the two schemas cannot drift. It carries the
	// six Polysynth controls the union adds here — hpMode / hpRes (the slope and
	// resonance Bitwig's Polymer panel does not have: F2's wiring, §7 Q22),
	// filtFm, shaper / shaperMode, fVel — and the generic fltMode / fltMode2
	// labels the card relabels per `filt` from §1.5.
	sp.putAll(topEnvironment[\f2FltSpecs]);
	// §1.7 envelope slot — the AEG: the §env table shared with the other two
	// units (~f2EnvSpecs). atk / dec / sus / rel are the CONTRACT names, so a
	// preset's own ADSR reaches the slot unprefixed (the polysynthU rule). The
	// three curve knobs are SC-native −8…8 now, the sampler's units: the −1…1
	// Bitwig storage this unit shipped is REINTERPRETED, not rewritten — the
	// keys keep their names so there is no idempotent gate, the values never
	// sounded (declared, unread) and −1…1 ⊂ −8…8 (ENVELOPE.md §4.3, §5 Q2).
	sp.putAll(topEnvironment[\f2EnvSpecs]);
	// §1.8 pitch, glide, output. `pitch` transposes BEFORE everything — the sub,
	// the PM ratio and the keytracking all follow it, where `oscPitch` moves the
	// slot oscillator alone.
	sp[\pitch]      = (min: -48, max: 48, warp: \lin, unit: "st", label: "pitch");
	sp[\glide]      = (min: 0, max: 10, warp: \lin, unit: "s", label: "glide");
	// `legatoOn` and not §1.8's `legato`: bare `legato` is one of sclang's own Event
	// keys and lives in SKIP_PARAMS / skipParams, which both compilers apply to the
	// name after the last dot — `polymer.legato` would be dropped from ~defs, from
	// the live-bus init and from f2map, so the control would sit at its arg default
	// for ever and no preset could ever move it (§1.9's naming rules).
	sp[\legatoOn]   = (min: 0, max: 1, warp: \lin, label: "legato", sel: #["—", "L"]);
	sp[\vel]        = (min: 0, max: 1, warp: \lin, label: "vel");
	sp[\gain]       = (min: -24, max: 24, warp: \lin, unit: "dB", label: "gain");
	sp[\pan]        = (min: -1, max: 1, warp: \lin, label: "pan");
	sp[\amp]        = (min: 0, max: 1, warp: \lin, label: "out");
	// the note pitch (a group broadcast — no knob; exported for completeness)
	sp[\freq]       = (min: 20, max: 20000, warp: \exp, unit: "Hz", label: "freq");
	sp
}.value;
// `curve` changes no graph — it is a drawn point list \f2voice will resolve to a
// buffer at spawn — so it must not enter the variant name: polymerU__osc_scrawl
// is ONE variant however many different curves the session draws.
~f2UnitOptsRes[\polymerU] = #[\curve];

// §6.3/§6.6/§6.7 which oscillators have an arm, DECLARED beside ~f2FltBuilt and
// ~f2EnvBuilt rather than hidden as a literal inside the generator — the mirror
// of the front's UNIT_BUILT.polymerU.osc, and the list the SC ≡ TS check reads.
// Order matters twice: the FIRST entry is what an unbuilt value falls back to
// and what the card prints after the arrow, and it must stay the schema default
// (`union`), so a keyless save builds the base def. All NINE since §curve —
// `scrawl` was the last, and it waited on the drawn point list rather than on
// DSP (§6.8). No oscillator falls back on this unit any more.
~f2OscBuilt = (polymerU: #[\union, \saw, \sine, \tri, \pulse, \phase1, \swarm, \bite, \scrawl]);

// Generator: opts (osc: 'bite', filt: 'ripple', env: 'pluck') → SynthDef `name`
// (~f2UnitVariantName: polymerU__env_pluck__filt_ripple__osc_bite). Per voice
// (§2), with everything a later stage owns left out:
//   noteF = Lag(freq, glide) × pitch → oscF = noteF × n/d × 2^(oscPitch/12)
//   + oscHz (∓oscHz on the right channel under oscStereo; n = 0 zeroes the
//   pitch bus and leaves oscHz in sole control) → the SUB at noteF × 2^subOct
//   (§2.4: one phasor, five shapes) → a Phasor at oscF × 2^(sync/12) reset by
//   the note, by its own master's wrap and by the sub's under subSync, its
//   phase offset by pm × sub → ONE oscillator model built on that phase (§2.2:
//   the saw bank, the triangle bank, SinOsc, or a bank of its own) → the sub
//   and the noise gated by fSubNoise and crossfaded in (§2 items 2 and 4) → HP
//   (hpMode / hpRes) → drive → cutoff summed in the PITCH domain (keytrack ×
//   FEG) → the §flt slot (filter FM → ld ladder or poly core → bypass → shaper) →
//   AEG × vel × gain × amp → Balance2(pan) → LeakDC(0.9993) → Sanitize → Out.
~f2UnitGen[\polymerU] = { |opts, name|
	var oget = { |k, d| ((opts !? { |o| o[k] }) ? d).asSymbol };
	var warn = topEnvironment[\f2UnitWarnOnce];
	var oscM = oget.(\osc, 'union');
	// §flt the filter model through the shared resolver: all eleven build; a
	// value outside the list falls back to `ld` (this unit's own) with one warning
	var fltM = topEnvironment[\f2FltResolve].value(\polymerU, opts, name);
	var fltSlot = topEnvironment[\f2FltSlot];
	var fegF = topEnvironment[\f2Feg];
	// §env the envelope model through the shared resolver: the union's five are
	// built, `shot` / `segments` fall back to `adsr` (this unit's own) with the
	// one warning
	var envM = topEnvironment[\f2EnvResolve].value(\polymerU, opts, name);
	var aegF = topEnvironment[\f2Aeg];
	var trigF = topEnvironment[\f2AegTrig];
	// Which §6 stage brings each advertised value that is still owed. The
	// fallback warning has to name it: «not built» on its own reads as a bug to
	// whoever hears a saw where they picked a Swarm.
	var oscBuilt = (topEnvironment[\f2OscBuilt][\polymerU]) ? #[\union];
	// empty since §curve landed Scrawl: every advertised oscillator has an arm, so
	// the only value that can reach `fell` now is one the schema never offered
	var oscStage = ();
	var fell = { |slot, want, built, stage|
		warn.value(("pm_" ++ slot ++ "_" ++ want).asSymbol,
			"⚠ [f2 pm] %: % is % — % is built as %".format(slot, want,
				(stage !? { |st| "not built yet (POLYMER.md §6." ++ st ++ ")" })
					? "not an advertised value", name, built));
	};
	var tbl   = topEnvironment[\f2PolyTables];
	var tBase = ((tbl !? { tbl[\base] }) ? 0).asInteger;
	var tLast = (((tbl !? { tbl[\n] }) ? 12).asInteger - 1).max(0);
	// the triangle bank (~f2PolymerTables, levels cut like the saw bank's so the
	// two share `lvl`), and its half-sine half one bank further up — the sub's
	// second shape (§2.4) and Bite's HALF core read the same twelve levels
	var pmTbl = topEnvironment[\f2PolymerTables];
	var triBase = ((pmTbl !? { pmTbl[\base] }) ? 0).asInteger;
	var hBase = triBase + (((pmTbl !? { pmTbl[\n] }) ? 12).asInteger);
	var def, bytes;
	if (tbl.isNil) { "⚠ [f2 pm] ~f2PolyTables is not allocated — polymerU reads buffer 0".postln };
	if (pmTbl.isNil) { "⚠ [f2 pm] ~f2PolymerTables is not allocated — the triangle reads buffer 0".postln };
	// A value from a later stage must not build a silent or a wrong graph: fall
	// back to the slot's schema DEFAULT — `union`, built since §6.2 — and say so
	// once (§6.1). The front's UNIT_BUILT leads each list with the model this
	// branch falls back to and prints it after the arrow («bite → union»), so the
	// two must move together: the target here changed from `saw` to `union` in
	// the same change that put `union` first there.
	if (oscBuilt.includes(oscM).not) { fell.('osc', oscM, 'union', oscStage[oscM]); oscM = 'union' };
	def = SynthDef(name.asSymbol, { |out = 0, gate = 0, t_trig = 0, amp = 0.5, i_free = 2,
		tel_bus = 0, telId = 0, freq = 220, vel = 1,
		// §curve the TWO PRODUCTS of one render, both ENGINE ARGS set by \f2voice
		// from the card's `curve` opt (~f2CurveRes) and never knobs — they join
		// tel_bus / telId, so §1.9's 81-control budget does not move. `curveBuf` is
		// the BASE of 12 consecutive mip buffers `osc: scrawl` reads; `shapeBuf` the
		// single 16385-frame drawing `env: segments` reads. -1 on both is «nothing
		// rendered yet», and each arm says what it does with that.
		curveBuf = -1, shapeBuf = -1,
		// §1.1 the shared block every oscillator model reads
		oscRatioN = 1, oscRatioD = 1, oscPitch = 0, oscHz = 0, oscStereo = 0, oscRetrig = 1,
		// §1.2 the module roles — 22 controls for nine oscillators, because five
		// roles are shared by two or three modules each. All 22 are read now that
		// Phase-1, Swarm and Bite are built; `scrawl`'s drawn cycle is the one
		// thing still owed, and it is a `curve` resource and not a knob (§6.8)
		oscPw = 0.5, oscPwB = 0.5, oscSkew = 0, oscFold = 0, oscSync = 0,
		oscPulse = 0, oscSaw = 1, oscTri = 0, oscMode = 0, oscModeB = 0,
		oscShape = 0, oscFormant = 1, oscFb = 0, oscDetune = 0.2, oscSkirt = 0.5, oscWave = 0,
		oscFm = 0, oscPwm = 0, oscPitchB = 0, oscLvlA = 1, oscLvlB = 0, oscLvlRm = 0,
		// §1.3 sub and noise — fixed hardware, built on every variant
		sub = 0, subWave = 0, subOct = 1, subSync = 0, pm = 0, noise = 0,
		// §1.4 high-pass — §flt adds Polysynth's slope and resonance; hpMode 1 /
		// hpRes 0 IS stage 1's fixed HPF, so a polymer save keeps it where it was
		hpMode = 1, hpFreq = 19.4, hpRes = 0,
		// §1.5 filter slot — the §flt union: filtFm, shaper and shaperMode are
		// Polysynth's, at defaults that multiply by one / select the dry path
		filtOn = 1, fltMode = 0, drive = 0, cut = 2000, res = 0, keytrack = 0, egAmt = 0, filtFm = 0,
		shaper = 0, shaperMode = 0, resLimit = 1, fltLin = 0, fltMode2 = 0,
		fltFbGain = 0, fltFbCut = 0.5, fltColor = 0, fltVowel = 0, bellGain = 6,
		// §1.6 FEG — fVel is Polysynth's velocity depth, ×1 exactly at 0
		fAtk = 0.01, fDec = 0.3, fSus = 0.5, fRel = 0.3, fVel = 0, fEnvModel = 0, fSubNoise = 0,
		// §1.7 envelope slot — the AEG, the §env union (ENVELOPE.md §1.3): the
		// curve defaults move 0 → −4 (SC-native now; inert under envModel 0 =
		// Analog, this unit's own default, and −4 IS the curve the fixed Env.adsr
		// had), hold / fadeIn / fadeOut are NEW args read by no model a keyless
		// save resolves to
		atk = 0.005, hold = 0.001, dec = 0.2, sus = 0.8, rel = 0.3, envModel = 0,
		atkC = -4, decC = -4, relC = -4, envLoop = 0, fadeIn = 0.001, fadeOut = 0.005,
		// §1.8 pitch, glide, output
		pitch = 0, glide = 0, legatoOn = 0, gain = 0, pan = 0|
		var g     = gate;
		var velC  = vel.clip(0, 1);
		var sdur  = SampleDur.ir;
		// every frequency in the graph is bounded by this, cutoffs included: HPF,
		// MoogFF and the phase accumulator all go unstable or NaN above it, and
		// Bitwig's own 33.5 kHz top end is past Nyquist on every rate F2 runs at.
		// Clipping the knob is not re-scaling it — the RANGE stays Bitwig's.
		var nyq   = SampleRate.ir * 0.45;
		// §1.7 the AEG, and it is what keeps the voice alive (doneAction: i_free —
		// the voice pool owns lifetime, which is why Bitwig's Affect Voice Lifetime
		// toggle has nothing to switch here). Through the shared fragment (~f2Aeg,
		// §env): at `adsr` / envModel A this is the Env.adsr(…, 1, -4) this unit
		// always built, at ar as it always was; a synth one-shot holds `hold` as
		// its body (ENVELOPE.md §2.8). `aegK` is the kr copy the legato `held` and
		// the telemetry read.
		var aegR  = aegF.(envM, g, { trigF.(g, t_trig) },
			(atk: atk, hold: hold, dec: dec, sus: sus, rel: rel, atkC: atkC, decC: decC, relC: relC,
				envModel: envModel, envLoop: envLoop, fadeIn: fadeIn, fadeOut: fadeOut,
				shapeBuf: shapeBuf),
			hold.clip(0.001, 8), #[[], [], []], i_free);
		var aeg   = aegR[\aeg];
		var aegK  = aegR[\aegK];
		// §1.6 the FEG — the shared ~f2Feg (kr, curve −4, does NOT hold the voice
		// alive, vel-scaled by fVel). `fSubNoise` reads it as a VCA on the sub and
		// the noise below, before either crossfade (§2 item 4).
		var feg   = fegF.(g, fAtk, fDec, fSus, fRel, fVel, vel);
		// §2 decision 6: `legatoOn` applies the glide to OVERLAPPING notes only. F2
		// has no note-off overlap at the SynthDef level, so v1 reads it off the
		// envelope — a gate that rose while the previous note was still sounding
		// glides, a gate that rose from silence starts in tune. Without it every
		// detached note slides up from whatever this voice played last.
		var held  = Latch.kr(Delay1.kr(aegK) > 0.001, Trig.kr(g));
		var glideE = glide.clip(0, 10) * (1 - ((legatoOn > 0.5) * (1 - held)));
		var noteF = Lag.kr(freq.max(1), glideE) * pitch.clip(-48, 48).midiratio;
		// §1.1 `oscRatioN = 0` ZEROES the pitch bus — Bitwig's own fixed-frequency
		// oscillator, with `oscHz` left in sole control — so the ratio has to
		// multiply BEFORE the Hz offset is added, never after. `oscStereo` is two
		// real accumulators (L +oscHz, R −oscHz), not a pan: the right channel is
		// built here and carried through the whole oscillator.
		var ratio = oscRatioN.round(1).clip(0, 99) / oscRatioD.round(1).clip(1, 99);
		var det   = oscHz.clip(-100, 100) * [1, 1 - (2 * (oscStereo > 0.5))];
		var oscF  = ((noteF * ratio * oscPitch.clip(-48, 48).midiratio) + det).clip(nyq.neg, nyq);
		// retrig: the polysynthU idiom — one sample on every gate front and every
		// t_trig, gated by `oscRetrig` (ON by default, knowingly inverted from
		// Bitwig's pre-cord: F2 notes are short and gridded, and a phase-coherent
		// attack is what makes two cells sound like the same note)
		var rtA   = Trig1.ar(K2A.ar(Trig.kr(g) + Trig.kr(t_trig)), sdur);
		var rt    = rtA * (oscRetrig > 0.5);
		// §2.1 the shared machinery. `oscSync` is Pulse's and Saw's alone (§1.2.3 /
		// §1.2.4 — Sine, Triangle and Union do not carry the knob), so only those
		// two build the silent master: it runs the audible wave 2^(sync/12) faster
		// and resets it once per NOTE period, so the perceived pitch does not move
		// and a formant sweeps up. Built out, not multiplied by zero, so a model
		// that does not read the control does not pay for it either. The SECOND
		// reset is the sub's wrap under `subSync`, and it is built for every model
		// because the sub is fixed hardware (§1.3): it is below, with the sub.
		var hasSync = #[\saw, \pulse].includes(oscM);
		var syncR  = if (hasSync) { oscSync.clip(0, 60).midiratio } { 1 };
		var readF  = oscF * syncR;
		var wrap   = if (hasSync) {
			var mph = Phasor.ar(rt, oscF * sdur, 0, 1);
			((mph - Delay1.ar(mph)) < 0) * (oscSync > 0.005)
		} { 0 };
		// the mip level comes off the READ frequency, and that frequency is SIGNED:
		// the right channel of a stereo-detuned oscillator with `oscRatioN = 0` runs
		// backwards, log2 of a negative number is NaN, and a NaN bufnum reads
		// silence for the rest of the voice's life. The rule is
		// the same for every read below: the level follows the WORST-CASE rate the
		// table is read at, never the nominal pitch — a phase warp reads its steep
		// segment that much faster, and a table's own partials fold if it is not.
		var lvlOf  = { |rate| ((rate.abs.max(20) / 27.5).log2).floor.clip(0, tLast) };
		// ── §1.3 / §2.4 THE SUB: Polymer's second voice, three jobs at once ────
		// It is blended into the mix, it is the PM modulator for the slot, and it
		// is the hard-sync master — which is why `subOct` moves the sync ratio and
		// the PM ratio as well as the sub's own pitch, and why it is built on every
		// variant whatever the `osc` menu says. It follows `noteF` and NOT `oscF`:
		// `pitch` transposes the whole voice, `oscPitch` / the ratio / `oscHz` move
		// the slot oscillator alone (§1.8), and that gap is exactly what `subSync`
		// turns into a formant control.
		// The octave is the SELECT INDEX 0/1/2 and the transpose is its negation —
		// the menu reads `0 −1 −2` (§1.3) and the stored value is the index, so a
		// preset that says 2 means two octaves DOWN.
		var subF   = noteF * (2 ** subOct.round(1).clip(0, 2).neg);
		var subL   = lvlOf.(subF);
		// the sub's own accumulator, reset by the note like the slot's so two cells
		// playing one note are one sound (§2.1's retrig rationale). Its rate is
		// always POSITIVE — the sub reads none of `oscRatioN` / `oscHz` /
		// `oscStereo`, so it cannot run backwards — which is why the wrap test is
		// §2's `< 0` as written and not the direction-blind |Δφ| > ½ the slot's own
		// masters need.
		var sph    = Phasor.ar(rt, subF * sdur, 0, 1);
		var sph2pi = sph * 2pi;
		// §2.4's five shapes, ONE live Select over ONE phasor and the three banks:
		// sine, half-sine, triangle, pulse 50 %, pulse 25 %, in Bitwig's own order
		// (§1.3 `✓ [STR]`). The two banked reads are one `Osc` whose BUFNUM is
		// selected and the two pulses are one shifted saw read whose SHIFT is
		// selected, so five shapes cost three oscillators rather than six — the
		// same discipline as §2.2's mode lists, which are taps on one core. The
		// pulses are the `\pulse` arm's two reads in ITS order (`(sph + 1 − pw)`,
		// because this bank's saw FALLS): §2.4's `saw(p) − saw(p + 0.25)` is the
		// rising-saw form and comes out positive for ¾ of the cycle, a 75 % pulse.
		// Duty ¼ nulls every 4th harmonic either way, which is what Bitwig names
		// the shape for («pulse without each 4th harmonic»), but only the first-pw
		// order is the 25 % pulse it also calls it. Sine is `SinOsc` and not the
		// triangle bank's top level (which IS a unit sine): the sub is the PM
		// modulator, and a table read carries its own interpolation error into
		// every sideband.
		var subIdx = subWave.round(1).clip(0, 4);
		var subBuf = Select.kr(subIdx, [tBase + subL, hBase + subL, triBase + subL,
			tBase + subL, tBase + subL]);
		var subSh  = Select.kr(subIdx, [0, 0, 0, 0.5, 0.75]);
		var subRd  = Osc.ar(subBuf, 0, sph2pi);
		var subPul = subRd - Osc.ar(tBase + subL, 0, ((sph + subSh) % 1) * 2pi);
		var subSig = Select.ar(subIdx, [SinOsc.ar(0, sph2pi), subRd, subRd, subPul, subPul]);
		// §2.1: phase modulation is added to the READ PHASE, never to the frequency
		// — that is what keeps the pitch stable and makes it phase modulation and
		// not vibrato. `pm` is in CYCLES (0…8 = Bitwig's 0…800 %), so one unit of
		// sub output at `pm` 1 is one whole cycle of deviation.
		var pmD    = pm.clip(0, 8);
		var pmP    = pmD * subSig;
		// §2's `rst`: the note trigger, the model's own sync master (Pulse and Saw),
		// and the sub's wrap under `subSync`. Every accumulator the model builds on
		// the NOTE pitch takes this, so hard sync reaches Swarm's eight lanes too;
		// Bite's B core keeps its own reset because it carries its own pitch. At
		// `subSync` 0 the term is exactly 0.0 and the trigger is what it always was.
		var subRst = ((sph - Delay1.ar(sph)) < 0) * (subSync > 0.5);
		var rst    = rt + wrap + subRst;
		var ph     = (Phasor.ar(rst, readF * sdur, 0, 1) + pmP).wrap(0, 1);
		// §2.1's mip rule under modulation: `readF` is the rate the phasor runs at,
		// `modF` the fastest the TABLE is actually read at, and PM is what separates
		// them — `pm` cycles of deviation per sub period read the wave (1 + pm)
		// times faster at the steepest point. Choosing the level from the nominal
		// pitch is the classic mistake: the table's own partials fold and the note
		// grows an octave-wrong buzz that only appears when the PM knob moves.
		var modF   = readF * (1 + pmD);
		var lvl    = lvlOf.(modF);
		// §2.2 the ONE model of this variant, built on `ph` — not a Select over
		// five, which would run all five for every voice.
		var oscSig = switch (oscM,
			\saw, {
				// §1.2.4 one read of the saw bank. Shape is a monotone phase bend
				// applied BEFORE the read, so the endpoints stay pinned and the wrap
				// step stays exactly 2 — bending the SIGNAL instead would undo the
				// band-limiting the bank exists for. Bitwig's own word for the amount
				// is «slightly», hence the half-octave clamp on the exponent rather
				// than the full ±1 the knob spans. At Shape 0 the read is `ph` ITSELF,
				// selected, not `ph ** 1`: libm's pow is not the identity to the last
				// bit at exponent 1, and Union at saw 1 / pulse 0 / tri 0 is this
				// read bit for bit only if nothing sits between the phasor and the
				// table (§6.2's acceptance test measured 1.2e-7 through the pow).
				var bend = 2 ** (oscSkew.clip(-1, 1) * -0.5);
				var bent = Select.ar(oscSkew.abs > 1e-6, [ph, ph ** bend]);
				Osc.ar(tBase + lvl, 0, bent * 2pi)
			},
			\sine, {
				// §1.2.1 a sine on the shared phase — SinOsc.ar(0, ph·2π), not a
				// free-running SinOsc.ar(f): retrigger, hard sync and the sub's phase
				// modulation all act on `ph`, and a sine with its own accumulator would
				// ignore all three.
				// Skew moves WHERE IN THE CYCLE THE PEAK SITS: a two-segment linear
				// phase map through (a, ¼), a = ¼ the identity. a = ¼·3^skew, so the
				// fast segment is about as steep at either end of the knob (+1: the
				// rise stretched over ¾ and the fall through the trough squeezed into
				// the last quarter — Bitwig's «kinked sawtooth»; −1: a 1/12-cycle rise
				// then the slow descent — the «ramp»). Fold is a REFLECTION (fold2),
				// never wrap2: gain ahead of a mirror at ±1, so peaks past full scale
				// come back as the extra humps Bitwig describes. Both are memoryless
				// in phase, so they are anti-aliased by evaluating at four sub-sample
				// phases and weight-summing [0.1 0.4 0.4 0.1] — an oversampled read
				// with no oversampling machinery. That sum is not the identity on a
				// pure sine (it is a short low-pass), so skew = fold = 0 SELECTS the
				// plain read instead of going through it: the fast path, and by far
				// the commonest use.
				var skew   = oscSkew.clip(-1, 1);
				var fold   = oscFold.clip(0, 1);
				var a      = 0.25 * (3 ** skew);
				var g      = 1 + (fold * 4);
				var inc    = readF * sdur;
				var pure   = SinOsc.ar(0, ph * 2pi);
				var shaped = Mix.fill(4, { |i|
					var p = (ph + (inc * ((i - 1.5) * 0.25))) % 1;
					var w = (0.25 * (p / a).min(1)) + (0.75 * ((p - a) / (1 - a)).max(0));
					(SinOsc.ar(0, w * 2pi) * g).fold2(1) * #[0.1, 0.4, 0.4, 0.1][i]
				});
				Select.ar((skew.abs + fold) > 1e-4, [pure, shaped])
			},
			\tri, {
				// §1.2.2 a read of the triangle bank. Skew is the RISE FRACTION s =
				// ½ + ½·skew: the table's rising half-cycle (¾ → 1¼) is read over a
				// span of s and its falling half over the remaining 1 − s, a
				// two-segment phase map that keeps the mean at 0 for every s (each
				// segment averages one zero-mean half-cycle). The cycle boundary sits
				// in the MIDDLE of the rise (`p` is `ph` advanced by s/2), so a note
				// starts at zero and rising like every other model here — not at the
				// trough, which is a −1 step into the blocker on every retrigger —
				// and at s = ½ the map is `ph` + 1: the same table read as Union's
				// triangle leg. The clamp is the pulse's: at 0 or 1 a segment has no
				// length to read over. The level follows the steep segment's read
				// rate, 0.5/min(s, 1−s) × f —
				// the worst case, so at full skew the slow segment reads a duller
				// table than it could, which is the price of the steep one not
				// folding its partials. Fold: fold2(x, 1) IS a triangle function of
				// x — for this bank's sine-phased triangle exactly T(x/4) — so the
				// fold is a second read of the band-limited table at tri·g/4 instead
				// of an arithmetic fold, and inherits the table's band-limiting; its
				// level follows that read's own rate, g times the first one. At high
				// levels the table is a sine and the fold a sine shaper, so the fold
				// read is not the identity at g = 1: it is crossfaded in over the
				// first 5 % of the knob so that fold 0 is the plain read exactly.
				var s      = (0.5 + (0.5 * oscSkew.clip(-1, 1))).clip(0.02, 0.98);
				var g      = 1 + (oscFold.clip(0, 1) * 4);
				var slope  = 0.5 / s.min(1 - s);
				var lvlT   = lvlOf.(modF * slope);
				var lvlF   = lvlOf.(modF * slope * g);
				var p      = (ph + (s * 0.5)) % 1;
				var w      = 0.75 + (0.5 * (p / s).min(1)) + (0.5 * ((p - s) / (1 - s)).max(0));
				var tri    = Osc.ar(triBase + lvlT, 0, w * 2pi);
				var folded = Osc.ar(triBase + lvlF, 0, tri * g * 0.25 * 2pi);
				tri + ((folded - tri) * (oscFold * 20).clip(0, 1))
			},
			\pulse, {
				// §1.2.3 two reads of the saw bank: saw(ph) − saw(ph − pw) is the pulse
				// positive for the FIRST `pw` of the cycle — band-limited at ANY width,
				// audio-rate PWM included, with no BLEP timing logic. Which read is
				// subtracted from which is the polarity, and the bank decides it: this
				// saw FALLS (sine1's Σ sin(kφ)/k starts at +1), so §2.2's
				// `saw(ph) − saw(ph + pw)`, written for a rising saw, comes out
				// positive for 1 − pw of the cycle — the ø_pulse reading §1.2.3 says
				// Pulse does NOT take. A magnitude spectrum cannot tell the two apart
				// (duty pw and 1 − pw null the same harmonics); only the wave can, and
				// it was measured positive for 0.746 of the cycle at pw ¼ before this
				// order was fixed. Positive at the START of the cycle rather than at its
				// end because that is what a comparator on this falling saw gives, and
				// it keeps the pulse's fundamental in phase with the saw's at pw ½ (a
				// pulse positive for the LAST pw is anti-phase there, which thins
				// Union). The bank's saw has no mean, so neither does the difference:
				// it is the ±1 pulse with its mean (2·pw − 1) already removed — the DC
				// term Union keeps (§2.2). Duty 1/n nulls every n-th harmonic.
				var pw = oscPw.clip(0.02, 0.98);
				Osc.ar(tBase + lvl, 0, ph * 2pi) - Osc.ar(tBase + lvl, 0, ((ph + (1 - pw)) % 1) * 2pi)
			},
			\union, {
				// §1.2.5 ONE phasor, three reads — a MIXER, not a morph: the saw read,
				// the pulse (the `\pulse` arm's two reads, in ITS order — see there for
				// why the shifted read is the one subtracted) and the triangle bank,
				// summed by three levels through a 4 ms lag so a level jump is a ramp
				// and not a click (the one shared core is F2's, §7 Q21). The saw's and
				// the triangle's fundamentals are in phase because both banks are
				// sine-phased, and the pulse's joins them at pw ½. The pulse is
				// the ±1 pulse WITH its mean (2·pw − 1) — the one place that DC is
				// deliberately kept: a step on the pulse width or on the pulse level
				// moves the mean, and the 0.9993 blocker at the unit output lets it
				// slide back over ~30 ms, which is F2's mechanism for Bitwig's
				// documented «smooth analog drift». Nothing is normalised (§7 Q4): all
				// three at 1 is ±3, and `gain` / `amp` are where that is dealt with.
				// At saw 1 / pulse 0 / tri 0 this is the `saw` model bit for bit.
				var pw  = oscPw.clip(0.02, 0.98);
				var lS  = Lag.kr(oscSaw.clip(0, 1), 0.004);
				var lP  = Lag.kr(oscPulse.clip(0, 1), 0.004);
				var lT  = Lag.kr(oscTri.clip(0, 1), 0.004);
				var saw = Osc.ar(tBase + lvl, 0, ph * 2pi);
				var pul = saw - Osc.ar(tBase + lvl, 0, ((ph + (1 - pw)) % 1) * 2pi) + ((2 * pw) - 1);
				var tri = Osc.ar(triBase + lvl, 0, ph * 2pi);
				(saw * lS) + (pul * lP) + (tri * lT)
			},
			\phase1, {
				// §1.2.6 phase distortion: ONE sine read through a monotone phase
				// warp. Four controls and no more — Algorithm (`oscMode`), Shape
				// (`oscShape`), Formant (`oscFormant`), Feedback (`oscFb`). There is
				// no Phase knob on this module (§7 Q5).
				//   out = sin(2π·(w(x) + (F−1)·x).wrap(0,1)),  w = x + a·(pw(x) − x)
				// THE FORMANT TERM IS ADDED, NOT MULTIPLIED, and that is a deviation
				// from §2.2's `sin(2π·F·w(x))` forced by §6 stage 6's own acceptance
				// number. Multiplying puts F cycles INSIDE the warp, so the warp's
				// slow segments drag the spectral peak down with Shape: measured on
				// the multiplied form, Formant 9 peaked on the SEVENTH harmonic at
				// Shape 0.5 and the sixth at 0.85 — the peak is not parked anywhere,
				// which is the one thing §1.2.6 says the control does. Adding (F−1)
				// UNDISTORTED cycles is §1.2.6's own wording read literally
				// («additional sine cycles within the waveshape») and makes the model
				// a carrier at exactly F·f0 phase-modulated by the deviation w(x) − x,
				// whose sidebands are symmetric about it. Everything else §2.2 says
				// holds word for word: the phase still reaches F, so it is wrapped
				// BEFORE it is scaled to radians (18π through SinOsc's radians-to-
				// index conversion is where the precision goes), and it is exactly
				// periodic for integer F because `w` is monotone and endpoint-
				// anchored — a non-integer F would put a step at the cycle boundary
				// and the model would buzz at the note rate.
				// The five algorithms are five sets of three x-KNOTS selected at kr
				// over ONE ar warp, not five warps selected at ar: the y-knots are
				// fixed at 0 ¼ ½ ¾ 1 for all five, so §2.2's Select.ar over five
				// warps is five sets of three NUMBERS — the affordability rule kept
				// («a mode list is selected because it is a tap on one already-
				// computed core»), and a fifth of the audio-rate cost.
				// F2 ships five and says so on the card (§7 Q5 — no source names
				// Bitwig's, and `phase-1.algorithm.desc` ends in the colon the dump
				// truncates), so what is fixed here is the SHAPE of each warp:
				//   0 SAW the first half-cycle inside 12 %; 1 SQR a bend at each zero
				//   crossing; 2 PLS the whole cycle inside the first 12 % then a
				//   crawl — the narrowest bend of the five, where the limiter bites
				//   first; 3 DBL SAW mirrored, the bend at the END; 4 RES the cycle
				//   crammed into a window in the middle, the CZ resonant family.
				var alg  = oscMode.round(1).clip(0, 4);
				// Formant is an INTEGER harmonic 1…9 (§1.2.6), and KEYTRACKED the way
				// the mip level is: capped at the highest harmonic still under
				// 0.45·SR. Formant 9 on a 3 kHz note asks for 27 kHz — the
				// undistorted source is already above Nyquist and no amount of bend
				// limiting can produce it. That cap STEPS at a note pitch, which a
				// glide crosses audibly; the alternative makes F fractional and puts
				// a buzz at the note rate into every high note, so the step is the
				// lesser fault. `readF` and not `modF`: PM adds sidebands, it does
				// not move the carrier at F·f0.
				var fmt  = oscFormant.round(1).clip(1, 9)
					.min((nyq / readF.abs.max(1)).floor.max(1));
				var x1   = Select.kr(alg, [0.06, 0.06, 0.04, 0.44, 0.30]);
				var x2   = Select.kr(alg, [0.12, 0.44, 0.08, 0.88, 0.36]);
				var x3   = Select.kr(alg, [0.56, 0.50, 0.12, 0.94, 0.42]);
				// the narrowest segment each knot set leaves — the only thing the
				// bend limit needs to know about the warp
				var gMin = Select.kr(alg, [0.06, 0.06, 0.04, 0.06, 0.06]);
				var g0   = x1, g1 = x2 - x1, g2 = x3 - x2, g3 = 1 - x3;
				var s0   = 0.25 / g0, s1 = 0.25 / g1, s2 = 0.25 / g2, s3 = 0.25 / g3;
				// ANTI-ALIASING is §2.2's keytracked bend limiting, as a ceiling on
				// Shape rather than a floor on the breakpoint — the same law. The
				// steepest segment climbs ¼ of the cycle in `gMin`, so the worst
				// instantaneous frequency is f·(F + a·(0.25/gMin − 1)) and that has
				// to stay under 0.45·SR. `readF`, not the note pitch: a synced or
				// ratio'd oscillator reads faster than the note and it is the READ
				// rate the warp bends. `.max(1e-6)` because a warp whose worst slope
				// is 1 is the identity and has no bend to limit; `.max(1)` because a
				// fixed-frequency oscillator at `oscRatioN` 0 with `oscHz` 0 reads at
				// 0 Hz and 0.45·SR/0 is inf. Shape stops moving where it would fold
				// partials back and never jumps, because the ceiling is continuous in
				// f, F and the algorithm.
				var aLim = ((nyq / readF.abs.max(1)) - fmt) / ((0.25 / gMin) - 1).max(1e-6);
				var a    = oscShape.clip(0, 1).min(aLim.clip(0, 1));
				// FEEDBACK is ONE self-substitution of the open-loop output into the
				// read phase — §2.1's `(ph + pm).wrap(0,1)` idiom — and NOT a
				// LocalIn/LocalOut loop. 1.33 ms of delay in an audio-rate phase path
				// detunes the feedback rather than deepening it: the sidebands would
				// land beside the harmonics instead of on them, and §7 Q18's control
				// block is not paid here. The substitution is a memoryless function
				// of `ph`, so it cannot run away however hard the knob is turned.
				// The depth spans 0.15 of a cycle, MEASURED and not chosen: self
				// phase modulation is a Bessel series, so past some index the carrier
				// returns and the sidebands get shallower again as the knob rises —
				// which would fail §6 stage 6's «deepens monotonically». Swept to
				// half a cycle on five (algorithm, Shape, Formant) corners the rms
				// bandwidth about the carrier stops rising at 0.35 of a cycle on the
				// gentle ones, 0.25 on the steepest warp and 0.15 on the deepest
				// patch; 0.15 is the floor of those five, so every one of them rises
				// all the way.
				var fb   = oscFb.clip(0, 1) * 0.15;
				// the warp: four clipped ramps summed. Branchless — a Select per
				// segment is four times the UGens and the same answer — and monotone
				// by construction, every slope positive and the pieces joined at the
				// knots. At a = 0 the whole sum is multiplied by exactly zero and `w`
				// is `ph` to the last bit: the algorithm's own UNDISTORTED SOURCE,
				// which is §6 stage 6's invariant (and note what it is NOT — at
				// Formant 5 it is a sine at 5·f0, not «a pure sine», which Bitwig
				// never promises).
				var warp = { |x|
					var pw = (s0 * x.clip(0, g0))
						+ (s1 * (x - x1).clip(0, g1))
						+ (s2 * (x - x2).clip(0, g2))
						+ (s3 * (x - x3).clip(0, g3));
					x + (a * (pw - x))
				};
				var read = { |x| SinOsc.ar(0, (warp.(x) + ((fmt - 1) * x)).wrap(0, 1) * 2pi) };
				var y0   = read.(ph);
				// at oscFb 0 the substituted phase is `ph` exactly and this IS y0 —
				// no Select needed to keep the feedback-off path clean, unlike the
				// sine model's oversampled read, which is a low-pass at rest
				read.((ph + (fb * y0)).wrap(0, 1))
			},
			\swarm, {
				// §1.2.7 the Grid's supersaw: EIGHT lanes, fixed — not a control, and
				// the third-party dataset that gives Swarm a 2…16 Voices knob is
				// synthetic. They sum to MONO; the only stereo Swarm can make is the
				// §1.1 block's `oscHz` + `oscStereo`, already the second channel of
				// `oscF`, so there is no width knob here.
				// THE DISTRIBUTION: the lanes sit at u = 2k/7 − 1, symmetric, the
				// outer pair at exactly ±1 so the widest voices land on ±`oscDetune`
				// and Skirt cannot change the WIDTH — the one thing Bitwig says it
				// does not do («fine-tunes the detuning distribution»). Skirt bends
				// them through sign(u)·|u|^p, p = 4^(2·skirt − 1): pushed to the rim
				// at 0, evenly spread at ½ (the default), clustered at the centre at
				// 1 with the outer pair still at the rim.
				// THE COHERENCE GAIN LAW is §2.2's, g = 1/(8(1−c) + √8·c), and it is
				// what §6 stage 6's «the level does not jump» measures: eight lanes in
				// phase are one signal eight times over and need 1/8; uncorrelated
				// they add in power and need 1/√8. A fixed 1/√8 blasts by 9.03 dB at
				// Spread 0 — that is the failure this law prevents. Skirt lives
				// INSIDE c because the same Spread with the lanes pulled in leaves
				// more of them in phase.
				// c REACHES 1 AT SPREAD 0.01, not §2.2's 0.25, and that is the one
				// number here that had to be measured. What decorrelates the lanes is
				// their PHASES — spread by c itself, and spread from the first sample
				// — not their frequencies, which only pull apart after they drift.
				// With §2.2's `min(detune·4, 1)` an 8 s note at Spread 0.02 came out
				// 8.6 dB below the same note at Spread 0, the level sliding down
				// through the note as the lanes unzipped. Full by half a cent — the
				// point where the lanes are detuned at all — holds the same sweep
				// inside 1 dB from 0.01 upward, and below it the lanes genuinely are
				// one sound (at ±0.05 cents the closest pair takes half a minute to
				// drift a cycle).
				// THE INITIAL PHASES are constants and not a `Rand`: two cells playing
				// one note have to be one sound. Eight lanes all starting at 0 attack
				// as one in-phase copy at eight times the steady level and then unzip
				// — a click on every note at every Spread but zero.
				// WHICH eight is not a free choice and the obvious answer is the worst
				// one: an EVENLY spread set (van der Corput, golden ratio, anything
				// low-discrepancy) is eight copies at phases k/8, which sum to the
				// shape at 8× the frequency and ⅛ the amplitude — harmonics 1…7
				// cancel EXACTLY. Measured with van der Corput phases the sine entry
				// lost 10.5 dB of rms at Spread 0.1 and the saw 8.2 dB: a hole in the
				// middle of the knob. The set below is SEARCHED against the gain law
				// itself — the lanes at spread c sum harmonic by harmonic to
				// |Σ exp(2πi·n·φ_k·c)|, which is exactly the number the law has to be
				// the reciprocal of — and holds it within 0.92 dB at every c on 1/n²,
				// 1/n⁴ and bare-fundamental spectra. A set picked only for c = 1
				// passes through a 4 dB cancellation notch at c = 0.8 on the way.
				// AT SPREAD 0 THIS IS ONE COPY of the selected waveshape: every ratio
				// is 2^0 and every phase offset is c·φ = 0, the lanes are the same
				// float, they are summed as a BALANCED TREE (which makes 8a exact
				// where a left fold rounds at 3a, 5a, 6a and 7a) and g is exactly ⅛.
				// Measured against the models that already ship, the five entries with
				// a counterpart land within ONE float32 ulp — 3.0e-08 against `saw`,
				// 6.0e-08 against `pulse` at each of its three duties, 3.6e-07 against
				// `tri`, 8.9e-08 against `sine`.
				var det   = oscDetune.clip(0, 1) * 0.5;             // ±50 cents at the rim, §7 Q6
				var p     = 4 ** ((2 * oscSkirt.clip(0, 1)) - 1);
				var u     = Array.fill(8, { |k| (2 * k / 7) - 1 });
				var d     = u.collect { |v| v.sign * (v.abs ** p) };
				// the lanes' mean displacement, normalised so skirt ½ (mean|u| = 4/7)
				// leaves the law reading Spread alone, and less when Skirt pulls in
				var disp  = (d.collect { |v| v.abs }.sum / 8) * (7 / 4);
				var c     = (oscDetune.clip(0, 1) * 100 * disp).clip(0, 1);
				var g     = 1 / ((8 * (1 - c)) + (8.sqrt * c));
				var ph0   = #[0, 0.217, 0.387, 0.409, 0.456, 0.526, 0.546, 0.931];
				// ONE mip level for all eight, off the WIDEST lane's read rate and
				// through `modF`'s PM factor (§2.1). Eight levels would be eight kr
				// log2/floor chains to split at most one mip boundary across a
				// hundred cents.
				var lvlW  = lvlOf.(oscF * det.midiratio * (1 + pmD));
				var wIdx  = oscWave.round(1).clip(0, 7);
				// THE WAVEFORM CHOOSER selects BUFNUMS AND TWO CONSTANTS, never
				// signals — Bitwig's Waveform is a menu applied to all eight voices,
				// not a saw↔sine crossfade (§7 Q6) — so eight entries cost two
				// oscillators a lane instead of sixteen. The eight are F2's and the
				// card says so (the entry list behind `[various waves]` is documented
				// nowhere): SAW, SQR, PLS, NRW (the `\pulse` arm's two reads at duty
				// ½, ¼, ⅛, in ITS order because this bank's saw FALLS), TRI, SIN,
				// HALF, TEETH. SIN costs no extra UGen because the banks are cut by
				// h = floor(SR/2 / (55·2^l)), which at the top level clips to ONE
				// partial: the triangle bank's last level is literally a unit sine.
				var bufA  = Select.kr(wIdx, [tBase + lvlW, tBase + lvlW, tBase + lvlW,
					tBase + lvlW, triBase + lvlW, triBase + tLast, hBase + lvlW, tBase + lvlW]);
				var sh    = Select.kr(wIdx, [0, 0.5, 0.75, 0.875, 0, 0, 0, 0.5]);
				// …and the shifted read's level, negated so a lane is one MulAdd
				var bNeg  = Select.kr(wIdx, [0, -1, -1, -1, 0, 0, 0, -0.5]);
				var lane  = { |k|
					// the lane's own accumulator: its own rate, its own start phase
					// added AFTER the Phasor (Phasor's `start` is its range floor, not
					// an initial value — a free-running lane under `oscRetrig` 0 would
					// ignore a resetPos and attack in phase with the other seven), and
					// the sub's phase modulation, which this model has to add per lane
					// because it reads no shared `ph`. `rst` and not `rt`: hard sync to
					// the sub reaches all eight (§1.3 — the sub is the sync master for
					// the slot, whatever the slot is).
					// The phase stays NORMALISED until each read scales it and the
					// shifted read is written `((p + sh) % 1) * 2pi`, the `\pulse` arm's
					// own form: scaling first is three UGens a lane cheaper and a few
					// ulps off the arm it is supposed to equal — it left waves 1/2/3 at
					// Spread 0 differing from the `pulse` model by 2.6e-06 where this
					// form differs by nothing at all.
					var pN = Phasor.ar(rst, oscF * (d[k] * det).midiratio * sdur, 0, 1)
						+ (ph0[k] * c) + pmP;
					Osc.ar(bufA, 0, pN * 2pi) + (Osc.ar(tBase + lvlW, 0, ((pN + sh) % 1) * 2pi) * bNeg)
				};
				var l = Array.fill(8, lane);
				(((l[0] + l[1]) + (l[2] + l[3])) + ((l[4] + l[5]) + (l[6] + l[7]))) * g
			},
			\bite, {
				// §1.2.8 two identical morphing cores wired into each other `✓ [UG]`:
				// A exponentially frequency-modulates B, B pulse-width-modulates A, A
				// can hard-sync B, B carries its own pitch offset, and a three-way
				// mixer sets the level of A, of B and of the ring modulation A×B.
				// `hasSync` deliberately does NOT list `bite`: this model's `oscSync`
				// is not Pulse's and Saw's self-sync but the A→B hard-sync enable, so
				// A runs at the nominal rate. Listing it there would run the audible
				// wave 2^(sync/12) faster AND sync B to it — the interval applied
				// twice.
				// The graph is two channels wherever `oscStereo` can split it, so the
				// feedback pair is as wide as the phase it modulates: a fixed
				// LocalIn.ar(1) against a two-channel LocalOut is a channel-count
				// mismatch, not a downmix.
				var nch   = ph.asArray.size;
				var mA    = oscMode.round(1).clip(0, 8);
				var mB    = oscModeB.round(1).clip(0, 8);
				var pwA   = oscPw.clip(0.02, 0.98);
				var pwB   = oscPwB.clip(0.02, 0.98);
				var pwmD  = oscPwm.clip(0, 1);
				var fmD   = oscFm.clip(0, 1);
				// §1.2.8: SYNC > 0 engages the reset AND its value adds to Pitch
				// Offset — the shared control read exactly as Pulse and Saw read
				// theirs, in semitones, with the same 0.005 engage threshold, so a
				// knob parked at 0 costs the reset nothing.
				var syncK = oscSync.clip(0, 60);
				var stB   = oscPitchB.clip(-48, 48) + syncK;
				// PWM reaches the pulse width's own declared ends and no further:
				// ±0.48 around a centred knob is 0.02…0.98, so full depth sweeps the
				// whole span and the clip below never has to bite in normal use.
				var pwmS  = pwmD * 0.48;
				// §2.1's level rule applied to the WARP the way `\tri` applies it to
				// skew: the steep segment reads its table 0.5/min(w, 1−w) times faster
				// than the note, so the level follows that rate and not the pitch — a
				// table read at 25× its nominal rate (w at the 0.02 clip) folds its
				// own partials back as an octave-wrong buzz. The width is audio-rate
				// under PWM, so the level takes the WORST CASE over the span the depth
				// can reach; at `oscPwm` 0 that is the knob itself and costs nothing.
				var wLo   = (pwA - pwmS).clip(0.02, 0.98);
				var wHi   = (pwA + pwmS).clip(0.02, 0.98);
				var slpA  = 0.5 / wLo.min(1 - wHi);
				var slpB  = 0.5 / pwB.min(1 - pwB);
				// B's nominal rate and the worst case the FM can push it to, both
				// clipped to 0.45·SR here so the LEVEL is chosen for a rate the phasor
				// can actually run at; the per-sample clip further down is what bounds
				// the phasor itself.
				var fBnom = (readF * stB.midiratio).clip(nyq.neg, nyq);
				var fBmax = (fBnom.abs * (fmD * 48).midiratio).min(nyq);
				// THE NINE SHAPES, one definition for both cores: §2.2's single phase
				// warp q = p<w ? p/(2w) : ½+(p−w)/(2(1−w)) — [0,w) stretched over the
				// first half of the cycle and [w,1) over the second — applied to a base
				// shape, with the fixed Saw and Sine reading `p` and so ignoring the
				// width, which is exactly why the manual calls that pair «fixed».
				// Branchless, the `\tri` arm's form: written as a Select the warp would
				// be evaluated twice. F2's names for the seven, invented and declared
				// as such (§7 Q8): 0 SQR a duty-w pulse (two bank reads half a cycle
				// apart in q, the `\pulse` arm's polarity), 1 TRI, 2 SIN, 3 HALF (the
				// sub's half of ~f2PolymerTables), 4 TRAP the triangle driven 2× into a
				// hard clip, whose corners the warp then moves, 5 DBL two sine cycles
				// per period so the warp splits them asymmetrically, 6 STEP a
				// four-level staircase saw(q) − saw(4q)/4 normalised by 4/3 — two
				// band-limited reads make the steps, an arithmetic quantiser would make
				// them out of pure aliasing — 7 SAW· and 8 SIN· the fixed pair.
				// A Select over the nine costs all nine every sample, and that is the
				// §2.2 rule kept, not broken: the MODULE is built and only the module's
				// own mode list is selected, because `oscMode` is a live control and a
				// variant per waveshape would be 81 defs for one oscillator.
				// Every scaling two shapes share is hoisted, `q·2π` above all: sclang
				// emits one BinaryOpUGen per written multiply and folds nothing, and
				// this arm pays for everything it writes twice over, once per core.
				var core  = { |p, w, lvlP, lvlW, lvlS, mode|
					var q    = (0.5 * (p / w).min(1)) + (0.5 * ((p - w) / (1 - w)).max(0));
					var q2pi = q * 2pi;
					var p2pi = p * 2pi;
					var sawQ = Osc.ar(tBase + lvlW, 0, q2pi);
					var triQ = Osc.ar(triBase + lvlW, 0, q2pi);
					Select.ar(mode, [
						sawQ - Osc.ar(tBase + lvlW, 0, (q + 0.5).wrap(0, 1) * 2pi),
						triQ,
						SinOsc.ar(0, q2pi),
						Osc.ar(hBase + lvlW, 0, q2pi),
						(triQ * 2).clip2(1),
						SinOsc.ar(0, q2pi * 2),
						(sawQ - (Osc.ar(tBase + lvlS, 0, (q * 4).wrap(0, 1) * 2pi) * 0.25)) * (4/3),
						Osc.ar(tBase + lvlP, 0, p2pi),
						SinOsc.ar(0, p2pi)
					])
				};
				// §7 Q18, taken: the B→A leg is closed through LocalIn/LocalOut and
				// pays one control block (1.33 ms at blockSize 64 and 48 kHz). That is
				// the colour of Bite's audio-rate PWM here — B leads the width it sets
				// by a block — and the global block size is NOT lowered for one
				// oscillator; a compiled UGen is the long-term answer (§6.9).
				// `Sanitize` in the loop and not only at the unit output: a NaN that
				// gets into a feedback path is there for the life of the voice and the
				// blocker downstream cannot un-ring it.
				// This pair is polymerU's ONLY audio-rate LocalIn, and a def gets
				// exactly one — a second is silently zeroed (IOUGens.cpp
				// LocalIn_Ctor), so it would not fail, it would go quiet. ~f2FltSlot's
				// block-delayed models keep clear of it on purpose (Ripple's R3 runs
				// its loop through a per-voice LocalBuf), but polysynthU's `fb` does
				// own a pair, so if FILTER.md §6 Q13 ever brings `fb` to Polymer it
				// lands on top of this one and `osc: bite` is where it breaks.
				var fbB   = Sanitize.ar(LocalIn.ar(nch));
				var wA    = (pwA + (pwmS * fbB)).clip(0.02, 0.98);
				// STEP's second read runs four times faster, and four times is two
				// levels exactly — `lvlW + 2` is the index `lvlOf` would return and six
				// control UGens per channel cheaper. The clip is not decoration: the
				// tri bank starts where the saw bank ends and the half-sine bank where
				// the tri bank ends, so an index past `tLast` does not read a duller
				// table, it reads a DIFFERENT WAVE.
				var lvlWA = lvlOf.(modF * slpA);
				var sA    = core.(ph, wA, lvl, lvlWA, (lvlWA + 2).min(tLast), mA);
				// A→B is EXPONENTIAL FM (Bitwig writes «xFM»), 0…4 octaves deep, and
				// it is SAMPLE-ACCURATE — only the PWM leg goes through the block,
				// because A feeds B forward inside the same sample and the loop is
				// broken on the way back. Exponential is why B's average pitch rises
				// with depth and why the result is inharmonic; Bitwig corroborates by
				// offering SYNC as the way to use xFM «without breaking the pitch of
				// Oscillator B». Both clips are load-bearing: the semitone clip stops
				// 2^x reaching `inf` if a band-limited core overshoots (inf × 0 in the
				// mixer is a NaN, and a NaN in a phasor is permanent), and the
				// frequency clip keeps the accumulator's step under half a cycle —
				// past Nyquist expo FM runs away and the phase step aliases down to an
				// arbitrary pitch instead of getting brighter.
				var fmSt  = (sA * fmD * 48).clip(-60, 60);
				var fB    = (fBnom * fmSt.midiratio).clip(nyq.neg, nyq);
				// the sync tick: §2.2 writes it `Slope.ar(pA) < 0`, and this is that
				// test made direction-blind. A phasor whose rate is NEGATIVE — the
				// right channel of a stereo-detuned voice at `oscRatioN` 0 with a
				// negative `oscHz` — falls on every sample, so a bare `< 0` would reset
				// B every sample and hold that channel at DC. What marks the wrap in
				// either direction is the step: |Δφ| > ½ cannot happen below Nyquist
				// and always happens at the seam.
				var aWrap = ((ph - Delay1.ar(ph)).abs > 0.5) * (syncK > 0.005);
				var pB    = Phasor.ar(rt + aWrap, fB * sdur, 0, 1);
				var lvlWB = lvlOf.(fBmax * slpB);
				var sB    = core.(pB, pwB, lvlOf.(fBmax), lvlWB, (lvlWB + 2).min(tLast), mB);
				// the trio of mix levels (§1.2.8), lagged 4 ms like Union's three so a
				// level jump is a ramp and not a click. Nothing is normalised, as in
				// Union (§7 Q4): all three at 1 is ±3 and `gain` / `amp` are where that
				// is dealt with. The RM term carries DC as soon as PWM makes the two
				// shapes asymmetric — the 0.9993 blocker at the unit output takes it,
				// and it stays the ONLY blocker (§2 decision 5).
				var lA    = Lag.kr(oscLvlA.clip(0, 1), 0.004);
				var lB    = Lag.kr(oscLvlB.clip(0, 1), 0.004);
				var lR    = Lag.kr(oscLvlRm.clip(0, 1), 0.004);
				LocalOut.ar(sB);
				(sA * lA) + (sB * lB) + (sA * sB * lR)
			},
			\scrawl, {
				// §1.2.9 the freely drawn single cycle. It has NO timbre knobs at all —
				// the shape IS the control — so this arm reads nothing of §1.2 and
				// declares nothing beyond §1.1 and the `curve` resource opt. `hasSync`
				// does not list it either: Scrawl carries no Sync knob in Bitwig, so the
				// wave runs at the nominal rate and the only resets it takes are the
				// note's and the sub's (§1.3).
				// The cycle reaching the server is GENUINELY PERIODIC — 16384 samples of
				// the half-open cycle, its terminal value living in a guard frame
				// OUTSIDE them (~f2CurveShape) — so the offline FFT that cut these
				// twelve levels needed no window and no endpoint fixup, and every level
				// is exactly periodic in 2048 points. That is what §1.2.9 means by «for
				// free», and it is why the drawn wave has no click at the wrap.
				// ONE READ ON THE SHARED PHASE, `lvlOf`'s own floored level — this arm is
				// the `saw` arm with a different bank, and deliberately so. Two things
				// the §6.8 sketch asked for are NOT taken, each because the measurement
				// went the other way:
				//   · VOsc, because VOsc owns its own accumulator and has no reset:
				//     retrigger, hard sync to the sub and the sub's phase modulation all
				//     act on `ph`, and `oscRetrig` is ON by default, so a VOsc Scrawl
				//     would silently ignore three parts of the machinery every other
				//     model obeys — and would need a second, different branch for the
				//     sync case, which is a model that can drift out of step with the
				//     other eight;
				//   · the UNROUNDED level and its crossfade into the next table, because
				//     these twelve levels are a MIP PYRAMID and not a wavetable morph.
				//     Level L already keeps only the partials that stay under SR/2 at the
				//     TOP of its band, so blending the next level in near that top THROWS
				//     AWAY harmonics that are legal at the pitch being played: measured
				//     on the drawn triangle at 1500 Hz, where the fractional level is
				//     5.77, the crossfade attenuated harmonic 7 — whose own frequency is
				//     10.5 kHz, less than half Nyquist — by 77 %. That is a dulling that
				//     moves with pitch, which is worse than the timbre STEP it was meant
				//     to hide, and the step is one every other oscillator on this card
				//     already has. The pyramid's law decides what is safe; nothing here
				//     second-guesses it.
				// The level follows `modF` (§2.1's worst case: the read rate with PM's
				// (1 + pm) factor on it) and never the nominal pitch, for the reason
				// every other read here does — a table read faster than its level allows
				// folds its own partials back as an octave-wrong buzz.
				// `curveBuf` is the BASE of twelve CONSECUTIVE buffers, so the level is
				// an offset a kr signal can carry. -1 means the render has not landed:
				// `.max(0)` reads buffer 0, the same fallback every other bank in this
				// file takes when its allocation failed, and \f2voice hands the default
				// drawing (~f2CurveNull) rather than -1 whenever a server is up.
				Osc.ar(curveBuf.max(0) + lvl, 0, ph * 2pi)
			}
		);
		// §1.3 / §2 items 2 and 4 — the MIX STAGE. `fSubNoise` is a VCA on the sub
		// and the noise BEFORE either blend, not a post-filter trim (§2 item 4), so
		// it is applied to both sources here and nowhere else. Then two
		// CROSSFADES, not sums: Bitwig's wording is unambiguous («blend between the
		// main oscillator (0 %) and the sub oscillator (100 %)»), and a crossfade
		// is what makes `sub` 1 silence the slot oscillator EXACTLY rather than
		// merely bury it. Linear and not equal-power (§7 Q11's recommendation
		// taken): `XFade2`'s law would put a +3 dB bump in the middle that «blend»
		// does not suggest. `LinXFade2` at −1 is `A × 1 + B × 0`, so a save with
		// `sub` and `noise` at their 0 defaults is the stage-2 graph to the bit.
		// The sub and the noise are MONO into both channels: `oscStereo` splits the
		// slot oscillator alone, and Polymer has one sub voice and one «noise
		// generator» (§1.3), so `noise` 1 is a centred hiss, not a widened one. No
		// white/pink choice, `✓ [STR]` by omission — the `polymer.*` string set
		// lists all ten panel controls and carries no noise-type key where the Grid
		// Noise module demonstrably does (§7 Q11).
		// §1.4 the high-pass sits PRE-filter (§2 decision 3). Bitwig's Polymer
		// panel gives it neither resonance nor slope (§7 Q22 — a pole count is seen
		// in the Expanded Device View only); the §flt union brings Polysynth's
		// hpMode / hpRes here as F2's wiring, marked as such: each stage is the
		// stage-1 HPF.ar at hpRes 0 — HPF × 1 + RHPF × 0, exact — cross-fading
		// linearly into Polysynth's RHPF law (rq = 1 − 0.95·hpRes) as hpRes rises,
		// and hpMode's `— 2p 4p` picks none / one / two stages, def 1 = the one HPF
		// stage 1 always had in circuit. A filter's own coefficient morph would be
		// the honest build; two filters cross-faded is what keeps 0 bit-exact.
		var subGate = Select.kr(fSubNoise > 0.5, [1, feg]);
		var mix1  = LinXFade2.ar(oscSig, subSig * subGate, (sub.clip(0, 1) * 2) - 1);
		var mix2  = LinXFade2.ar(mix1, WhiteNoise.ar * subGate, (noise.clip(0, 1) * 2) - 1);
		var hpF   = hpFreq.clip(19.4, nyq);
		var hpR   = hpRes.clip(0, 1);
		var hpQ   = 1 - (hpR * 0.95);
		var hpStg = { |x| (HPF.ar(x, hpF) * (1 - hpR)) + (RHPF.ar(x, hpF, hpQ) * hpR) };
		var hp2   = hpStg.(mix2);
		var hp4   = hpStg.(hp2);
		var hp    = Select.ar(hpMode.round(1).clip(0, 2), [mix2, hp2, hp4]);
		// §1.5 drive is a gain INTO the model's nonlinearity, not a trim: on `ld`
		// that nonlinearity is the ladder's own resonance, and `mg`'s input tanh is
		// what makes the two models different (FILTER.md §3.2). On `poly` there is none, so
		// it is the plain pre-filter gain Polysynth applies.
		var pre   = hp * drive.clip(-24, 24).dbamp;
		// §2 decision 1: the cutoff sum happens in the PITCH domain, in semitones,
		// and is exponentiated ONCE — `keytrack` 0…200 % and `egAmt` ±120 st are
		// both measured off Bitwig's device dump. Summed in Hz the FEG would sound
		// wrong at the bottom of the keyboard; this is how Bitwig's cutoff bus works.
		// This unit's own law, kept (polysynthU reads keytrack as a factor on the
		// glided freq BEFORE `pitch`; here it is semitones AFTER it). The filter FM
		// and the 19.4…0.45·SR clip are inside ~f2FltSlot, and the FM product is
		// formed at kr here (fmKr) — an ar wire would hand MoogFF the previous
		// block's cutoff, one block late against stage 1; at filtFm 0 the bus keeps
		// this value exactly.
		var cutSt = (keytrack.clip(0, 2) * 12 * (noteF / 261.63).log2)
			+ (egAmt.clip(-120, 120) * feg);
		var cutK  = cut.clip(19.4, 33500) * (2 ** (cutSt / 12));
		// §2.3 the slot — `ld` (MoogFF, the stage-1 build) or `poly` (Polysynth's
		// core as a second arm on this cutoff bus), then the bypass and the shaper,
		// Polysynth's block verbatim: shaper 0 → post = filt exactly.
		var flt   = fltSlot.(fltM, pre, cutK, 19.4, nyq, filtFm, res, fltMode, filtOn, shaper, shaperMode, true,
			fltLin, resLimit, fltMode2, fltFbGain, fltFbCut, fltColor, fltVowel, bellGain);
		var post  = flt[\post];
		var outLv = aeg * velC * gain.clip(-24, 24).dbamp * amp;
		var sig   = Balance2.ar(post[0], post[1], pan.clip(-1, 1), outLv);
		// telemetry as every unit, with the §synth-mod audibility gate: a telId of 0
		// (no telOut on the preset) sends nothing at all, and a voice that neither
		// sounds nor holds its gate is silent on the wire too.
		SendReply.kr(Impulse.kr(30) * (telId > 0) * ((aegK > 0.001) + (g > 0)).min(1),
			'/f2_chan', [aegK], telId);
		// §2 decision 5: ONE DC blocker, and its coefficient is lower than the SC
		// default (0.9993 ≈ 5 Hz at 48 kHz against 0.995 ≈ 40 Hz) because Union's
		// documented DC-drift is a SLOW transient and a 40 Hz blocker turns it into
		// a click. It stays the only one: a second blocker upstream would cascade
		// two high-passes and the faster of the two would win.
		Out.ar(out, Sanitize.ar(LeakDC.ar(sig, 0.9993)));
	});
	bytes = def.asBytes.size;
	("[f2 pm] % (osc % / filt % / env %): % bytes".format(def.name, oscM, fltM, envM, bytes)).postln;
	if (bytes > 16383) {
		("⚠ [f2 pm] % is % bytes > 16383 — sclang writes the def file and /d_load's it (local server)"
			.format(def.name, bytes)).postln;
	};
	def
};
// the base def (every menu at its default) — the SynthDesc the context export
// and \f2voice read; variants are built on demand by ~f2UnitDef / ~f2UnitEnsure
~f2UnitGen[\polymerU].value((), \polymerU).add;

("✓ f2units v" ++ ~f2UnitsVer ++ ": 26 units (v49 cut " ++ ~f2UnitsCut.size ++ ": " ++ ~f2UnitsCut.keys.asArray.sort.join(" ") ++ ") + f2chainOut sink + ports + eq3 + stut-look/idle2 + conv-suite (convU bus|sample IR) + tape-head + chip + polysynth (saw bank @" ++ ((~f2PolyTables !? { |t| t[\base] }) ? "none") ++ ") + sampler (repitch/cycles/textures/spectral/fragments, single/sliced, grain windows @" ++ ((~f2SmpWins !? { |t| t[\base] }) ? "none") ++ ", slicing div/beats/onsets/pitch/manual, spectral " ++ if (~f2SmpPV) { "PV @ nulls " ++ (~f2SmpFftNull.keys.asArray.sort.collect { |k| ~f2SmpFftNull[k] }) } { "Warp1 fallback (no sc3-plugins)" } ++ ", filter block core) + polymer (stage 4: saw/sine/tri/pulse/union/phase1/swarm/bite/scrawl + sub/noise/pm/sync + ld + adsr of 9x11x7 menus, 81 live controls, tri + half-sine banks @" ++ ((~f2PolymerTables !? { |t| t[\base] }) ? "none") ++ ") + flt (one filter slot on polysynth 72 / polymer 81 / sampler 92 live controls: all eleven models built, FILTER.md §3) + env (one envelope block on all three: all seven — adsr ahdsr ar ad pluck shot segments — built on all three) + curve (the drawn point list: v1 base-32, cap " ++ ~f2CurveMax ++ " points, " ++ ~f2CurveRender ++ "-sample cycle + guard frame, " ++ ~f2CurveLevels ++ " mip levels, cache " ++ ~f2CurveCacheMax ++ ", defaults @" ++ (if (~f2CurveNull >= 0) { ~f2CurveNull.asString ++ "/" ++ ~f2CurveNullShape } { "none" }) ++ ") + unit schema (opts/specs) + port-who + telemetry + chain/chainIn pass-through + unit variants (" ++ ~f2UnitGen.size ++ " gen, " ++ ~f2LegacyUnits.size ++ " legacy)").postln;
// The unit count above is the SynthDefs whose name ends in `U`: 23 written out in this file
// plus the three ~f2UnitGen builds (polysynthU, samplerU, polymerU) — 26 since v49 took
// amU, envcaU and onsetU out (~f2UnitsCut). It had been one short since samplerU landed —
// the number is hand-kept, so it says here what it counts, and sc/nrt/build.scd asserts it.
//
// The COMPLETION MARKER, and the last statement in the file on purpose. This
// whole file is ONE expression, so a throw anywhere in it abandons everything
// below the throw while leaving what ran already in place — a half-loaded engine
// that looks exactly like a good one from the outside. ~f2UnitsLoadedVer keeps
// its previous value in that case, so f2_boot and the checks can tell the two
// apart instead of guessing from which units happen to be missing.
~f2UnitsLoadedVer = ~f2UnitsVer;
};
)
