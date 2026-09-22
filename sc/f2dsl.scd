{ |rootPath|
	var globalEnv = currentEnvironment;

	Spec.add(\srcX, [0, 1]);
	Spec.add(\srcY, [0, 1]);
	Spec.add(\mic1X, [0, 1]);
	Spec.add(\mic1Y, [0, 1]);
	Spec.add(\mic2X, [0, 1]);
	Spec.add(\mic2Y, [0, 1]);

	// Physics
	Spec.add(\decayScale, [0.1, 10.0, \exp]);
	Spec.add(\roomSize, [0.01, 10, \exp]);
	Spec.add(\clickVol, \amp);
	Spec.add(\damp, [0, 1]);
	Spec.add(\gridRes, [2, 32, \lin, 1]);

	// Texture
	Spec.add(\roughness, [0.0, 1.0]);
	Spec.add(\rub, [0.0, 1.0]);
	Spec.add(\dryMix, [0.0, 1.0]);
	Spec.add(\crinkle, [0.0, 1.0]);

	// Synth type IDs for visualizer (used in SendReply)
	// 0 = modalS (legacy default), 1 = foldS, 2 = pluckS
	Spec.add(\synthType, [0, 10, \lin, 1]);

	// Standard Envelope
	Spec.add(\atk, [0.001, 2.0, \exp]);
	Spec.add(\dec, [0.01, 2.0, \exp]);
	Spec.add(\sus, [0.0, 1.0]);
	Spec.add(\rel, [0.01, 5.0, \exp]);
	Spec.add(\curve, [-8, 8]);

	// Standard FX
	Spec.add(\gate, [0, 1, \lin, 1]);
	Spec.add(\mix, [0, 1]);
	Spec.add(\wet, [0, 1]);
	Spec.add(\feedback, [0, 1]);
	Spec.add(\drive, [1, 100, \exp]);
	Spec.add(\width, [0, 1]);
	Spec.add(\colorID, [0, 10, \lin, 1]);

	Spec.add(\hardness, [0, 1]);
	Spec.add(\bendAmount, [-2, 2]);
	Spec.add(\feedback, [0, 0.99]);
	Spec.add(\crossCouple, [0, 1.0]);
	Spec.add(\scrupAmp, [0, 4.0]);
	Spec.add(\damp, [0, 1]);

	// ═══════════════════════════════════════════════════════════
	// A. SYNTAX INJECTORS
	// ═══════════════════════════════════════════════════════════

	// --- Structure ---
	~q = Object.new;
	~q.addUniqueMethod(\at, { |self ... args| (dsl_type: \seq, list: args) });
	~c = Object.new;
	~c.addUniqueMethod(\at, { |self ... args| (dsl_type: \par, list: args) });
	~m = Object.new;
	~m.addUniqueMethod(\at, { |self ... args| (dsl_type: \bind, head: args[0], args: args[1..]) });

	// --- Structure Extensions ---
	~w = Object.new;
	~w.addUniqueMethod(\at, { |self ... args| (dsl_type: \wseq, pairs: args.clump(2)) });
	~r = Object.new;
	~r.addUniqueMethod(\at, { |self ... args| (dsl_type: \rand, list: args) });
	~rw = Object.new;
	~rw.addUniqueMethod(\at, { |self ... args| (dsl_type: \wrand, pairs: args.clump(2)) });
	~n = Object.new;
	~n.addUniqueMethod(\at, { |self ... args| (dsl_type: \rep, item: args[0], times: args[1] ?? 2) });

	// --- Modulation ---
	~pick = Object.new;
	~pick.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \pick, param: args[0], values: args[1], scope: args[2] ?? \event)
	});
	~ramp = Object.new;
	~ramp.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \ramp, param: args[0], from: args[1], to: args[2], curve: args[3] ?? \lin)
	});
	~osc = Object.new;
	~osc.addUniqueMethod(\at, { |self ... args|
		var param = args[0];
		var vals = if (args[1].isKindOf(Array)) { args[1] } { args[1..] };
		(dsl_type: \osc, param: param, values: vals)
	});
	~drift = Object.new;
	~drift.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \drift, param: args[0], center: args[1] ?? 0.5,
			amount: args[2] ?? 0.05, speed: args[3] ?? 4)
	});

	// --- Extended Modulation Injectors ---
	~slew = Object.new;
	~slew.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \slew, param: args[0], from: args[1], to: args[2],
			slewTime: args[3] ?? 0.1, curve: args[4] ?? \lin)
	});
	~stepR = Object.new;
	~stepR.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \stepR, param: args[0], values: args[1], holdBeats: args[2] ?? 1)
	});
	~lfoR = Object.new;
	~lfoR.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \lfoR, param: args[0], center: args[1] ?? 0.5,
			depth: args[2] ?? 0.3, rate: args[3] ?? 1, wave: args[4] ?? \sin)
	});
	~envR = Object.new;
	~envR.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \envR, param: args[0],
			levels: args[1] ?? [0, 1, 0.6, 0],
			times: args[2] ?? [1, 1, 2],
			curves: args[3] ?? [\lin, \lin, \lin])
	});


	// ═══════════════════════════════════════════════════════════
	// --- FX Ramp Injector (scope-aware) ---
	~fxRamp = Object.new;
	~fxRamp.addUniqueMethod(\at, { |self ... args|
		(dsl_type: \fxRamp, target: args[0], param: args[1],
			from: args[2] ?? 0, to: args[3] ?? 1, curve: args[4] ?? \lin, rate: args[5] ?? 1)
	});

	// B. DATA STORAGE
	// ═══════════════════════════════════════════════════════════

	~defs = ~defs ?? { Dictionary.new };
	~samples = ~samples ?? { Dictionary.new };
	~modalBuffers = ~modalBuffers ?? { Dictionary.new };
	~rack = ();
	~dsl = ();
	~rack.repo = Dictionary.new;
	~dsl.fxTargets = Dictionary.new;
	~dsl.fxAliasMap = Dictionary.new;
	~rack.bus = ( main: Bus.audio(s, 2), tel:  Bus.control(s, 4) );

	// SynthType registry: visualizer reads this to interpret telemetry slots
	~synthTypes = Dictionary.new;
	~synthTypes[0] = (name: \modalS,  class: \positioned, params: #[micSpread, roughness, roomSize, modDepth]);
	~synthTypes[1] = (name: \foldS,   class: \positioned, params: #[micSpread, crinkle, roomSize, modDepth]);
	~synthTypes[2] = (name: \pluckS,  class: \positioned, params: #[micSpread, crinkle, roomSize, modDepth]);
	~synthTypes[3] = (name: \kickS,   class: \simple,     params: #[tension, click, 0, 0]);
	~synthTypes[4] = (name: \s1S,     class: \simple,     params: #[snap, timb, 0, 0]);
	~synthTypes[5] = (name: \h1S,     class: \simple,     params: #[sharp, 0, 0, 0]);
	~synthTypes[6] = (name: \amS,     class: \tonal,      params: #[modIndex, feedback, 0, 0]);
	~synthTypes[7] = (name: \clayPS,  class: \tonal,      params: #[brightness, texture, drive, hardness]);
	~synthTypes[8] = (name: \hatS,    class: \simple,     params: #[sharp, 0, 0, 0]);
	~synthTypes[9] = (name: \kickS,   class: \simple,     params: #[tension, 0, 0, 0]);

	// ═══════════════════════════════════════════════════════════
	// C. PARSER
	// ═══════════════════════════════════════════════════════════

	~toPat = { |obj, dur|
		// NIL GUARD: nil input → rest
		if (obj.isNil) { Pseq([(type: \rest, dur: dur ? 1)], 1) }
		{
		if (obj.isKindOf(Function)) {
			Plazy({ ~toPat.value(obj.value, dur) });
		}
		{
			if (obj.isKindOf(Event) and: { obj[\dsl_type].notNil }) {
				var type = obj[\dsl_type];

				case

				// ─── STRUCTURE ───

				{ type == \seq } {
					var list = obj[\list];
					if (list.isNil or: { list.size == 0 }) {
						Pseq([(type: \rest, dur: dur)], 1)
					} {
						var subDur = dur / list.size;
						Pseq(list.collect { |item| ~toPat.value(item, subDur) }, 1);
					}
				}
				{ type == \par } {
					var list = obj[\list];
					if (list.isNil or: { list.size == 0 }) {
						Pseq([(type: \rest, dur: dur)], 1)
					} {
						Ppar(list.collect { |item| ~toPat.value(item, dur) }, 1);
					}
				}
				{ type == \bind } {
					Plazy({
						var head = obj[\head];
						var params = obj[\args];
						var maxSeqLen = 1;

						// Remaining non-Function modifiers become Pchain layers
						var allPure = params.reject(_.isKindOf(Function));
						var fxRampObjs = allPure.select { |p| p.isKindOf(Event) and: { p[\dsl_type] == \fxRamp } };
						var pureParams = allPure.reject { |p| p.isKindOf(Event) and: { p[\dsl_type] == \fxRamp } };
						var modifiers = pureParams.collect { |p|
							if (p.isNil) { Pbind() }  // skip nil modifiers
							{
							if (p.isKindOf(Event) and: { p[\dsl_type] == \seq }) {
								var list = p[\list];
								var parsedList = list.collect { |item|
									if (item.isNumber or: { item.isKindOf(Event) }) { item }
									{ ~toPat.value(item, dur) }
								};
								if (list.size > maxSeqLen) { maxSeqLen = list.size };
								if (parsedList.every(_.isNumber)) {
									Pbind(\degree, Pseq(parsedList, inf), \dur, Pfin(maxSeqLen))
								} {
									Pfin(maxSeqLen, Pseq(parsedList, inf))
								}
							} {
								if (p.isKindOf(Event) and: { p[\dsl_type].notNil }) {
									~toPat.value(p, dur)
								} {
									if (p.isKindOf(Pattern)) { p }
									{
										if (p.isKindOf(Event)) { Pbind(*p.asPairs) }
										{ if (p.isNumber) { Pbind(\degree, p) } { Pbind() } }
									}
								}
							}
							}
						};

						var headPat;
						var isDSL = head.isKindOf(Event) and: { head[\dsl_type].notNil };
						var isAtom = (head.isKindOf(Symbol) or: { head.isNumber } or: { head.isKindOf(Event) and: { isDSL.not } });

						// Pre-process: Function modifiers (mod library) wrap the head
						// They return DSL nodes like ~m[head, drifts...], so apply them first
						params.do { |p|
							if (p.isKindOf(Function)) {
								head = try { p.(head) } { |err|
									"[f2 warn] bind mod fn: %".format(err.errorString).postln;
									head
								};
							};
						};

						if (isAtom and: { maxSeqLen > 1 }) {
							headPat = Pn(~toPat.value(head, dur / maxSeqLen), inf);
						} {
							headPat = ~toPat.value(head, dur);
						};

						if (modifiers.size > 0) {
							var mp = Pchain(headPat, *modifiers);
							if (fxRampObjs.size > 0) {
								var fp = fxRampObjs.collect { |obj| ~toPat.value(obj, dur) };
								Ppar([mp] ++ fp);
							} { mp };
						} {
							if (fxRampObjs.size > 0) {
								var fp = fxRampObjs.collect { |obj| ~toPat.value(obj, dur) };
								Ppar([headPat] ++ fp);
							} { headPat };
						};
					});
				}
				{ type == \wseq } {
					var pairs = obj[\pairs];
					var totalWeight = pairs.collect { |p| p[1] }.sum;
					Pseq(pairs.collect { |pair|
						~toPat.value(pair[0], dur * pair[1] / totalWeight);
					}, 1);
				}
				{ type == \rand } {
					// §16-B: the rand branch is chosen at demand time (s.latency before the sound) → send
					// /f2_branch to the backend. The compiler puts nodeId/sceneId on the Event: nodeId is
					// the id of the tree container (= randId in the backend's SessionModel), sceneId the
					// row's id. No nodeId (hand-written DSL) → as before, nothing is emitted (the backend
					// then over-gates rand — sound-safe). The distribution is identical to the old one
					// (list.size.rand == .choose); we simply catch the index now.
					var list = obj[\list];
					var nodeId = obj[\nodeId];
					var idxMap = obj[\idxMap];
					var sceneId = obj[\sceneId] ? topEnvironment[\f2Scene];
					Plazy({
						// §v2-sc the variant player: if the compiler gave us v2Id/v2Dur and the engine
						// delivered this iteration's choice (~f2Choice under the key "<scene>/<id>/<iter>",
						// iter = floor(beats/loopDur) with an epsilon off the float edge of the boundary),
						// play THAT one. No entry (engine not connected, or the very first demand) — the old throw.
						var v2got, idx, outIdx, v2key;
						if (obj[\v2Id].notNil and: { obj[\v2Dur].notNil } and: { ~f2Choice.notNil }) {
							v2key = ((sceneId ? \default).asString ++ "/" ++ obj[\v2Id].asString
								++ "/" ++ ((thisThread.beats / obj[\v2Dur]) + 1e-4).floor.asInteger).asSymbol;
							v2got = ~f2Choice[v2key];
							// §diag the first demand reads: hit (the engine's index) or nil → a random throw
							if ((topEnvironment[\f2RandLog] ? 8) > 0) {
								topEnvironment[\f2RandLog] = (topEnvironment[\f2RandLog] ? 8) - 1;
								("[f2] rand? " ++ v2key ++ " → " ++ (v2got ? "nil(roll)")).postln;
							};
						};
						idx = if (v2got.notNil and: { list.size > 0 }) { v2got.clip(0, list.size - 1) }
							{ if (list.size > 0) { list.size.rand } { 0 } };
						outIdx = if (idxMap.notNil) { idxMap[idx] ? idx } { idx };
						if (nodeId.notNil and: { ~f2BackendAddr.notNil } and: { list.size > 0 }) {
							~f2BackendAddr.sendMsg('/f2_branch',
								(sceneId ? \default).asString, nodeId.asString, outIdx, thisThread.beats.asFloat);
						};
						~toPat.value(list[idx], dur);
					});
				}
				{ type == \wrand } {
					// §16-B: the same for wrand. windex(weights) gives a WEIGHTED index with the same
					// distribution as the old items.wchoose(weights) — only now we have the index for /f2_branch.
					var pairs = obj[\pairs];
					var items = pairs.collect(_[0]);
					var weights = pairs.collect(_[1]).normalizeSum;
					var nodeId = obj[\nodeId];
					var idxMap = obj[\idxMap];
					var sceneId = obj[\sceneId] ? topEnvironment[\f2Scene];
					Plazy({
						// §v2-sc as in \rand: the engine's choice from ~f2Choice wins, the throw is the fallback
						var v2got, idx, outIdx, v2key;
						if (obj[\v2Id].notNil and: { obj[\v2Dur].notNil } and: { ~f2Choice.notNil }) {
							v2key = ((sceneId ? \default).asString ++ "/" ++ obj[\v2Id].asString
								++ "/" ++ ((thisThread.beats / obj[\v2Dur]) + 1e-4).floor.asInteger).asSymbol;
							v2got = ~f2Choice[v2key];
							if ((topEnvironment[\f2RandLog] ? 8) > 0) {
								topEnvironment[\f2RandLog] = (topEnvironment[\f2RandLog] ? 8) - 1;
								("[f2] wrand? " ++ v2key ++ " → " ++ (v2got ? "nil(roll)")).postln;
							};
						};
						idx = if (v2got.notNil and: { items.size > 0 }) { v2got.clip(0, items.size - 1) }
							{ if (items.size > 0) { weights.windex ? 0 } { 0 } };
						outIdx = if (idxMap.notNil) { idxMap[idx] ? idx } { idx };
						if (nodeId.notNil and: { ~f2BackendAddr.notNil } and: { items.size > 0 }) {
							~f2BackendAddr.sendMsg('/f2_branch',
								(sceneId ? \default).asString, nodeId.asString, outIdx, thisThread.beats.asFloat);
						};
						~toPat.value(items[idx], dur);
					});
				}
				{ type == \rep } {
					var times = obj[\times] ? 2;
					var subDur = dur / times;
					Pseq(times.collect { ~toPat.value(obj[\item], subDur) }, 1);
				}

				// ─── MODULATION (nil-safe) ───

				{ type == \pick } {
					var param = obj[\param];
					var values = obj[\values];
					var scope = obj[\scope];
					if (param.isNil or: { values.isNil } or: { values.isKindOf(Array) and: { values.isEmpty } }) { Pbind() } {
						var basePat = Prand(values, inf);
						var scopedPat = case
						{ scope == \event } { basePat }
						{ scope == \once } { Plazy({ var v = values.choose; Pn(v, inf) }) }
						{ scope == \seq } { Pseq(values, inf) }
						{ scope.isNumber } { Pstutter(scope.max(1), basePat) }
						{ basePat };

						if (param.isKindOf(Array)) {
							Pbind(*param.collect { |key, i|
								[key, Pcollect({ |arr| arr[i] }, scopedPat)]
							}.flatten)
						} {
							Pbind(param, scopedPat)
						}
					}
				}
				{ type == \ramp } {
					var param = obj[\param], from = obj[\from], to = obj[\to];
					var curve = obj[\curve];
					if (param.isNil or: { from.isNil } or: { to.isNil }) { Pbind() } {
						// from/to may be Pdefn (Patterns) in live mode — can't do
						// numeric safety checks on Patterns, so skip exp guard.
						var fromIsNum = from.isNumber;
						var toIsNum = to.isNumber;
							var pat = case
						{ curve == \rand } {
							if (fromIsNum and: { toIsNum }) {
								Pwhite(from.min(to), from.max(to), inf)
							} {
								Pwhite(from, to, inf)
							}
						}
						{ // lin, exp, default: pre-computed Pseq
							Pseq(~rampVals.(from, to, dur, curve), inf)
						};
						Pbind(param, pat)
					}
				}
				{ type == \fxRamp } {
					var target = obj[\target], fxParam = obj[\param];
					var from = obj[\from], to = obj[\to], curve = obj[\curve];
					if (target.isNil or: { fxParam.isNil } or: { from.isNil } or: { to.isNil }) { Pbind() } {
						var steps = (dur * 10).max(4).asInteger;
						var updateDur = dur / steps;
						var fxRate = obj[\rate] ?? 1;
						var vals = ~rampValsEx.(from, to, steps, curve, fxRate);
						// Standalone Pbind: fires \fxSet events at 10x/beat
						// Wrapped in Ppar by ~m handler → scope-aware
						Pfin(steps, Pbind(\type, \fxSet,
							\fxTarget, target, \fxParam, fxParam,
							\fxVal, Pseq(vals, 1), \dur, updateDur))
					}
				}
				{ type == \osc } {
					var vals = obj[\values];
					if (obj[\param].isNil or: { vals.isNil } or: { vals.size == 0 }) { Pbind() } {
						Pbind(obj[\param], Pseq(vals, inf))
					}
				}
				{ type == \drift } {
					var center = obj[\center] ? 0.5, amt = obj[\amount] ? 0.05, speed = obj[\speed] ? 4;
					if (obj[\param].isNil) { Pbind() } {
						Pbind(obj[\param],
							Pstutter(speed.max(1), Pwhite(center - amt, center + amt).clip(0.0, 1.0)))
					}
				}

				// ─── EXTENDED MODULATION ───

				{ type == \slew } {
					var param = obj[\param], from = obj[\from], to = obj[\to];
					var slewTime = obj[\slewTime] ?? 0.1;
					if (param.isNil or: { from.isNil } or: { to.isNil }) { Pbind() } {
						var nSteps = (dur / slewTime.max(0.01)).ceil.max(2).asInteger;
						var stepDur = dur / nSteps;
						var vals = Array.fill(nSteps, { |i|
							from + ((to - from) * (i / (nSteps - 1)))
						});
						Pbind(param, Pseq(~envVals.(vals, Array.fill(nSteps - 1, slewTime.max(0.01)), \lin, dur), inf))
					}
				}

				{ type == \stepR } {
					var param = obj[\param], values = obj[\values];
					var holdBeats = obj[\holdBeats] ?? 1;
					if (param.isNil or: { values.isNil } or: { values.isEmpty }) { Pbind() } {
						Pbind(param, Pstutter(holdBeats.max(1), Pseq(values, inf)))
					}
				}

				{ type == \lfoR } {
					var param = obj[\param];
					var center = obj[\center] ?? 0.5, depth = obj[\depth] ?? 0.3;
					var rate = obj[\rate] ?? 1, wave = obj[\wave] ?? \sin;
					if (param.isNil) { Pbind() } {
						var stepsPerCycle = (dur * rate).max(4).asInteger;
						var lfoVals = Array.fill(stepsPerCycle, { |i|
							var phase = i / stepsPerCycle * 2pi;
							var v = case
								{ wave == \sin } { sin(phase) }
								{ wave == \tri } { 1 - (2 * ((phase / pi) % 2 - 1).abs) }
								{ wave == \saw } { (phase / 2pi * 2) - 1 }
								{ wave == \pulse } { if ((phase / 2pi) < 0.5) { 1 } { -1 } }
								{ sin(phase) };
							center + (v * depth)
						});
						Pbind(param, Pseq(lfoVals, inf))
					}
				}

				{ type == \envR } {
					var param = obj[\param];
					var levels = obj[\levels] ?? [0, 1, 0.6, 0];
					var times = obj[\times] ?? [1, 1, 2];
					var curves = obj[\curves] ?? [\lin, \lin, \lin];
					if (param.isNil) { Pbind() } {
						Pbind(param, Pseq(~envVals.(levels, times, curves, dur), inf))
					}
				}

				// ─── FALLBACK ───
				{ true } { Pseq([Rest(dur)], 1) };
			}

			// ─── NON-DSL OBJECTS ───
			{
				// Pattern pass-through: Pbind, Pbindf, Pchain etc.
				if (obj.isKindOf(Pattern)) { obj }
				{
				if (obj.isKindOf(Array)) {
					var subDur = dur / obj.size;
					Pseq(obj.collect { |item| ~toPat.value(item, subDur) }, 1);
				}
				{
					if (obj.isKindOf(Event)) { Pseq([obj.copy.put(\dur, dur)], 1) }
					{
						if (obj.isKindOf(Symbol)) {
							if (obj == \x) { Pseq([(type: \rest, dur: dur)], 1) }
							{ Pseq([(instrument: obj, dur: dur)], 1) };
						}
						{
							if (obj.isNumber) { Pseq([(degree: obj, dur: dur)], 1) }
							{ Pseq([(type: \rest, dur: dur)], 1) }
						}
					}
				}
				}
			}
		}
		}
	};

	// ═══════════════════════════════════════════════════════════
	// D. PLAY & ENRICH
	// ═══════════════════════════════════════════════════════════

	// Pre-compute ramp values (Pseg doesn't work in Pchain context)
	~rampVals = { |from, to, steps, curve|
		var n = steps.max(1).asInteger;
		if (from.isNumber and: { to.isNumber }) {
			Array.fill(n, { |i|
				var t = if (n > 1) { i / (n - 1) } { 1 };
				case
				{ curve == \exp and: { from.abs > 0.0001 and: { to.abs > 0.0001 and: { from.sign == to.sign }}}} {
					from * (to / from).pow(t)
				}
				{ from + ((to - from) * t) }
			})
		} {
			Array.fill(n, { |i| from + ((to - from) * (i / (n - 1).max(1))) })
		}
	};
		// Full ramp value generator: handles all curve types for fxRamp
	~rampValsEx = { |from, to, steps, curve, rate=1|
		var n = steps.max(1).asInteger;
		case
		{ curve == \rand } { Array.fill(n, { from.rrand(to) }) }
		{ curve == \lfo or: { curve == \sin } } {
			var center = (from + to) / 2, depth = (to - from).abs / 2;
			Array.fill(n, { |i|
				var phase = i / n * 2pi * rate;
				center + (sin(phase) * depth)
			})
		}
		{ curve == \step } {
			var nSteps = rate.max(1).asInteger;
			Array.fill(n, { |i|
				var idx = (i / (n / nSteps).max(1)).floor.asInteger.min(nSteps - 1);
				var vals = Array.interpolation(nSteps, from, to);
				vals[idx]
			})
		}
		{ curve == \drift } {
			var center = (from + to) / 2, amt = (to - from).abs / 2;
			var val = center;
			Array.fill(n, {
				val = (val + (amt * 0.3).rand2).clip(center - amt, center + amt);
				val
			})
		}
		{ curve == \env } {
			var env = Env([from, to, (from + to) / 2, from],
				[steps * 0.3, steps * 0.3, steps * 0.4].max(0.01), \lin);
			var totalDur = env.times.sum;
			Array.fill(n, { |i| env.at(i / n * totalDur) })
		}
		{ ~rampVals.(from, to, n, curve) }
	};
~envVals = { |levels, times, curves, steps|
		var n = steps.max(1).asInteger;
		var env = Env(levels, times, curves);
		var totalDur = times.sum;
		Array.fill(n, { |i|
			var t = if (n > 1) { i / (n - 1) * totalDur } { 0 };
			env.at(t)
		})
	};

	// High-resolution FX ramp event type
	Event.addEventType(\fxSet, {
		// §fx-chan name → the REAL Ndef through the rack's aliases: a bare name could create an
		// EMPTY Ndef («the effect is dead») while the modulation went nowhere (the bake path)
		var d = topEnvironment[\dsl], nd = ~fxTarget;
		if (d.notNil and: { d[\fxTargets].notNil }) { nd = d[\fxTargets].at(~fxTarget) ? ~fxTarget };
		Ndef(nd).set(~fxParam, ~fxVal);
	});

	// §fx-chan live FX path: an Ndef param is mapped onto an mb bus ONCE per deploy —
	// the core engine writes /f2_setb (fx locks = live base, fx ramps = ranked
	// layers, scope windows gate them), the Ndef reads the bus continuously. No
	// per-event .set and no \fxSet storms. Reserved proxy params are never mapped
	// (they would break routing/volume).
	// §fx-latch semantics: the bus KEEPS the last value the engine delivered —
	// a lock's value, once its window played, stays on the effect until the next
	// writer plays a different one. Nothing snaps back to a base between windows,
	// and the latch survives rack rebuilds (the bus outlives Ndef.clear and the
	// re-applied mapping picks it right back up).
	// Registries:
	//   ~f2FxBase[busKey] — the param's own pre-engine value (explicit .set or the
	//     source function's arg default), captured for seeding a FRESH bus and for
	//     manual resets: ~f2FxBase.keysValuesDo { |k, v| ~mbAt.(k).set(v) }.
	//   ~f2FxMaps[busKey] = [fxName, param] — every engine mapping ever requested,
	//     so ~f2FxReapply can re-map after ~makeRack rebuilds the rack (Ndef.clear
	//     wipes ALL mappings; before this, engine-driven fx went dead until the
	//     next structural redeploy — the "works after the fifth restart" bug).
	~f2FxBase = ~f2FxBase ? IdentityDictionary.new;
	~f2FxMaps = ~f2FxMaps ? IdentityDictionary.new;
	~f2FxMapReserved = Set[\amp, \out, \i_out, \gate, \fadeTime, \in, \tel_bus, \bus,
		\group, \addAction, \server, \instrument, \type, \dur, \sustain, \sendGate,
		\callback, \finish, \selfFree, \id, \freq, \midinote, \note, \degree];
	~f2FxMap = { |fxName, param, busKey|
		var p = param.asSymbol, k = busKey.asSymbol;
		var nd = fxName.asSymbol;
		if (~dsl.notNil and: { ~dsl[\fxTargets].notNil }) { nd = ~dsl[\fxTargets].at(nd) ? nd };
		if (~f2FxMapReserved.includes(p).not and: { ~mbAt.notNil }) {
			var existed = ((~mb.notNil) and: { ~mb[k].notNil }) or: { (~mbRaw.notNil) and: { ~mbRaw[k].notNil } };
			var b = ~mbAt.(k);
			// cur: a number → the param's own set value; nil → never set, take the
			// source function's arg default; the \cN map symbol → already mapped.
			var cur = try { Ndef(nd).nodeMap.at(p) } { nil };
			if (cur.isNil) {
				cur = try {
					var cn = Ndef(nd).controlNames.detect { |c| c.name == p };
					cn !? { cn.defaultValue };
				} { nil };
			};
			if (cur.isNumber) {
				~f2FxBase[k] = cur; // bookkeeping for manual resets
				// §fx-latch: seed ONLY a fresh bus (else mapping would snap the
				// param to 0 until the first delivery). An existing bus holds the
				// latched value — never overwrite it here.
				if (existed.not) { b.set(cur) };
			};
			~f2FxMaps[k] = [fxName.asSymbol, p];
			// TRAP: NodeProxy.map is an alias of .set, and a raw Bus converts to
			// its INDEX as a control input — `Ndef(nd).map(p, b)` was literally
			// setting the param to the bus number (mix := 214), never mapping it,
			// so fx locks/ramps did not move the effect at all. bus.asMap (\cN)
			// is what the server understands as "map this control to bus N", and
			// the proxy re-sends it from its nodeMap on every source rebuild.
			try { Ndef(nd).set(p, b.asMap) } { |err|
				("⚠ [f2FxMap] " ++ fxName ++ "." ++ param ++ ": " ++ err.errorString).postln };
		};
	};
	// Re-map every registered engine fx param — called by ~makeRack / the front
	// rack deploy after a rack rebuild (their Ndef clear dropped all mappings).
	// The latched bus values survive the rebuild and the mapping picks them back
	// up. /f2_fxsync then tells the core to forget its fx diffs and re-send all
	// live values — guards active writers against fresh-bus seeding.
	~f2FxReapply = {
		if (~f2FxMaps.size > 0) {
			("[f2] fx remap after rack rebuild: " ++ ~f2FxMaps.size ++ " param(s)").postln;
			~f2FxMaps.keysValuesDo { |k, np| ~f2FxMap.(np[0], np[1], k) };
			(~f2CoreAddr ? ~f2BackendAddr ? NetAddr("127.0.0.1", 57121)).sendMsg('/f2_fxsync');
		};
	};
	// /f2_fxrest <scKey…> — MANUAL reset tool (the core does not send it under
	// §fx-latch): snap the named sinks back to their captured pre-engine values.
	// No args = reset every captured sink. Console: ~f2FxHome.value.
	OSCdef(\f2_fxrest, { |msg|
		topEnvironment.use {
			var i = 1;
			while { i < msg.size } {
				var k = msg[i].asSymbol, base = ~f2FxBase[k];
				if (base.isNumber and: { ~mbAt.notNil }) { ~mbAt.(k).set(base) };
				i = i + 1;
			};
			if (msg.size <= 1) { ~f2FxHome.value };
		};
	}, '/f2_fxrest').permanent_(true);
	// ~f2FxHome — return every engine-driven fx param to its own base value.
	~f2FxHome = {
		if (~mbAt.notNil) {
			~f2FxBase.keysValuesDo { |k, v| if (v.isNumber) { ~mbAt.(k).set(v) } };
			("[f2] fx home: " ++ ~f2FxBase.size ++ " param(s) reset").postln;
		};
	};

	// ═══════════════════════════════════════════════════════════
	// §reuse — SYNTH REUSE (persistent voices instead of a spawn per note)
	// ───────────────────────────────────────────────────────────
	// A pool of persistent synths PER PRESET (voices 1..16). A cell's event does NOT spawn a new
	// synth — it takes a voice from the pool, MAPS its modulatable arguments onto the per-cell
	// buses (~mbAt) and gates it. The voice is always alive (i_free=0), so grPos reads a bus that
	// is already filled from the base WITHOUT a birth race (the onset click goes away), and the
	// node count is bounded (≤ voices·presets). The toggle ~f2Reuse=false plus a redeploy gives
	// back the EXACT old behaviour (spawning). reattack: gate-off through sustain (0→1 on the next
	// note = a re-attack); legato: the gate stays at 1 (glide). Overlap inside the pool: a voice's
	// generation (gen) stops an old gate-off from cutting a new note on the same voice. Synths
	// without an \i_free control free themselves on release → the voice is recreated (a graceful
	// degradation to spawning); F2's own synths (sliceS/edge/matter) hold \i_free=0 → full reuse.
	// ═══════════════════════════════════════════════════════════
	~f2Reuse = ~f2Reuse ? true;
	~f2Voices = ~f2Voices ? IdentityDictionary.new;
	~f2VGroups = nil;   // §loop-order v2 migration: the old dictionary with its poisoned parent ivar goes
	// §reuse freeing a ROW's voices (a stop or a row switched off, AND the beginning of every
	//   deploy — see the compiler). Otherwise persistent i_free=0 voices hang about: legato and
	//   hold keep the gate up so the sound never dies. So they leave the dictionary at once, and
	//   set/free are sent with the error SUPPRESSED (a /f2/hush's ~f2PatGroup freeAll may already
	//   have taken them — «not found» must not spam). Gate off → .free after the tail (a soft
	//   release, if the node is still alive).
	//   CORRECTION, measured on 3.13.0: /g_freeAll does NOT kill silently. Freeing a group sends
	//   /n_end for every node under it — children, grandchildren and the groups among them — so a
	//   registered voice taken by a hush really does drop to isPlaying false, and the registries
	//   below are emptied for the sake of the pool's bookkeeping, not to work around a missing
	//   notification. The «/n_mapn Node not found» flood this note used to blame on that comes
	//   from the opposite case and is fixed at its own root — see §node-live just below: a node
	//   the server REFUSED never sends /n_go or /n_end at all.
	// §stack voice accessors. A pooled voice is either a plain Synth or a STACK
	// PROXY — an Event (grp: Group, nodes: id → Synth, out: output id) built by
	// mkVoice for a composite preset. §cards strips build the same proxy plus
	// `sink`: nodes = cards, out = the last on-card (the telId target only),
	// sink = the \f2chainOut output node that applies the PRESET level. Every
	// pool site goes through these accessors so both kinds behave identically:
	// nodeID comes from the group (n_set/n_map/n_free on a group reach all its
	// children); liveness needs the group AND every node; set/map demux
	// prefixed args `id__param` to the owning node (an id without a node —
	// bypassed / removed card — is dropped silently), broadcast the shared
	// gate/t_trig/freq to the group, and route un-prefixed unit params: a
	// stack sends them (amp, atk…) to its output node, a strip with a sink
	// sends `amp` and `out` to the sink and drops every other plain name (each
	// card's own params are `id__param`). §node-bus a plain `out` is the
	// preset's rack bus, set per event by \f2voice: it goes to the ONE node
	// that writes the preset's output (the sink, or a stack's output node),
	// never to the group — a broadcast would move every card off its stage
	// slot. §post a strip with a divider has NO sink per voice (post: true on
	// the proxy): the pool-level sink in pool[\post] takes `amp` and `out`,
	// set by \f2voice itself, and the demux drops them here. Bodies avoid
	// bare ~ (called from Event:play — see the note in f2units.scd).
	~f2VNode = { |v| if (v.isKindOf(Event)) { v[\grp].nodeID } { v.tryPerform(\nodeID) } };
	// §node-live A NODE THE SERVER REFUSED IS A CORPSE THAT NEVER LIVED, and
	// isPlaying cannot see it. When /s_new or /g_new is refused — the parent
	// group is gone, the server has not got that SynthDef, maxNodes is reached —
	// the client still has its Node object, `register(true)` has already put
	// isPlaying at TRUE, and no /n_go and no /n_end will ever arrive to take it
	// down again. So isPlaying stays true for the rest of the session, every
	// liveness guard below used to believe it, the pool never replaced that
	// voice, and every event went on addressing it. Measured on 3.13.0: one
	// «/n_mapn Node N not found» per mapped parameter per event — 23 of them per
	// event on the golden program, the same node id over and over, for as long
	// as the row plays, with the voice silent throughout.
	//
	// NodeWatcher sets isRunning only on a real /n_go, and register(true) does
	// NOT touch it (measured: a live node reads isPlaying true / isRunning true,
	// a refused one isPlaying true / isRunning false, and stays that way). So
	// isRunning is the SERVER's own confirmation, and this is the test every
	// guard uses: playing AND (confirmed, or still too young to have answered).
	// `at` is when the client sent the spawn (Main.elapsedTime); without one,
	// only a confirmation counts — which is right for a node old enough to be
	// asked about, and is why the stamp is kept next to every node the engine
	// may address within a moment of making it. Nothing here pauses nodes
	// (/n_run is never sent), so isRunning false on a confirmed node cannot
	// happen; if that ever changes this test needs a third state. The grace is a
	// SECOND, which is three orders of magnitude over a local server's round trip
	// and still short enough that a refused voice is replaced on the next event;
	// it is settable from the shell (`~f2NodeGrace = 2;`) for a server that is not
	// on this machine, and preserved across a reload of this file.
	~f2NodeGrace = ~f2NodeGrace ? 1.0;
	~f2NodeLive = { |n, at|
		n.notNil and: { n.isPlaying and: { n.isRunning
			or: { at.notNil and: { (Main.elapsedTime - at) < (topEnvironment[\f2NodeGrace] ? 1.0) } } } }
	};
	// §cards liveness: user SynthDefs from Synths/ use doneAction: 2 and have no
	// i_free — as a card such a node self-frees after its first release while
	// the voice group stays "playing"; judged by the group alone the pool never
	// respawned the slot and it stayed silent forever. Every card node (and the
	// sink) is registered at spawn, so a dead child marks the voice dead and
	// the pool respawns it (freeing the group first — nothing leaks).
	// §node-live `at` is the voice's spawn stamp (pool[\bornAt][idx]): inside the
	// grace an unconfirmed node counts as alive, because \f2voice maps a voice
	// in the same event that spawned it and the confirmation is still in flight.
	~f2VPlaying = { |v, at|
		var live = topEnvironment[\f2NodeLive];
		// §stack a group of copies is alive when its group and every copy are
		if (v.isKindOf(Event) and: { v[\copies].notNil }) {
			live.(v[\grp], at) and: { v[\copies].every { |c| topEnvironment[\f2VPlaying].value(c, at) } }
		} {
		if (v.isKindOf(Event)) {
			live.(v[\grp], at)
				and: { v[\nodes].values.every { |n| live.(n, at) } }
				and: { v[\sink].isNil or: { live.(v[\sink], at) } }
		} { live.(v, at) }
		}
	};
	~f2VDemux = { |v, args|   // flat [k, val …] → (shared: [...], per: id → [...], sink: [...])
		var shared = [], per = IdentityDictionary.new, sink = [];
		args.pairsDo { |k, val|
			// (`arg` is a reserved word in sclang — argument names are `an`)
			var ks = k.asString, i = ks.find("__"), id, an;
			if (i.notNil and: { i > 0 }) {
				id = ks.copyFromStart(i - 1).asSymbol;
				an = ks.copyToEnd(i + 2).asSymbol;
			};
			if (id.notNil) {
				// prefixed: to its node; no node (bypassed / removed card) → dropped, never per[nil]
				if (v[\nodes][id].notNil) { per[id] = (per[id] ? []) ++ [an, val] };
			} {
				if (#[\gate, \t_trig, \freq].includes(k)) { shared = shared ++ [k, val] } {
					if (v[\sink].notNil or: { v[\post] == true }) {
						// §cards strip: `amp` is the PRESET level (output node) and
						// `out` (§node-bus) the bus it writes; any other plain name has
						// no addressee. §post with a divider the sink is the pool's (no
						// per-voice sink, v[\sink] nil): the pair is collected and dropped
						// by ~f2VSet/~f2VMap — \f2voice addresses pool[\post][\sink] itself.
						if (k == \amp or: { k == \out }) { sink = sink ++ [k, val] };
					} {
						// stack (or a strip without f2units' output node): plain unit
						// params — `out` included (§node-bus) — go to the output node; an
						// empty strip has none (out = nil) and drops them (never a nil
						// key). Legacy strip layout (no sink) or a strip/stack whose
						// stage bus failed to allocate: only the output node follows a
						// per-event `out`; the other cards that write the out directly
						// keep the bus baked at spawn.
						v[\out] !? { |oid| per[oid] = (per[oid] ? []) ++ [k, val] };
					};
				};
			};
		};
		(shared: shared, per: per, sink: sink)
	};
	// §node-live THE PER-EVENT SET AND REMAP ARE BEST EFFORT, AND NOW SAY SO.
	// Every other send in this file that may reach a node that has just gone —
	// the gate-off, the soft retire, ~f2FreeSceneVoices, ~f2FreePost — already
	// goes out inside [\error, 0] … [\error, 1], because a node can die between
	// the decision and the packet for perfectly ordinary reasons (a doneAction:2
	// card self-freed, a hush took the group) and «Node not found» must not spam.
	// These two were the exception, and they are the two that run PER EVENT and
	// once PER PARAMETER: with the golden program's 23 mapped parameters that is
	// 23 lines an event, several times a second, for one voice the server never
	// made. The liveness fix above is what RECOVERS such a voice (it is replaced
	// on the next event); this is what keeps the window before the replacement,
	// and any genuinely transient death, down to nothing. The one thing worth
	// saying is said once, by name, where the voice is replaced.
	~f2SetQuiet = { |n, args|
		n !? { s.sendBundle(nil, [\error, 0], n.setMsg(*args), [\error, 1]) };
	};
	~f2MapQuiet = { |n, args|
		n !? { s.sendBundle(nil, [\error, 0], n.mapMsg(*args), [\error, 1]) };
	};
	~f2VSet = { |v, args|
		var quiet = topEnvironment[\f2SetQuiet];
		// §stack every copy takes the set (gate, freq, t_trig, plain params alike)
		if (v.isKindOf(Event) and: { v[\copies].notNil }) {
			v[\copies].do { |c| topEnvironment[\f2VSet].value(c, args) };
		} {
		if (v.isKindOf(Event)) {
			var d = topEnvironment[\f2VDemux].value(v, args);
			if (d[\shared].size > 0) { quiet.(v[\grp], d[\shared]) };
			d[\per].keysValuesDo { |id, a| quiet.(v[\nodes][id], a) };
			if (d[\sink].size > 0) { quiet.(v[\sink], d[\sink]) };
		} { quiet.(v, args) };
		}
	};
	~f2VMap = { |v, param, idx|
		var quiet = topEnvironment[\f2MapQuiet];   // §node-live see ~f2VSet above
		// §stack one bus for every copy (the gate, a channel gate): per-copy buses
		// go through the f2map loop of \f2voice, which addresses each copy itself
		if (v.isKindOf(Event) and: { v[\copies].notNil }) {
			v[\copies].do { |c| topEnvironment[\f2VMap].value(c, param, idx) };
		} {
		if (v.isKindOf(Event)) {
			var d = topEnvironment[\f2VDemux].value(v, [param, idx]);
			if (d[\shared].size > 0) { quiet.(v[\grp], d[\shared]) };
			d[\per].keysValuesDo { |id, a| quiet.(v[\nodes][id], a) };
			if (d[\sink].size > 0) { quiet.(v[\sink], d[\sink]) };
		} { quiet.(v, [param, idx]) };
		}
	};
	// §node-live a voice the client believes in that the SERVER never confirmed:
	// isPlaying true (register(true) put it there), isRunning still false past the
	// grace — its /s_new or /g_new was refused and made no node at all.
	~f2VRefused = { |v|
		var n = if (v.isKindOf(Event)) { v[\grp] } { v };
		n.notNil and: { n.isPlaying and: { n.isRunning.not } }
	};
	// §bus-gen freeing a stage-bus registry entry. An entry remembers the ALLOCATOR it took its
	// bus from: after s.newBusAllocators (a server reboot with sclang still alive) the allocator is
	// a new object, and an index from the previous life was long since handed to someone else, so
	// a .free would give them away someone else's live block. No match — just forget the entry.
	~f2StackBusRel = { |o|
		if (o.notNil and: { o[\alloc] === s.audioBusAllocator }) { try { o[\bus].free } };
	};
	// §bus-gen buries the PREVIOUS GENERATIONS of the same pool. poolKey is «row|preset@the group's
	// nodeID», and that nodeID changes on every hush or relaunch: entries of old generations stayed
	// in the registry forever together with their buses (nobody ever walked the registry), so over a
	// long session the server's audio bus pool was eaten up — Bus.audio started returning nil and a
	// voice event failed on `.index` of nil. A new generation buries all the previous ones: their
	// group is gone and nobody is left to read those buses. The freeing is deferred by 0.5 s — the
	// same headroom as the soft retirement in §cfg-sig: voices of the previous generation may still
	// be playing out their release, and the bus under them must not change owner instantly.
	// §bus-park THE RETIREMENT DELAY. A bus has to outlive the voices that read from it, and those
	// are freed on DIFFERENT clocks: a scene after 0.4 BEATS (TempoClock), the soft retirement of
	// §cfg-sig after 0.4 SECONDS. At a slow tempo 0.4 beats is nearly a second, and a fixed half
	// second would hand the index away under a voice that is still sounding. Hence the common
	// denominator: «after the voices, plus a tenth».
	~f2StackBusAfterBeats = { |beats = 0.4| ((beats * TempoClock.default.beatDur).max(0.4)) + 0.1 };
	// §bus-park retiring an entry. Every retirement site used to take the entry off the registry and
	// hold it ONLY in the closure of a deferred call — and CmdPeriod clears scheduled functions, so a
	// bus already off the books but not yet .free'd was lost without a single reference: exactly what
	// was being fixed, leaking. Now a retired entry waits in a list with ITS OWN due time, and any
	// later retirement drains everything that has matured — one lost call costs nothing any more. The
	// due time is on Main.elapsedTime, as everywhere else in this engine: the mark is set from a
	// TempoClock routine and drained on SystemClock, and the clock must not matter here.
	// §park-eps AND THAT LAST SENTENCE WAS THE MISTAKE: THE MARK AND THE WAKE COME
	// OFF DIFFERENT CLOCKS. The due time is
	// PHYSICAL (Main.elapsedTime, deliberately — see above), while
	// SystemClock.sched places the wake at the CALLING THREAD'S LOGICAL seconds
	// plus delay. Every real caller is inside a clock routine — ~f2DeckSync and
	// ~f2FreeSceneVoices are interpreted inside the eval drain's
	// Routine(…).play(TempoClock.default) — and a routine's logical seconds run
	// BEHIND physical by the scheduler's wake latency, measured at 2e-4 s here.
	// So the drain woke that much before its own entry was due, `due <= now` was
	// false for it, and the last entry of every burst was stranded: 20 of 20, not
	// the coin flip the shape suggests. And 2e-4 is the FLOOR: a real caller runs
	// in the middle of `c.interpret` of a whole deploy program, which advances no
	// logical time at all, so the lag is whatever that interpret costs — seconds,
	// on a content boot. Hence both halves. The 0.01 tolerance settles the bare
	// scheduler's lag in one wake; the re-schedule of whatever the drain KEPT is
	// what covers an arbitrarily large one, and the lost wake the comment above
	// worries about (CmdPeriod clears scheduled functions) with it. A drain is
	// only re-armed while something is still parked, so the chain ends itself.
	~f2StackBusRetire = { |e, delay = 0.5|
		var drain;
		if (e.notNil) {
			e[\due] = Main.elapsedTime + delay;
			topEnvironment[\f2StackBusParked] = (topEnvironment[\f2StackBusParked] ? []).add(e);
		};
		drain = {
			var now = Main.elapsedTime, keep = [];
			(topEnvironment[\f2StackBusParked] ? []).do { |o|
				if ((o[\due] ? 0) <= (now + 0.01)) {
					topEnvironment[\f2StackBusRel].value(o);
				} {
					keep = keep.add(o);
				};
			};
			topEnvironment[\f2StackBusParked] = keep;
			if (keep.size > 0) {
				SystemClock.sched((keep.collect { |o| o[\due] ? 0 }.minItem - now).max(0.01), drain);
			};
			nil
		};
		SystemClock.sched(delay, drain);
	};
	~f2StackBusGen = { |reg, poolKey|
		var ps = poolKey.asString, at, pre;
		ps.do { |c, i| if (c == $@) { at = i } };
		if (at.notNil) {
			pre = ps.copyRange(0, at);            // «row|preset@», the boundary is the @
			reg.keys.asArray.do { |k|
				if (k != poolKey and: { k.asString.beginsWith(pre) }) {
					topEnvironment[\f2StackBusRetire].value(reg[k],
						topEnvironment[\f2StackBusAfterBeats].value(0.4));
					reg.removeAt(k);
				};
			};
		};
	};
	// §stack private route buses per pool: one stereo slot per (source unit ×
	// voice), reused across respawns of the same pool; reallocated only when
	// the slot count changes (graph or voices edited).
	~f2StackBusAt = { |poolKey, pairs|
		var reg = topEnvironment[\f2StackBus];
		var e, n = pairs.max(1);
		if (reg.isNil) { reg = IdentityDictionary.new; topEnvironment[\f2StackBus] = reg };
		e = reg[poolKey];
		if (e.isNil or: { e[\n] != n }) {
			e !? { |o| topEnvironment[\f2StackBusRel].value(o) };
			if (e.isNil) { topEnvironment[\f2StackBusGen].value(reg, poolKey) };
			e = (bus: Bus.audio(s, 2 * n), n: n, alloc: s.audioBusAllocator);
			// An empty allocator returns nil. That nil entry used to GO INTO THE REGISTRY, and the
			// pool stayed broken for the rest of the session even after the buses were freed: the
			// next call saw e[\n] == n and handed back the same nil. Do not cache a failure — and say
			// so out loud, because otherwise it is just silence.
			if (e[\bus].isNil) {
				reg.removeAt(poolKey);
				e = nil;
				("✗ f2: cannot allocate a stack bus (% ch) for pool % — the server's audio bus pool is exhausted; raise s.options.numAudioBusChannels and reboot the server").format(2 * n, poolKey).postln;
			} {
				reg[poolKey] = e;
			};
		};
		if (e.isNil) { nil } { e[\bus] }
	};

	// §post STATIC BUS MAPS. A post card (a strip's singleton processor, see
	// §post in \f2voice) is mapped ONCE at spawn onto the preset-level bus of
	// each of its live params — there is no per-event remap for it, so when
	// f2_modsmooth creates the SMOOTHER of that key later (the core flags the
	// key as modulated on its first ramp), nobody would move the node from the
	// raw bus to the smoothed one. The registry remembers (node, param) per
	// key; ~f2FlagApply calls ~f2SmoothHook right after it creates a smoother
	// and the hook remaps every registered consumer of the key. Entries leave
	// with their post group (~f2FreePost) or when the node is found dead.
	// Bodies avoid bare ~ (the hook runs inside the OSCdef's topEnvironment.use,
	// the registration inside Event:play).
	~f2StaticMaps = ~f2StaticMaps ?? { IdentityDictionary.new };
	~f2StaticMapAdd = { |key, node, param, grp|
		var reg = topEnvironment[\f2StaticMaps];
		if (reg.isNil) { reg = IdentityDictionary.new; topEnvironment[\f2StaticMaps] = reg };
		// §node-live `at` is the spawn stamp the liveness test needs (see ~f2NodeLive)
		reg[key] = (reg[key] ? []).add((node: node, param: param, grp: grp, at: Main.elapsedTime));
	};
	~f2SmoothHook = { |k, sm|
		var reg = topEnvironment[\f2StaticMaps];
		var list = reg !? { reg[k] };
		var kept = [];
		if (list.notNil and: { sm.notNil }) {
			list.do { |e|
				// §node-live isPlaying alone kept a node the server had REFUSED here for
				// the rest of the session, and the hook remapped it on every key it owns
				// — one «/n_mapn Node N not found» per key, the same id
				if (topEnvironment[\f2NodeLive].(e[\node], e[\at])) {
					e[\node].map(e[\param], sm.index);
					kept = kept.add(e);
				};
			};
			if (kept.size == 0) { reg.removeAt(k) } { reg[k] = kept };
		};
	};
	// §post freeing a pool's post group: n_free on the group (error suppressed —
	// a hush may have taken it already) and its static-map entries dropped.
	~f2FreePost = { |p|
		var reg = topEnvironment[\f2StaticMaps];
		if (p.notNil and: { p[\grp].notNil }) {
			s.sendBundle(nil, [\error, 0], [\n_free, p[\grp].nodeID], [\error, 1]);
			reg !? {
				reg.keys.asArray.do { |k|
					var kept = reg[k].reject { |e| e[\grp] === p[\grp] };
					if (kept.size == 0) { reg.removeAt(k) } { reg[k] = kept };
				};
			};
		};
	};

	~f2FreeSceneVoices = { |sceneKey|
		var pre = sceneKey.asString ++ "|";
		var sreg = topEnvironment[\f2StackBus];
		(~f2Voices ? IdentityDictionary.new).keys.do { |k|
			if (k.asString.beginsWith(pre)) {
				var pool = ~f2Voices[k];
				~f2Voices.removeAt(k);
				if (pool.notNil) {
					pool[\synths].do { |sy| if (sy.notNil) {
						s.sendBundle(nil, [\error, 0], [\n_set, ~f2VNode.(sy), \gate, 0], [\error, 1]);
					} };
					// §post the pool's post group goes with the voices, after their
					// release (it is what the releasing voices sound through)
					TempoClock.default.sched(0.4, { pool[\synths].do { |sy| if (sy.notNil) {
						s.sendBundle(nil, [\error, 0], [\n_free, ~f2VNode.(sy)], [\error, 1]);
					} }; pool[\post] !? { |p| topEnvironment[\f2FreePost].value(p) }; nil });
				};
			};
		};
		// §bus-gen stopping a row takes ITS stage buses too. This function did not touch the
		// ~f2StackBus registry at all, so every (row × preset) that had played even once in a session
		// held its stereo pack until the server was rebooted — and scsynth has one audio bus pool for
		// everything. They are freed with the same 0.4 s deferral as the voices: those are playing out
		// their release on exactly these buses.
		sreg !? { |reg|
			reg.keys.asArray.do { |k|
				if (k.asString.beginsWith(pre)) {
					topEnvironment[\f2StackBusRetire].value(reg[k],
						topEnvironment[\f2StackBusAfterBeats].value(0.4));
					reg.removeAt(k);
				};
			};
		};
	};
	// ═══════════════════════════════════════════════════════════
	// §scope-deck — DECKS ON TREE NODES AND BLOCKS
	// (docs/design/SCOPE-DECKS.md §5 stage 5, docs/wiki/Decks.md, SYNTH-MODULES.md "Decks")
	// ───────────────────────────────────────────────────────────
	// Every tree container and every block owns a DECK: a strip of sound-
	// PROCESSING singleton cards (processors with a chainIn — no sources, no
	// modulators), empty by default. A deck is ONE instance per (row × scope),
	// alive on silence (a reverb tail rings out over a rest, a knob turned in
	// silence is heard the moment a note lands), created at deploy, KEPT across
	// redeploys while its cards are unchanged, freed when the row stops or the
	// deck is removed. The ROUTING is the compilers' (session builders, both
	// engines): a node's deck processes only the children that INHERIT its bus;
	// a child that overrides the bus is its own exit into the rack. So every
	// event carries `f2deck: '<scope>'` — the deck it feeds — and the ~enrich
	// wrapper asks ~f2DeckIn.(row, scope) for that deck's IN pair and puts it on
	// the event's \out (the existing per-event out path of \f2voice — voice
	// outAt / pool[\postOut] — applies it; nothing in \f2voice changes); nil →
	// the event falls back to its outBus.
	//
	// THE REGISTRY ~f2Decks: rowKey → (scopeSymbol → entry). An entry: grp (the
	// deck's Group inside ~f2DeckGroup), nodes (id → Synth), nodeCtl (id → the
	// def's control names), sink (\f2chainOut, amp 1: a deck has no level of its
	// own), bus (Bus.audio(s, 2·(deckN+1)): pair 0 = the deck's IN pair, pairs
	// 1..deckN the stages — card i reads i, writes i+1, the last writes -1 = the
	// sink's input, pair deckN), sig, depth, scope, sinkScope, busName, outIdx,
	// at (creation time). THE LADDER ~f2DeckGroup: one Group.after(~f2PatGroup)
	// — every voice executes before it (voices live in ~f2PatGroup, at the head
	// of the default group; the /f2/eval handler recreates that group at the
	// head before every eval, so a deck group created after ANY pattern group
	// sits after all of them) and the rack groups (Group.tail at the rack
	// deploy) after it. Created lazily; when ~f2PatGroup is nil the deck group
	// is Group.tail(s.defaultGroup) with a warning once (the rack then reads
	// its buses BEFORE the decks write them — a deck routed to the rack is
	// lost until the next deploy recreates the pattern group).
	// Inside the ladder the decks of a row execute DEEPEST FIRST: ~f2DeckSync
	// moves the row's deck groups to the tail of ~f2DeckGroup by depth
	// descending (ties by scope string), so a child's output is read by its
	// parent in the same cycle (In.ar, no delay, exactly like the rack's
	// pipeline). Decks of other rows keep their relative order — they write
	// rack buses or their own row's decks only.
	//
	// ~f2DeckSync.(rowKey, defs) — the compiled program's sync line (both
	// compilers, ALWAYS emitted, right after ~f2FreeSceneVoices and before
	// ~play): defs = [(scope, depth, cards: [(id, unit, opts?, rd, wr)…],
	// deckN, deckMap: [\id__param, \scKey …] (live) | deckArgs: [\id__param,
	// value …] (bake), sink: '<scope>'|nil, bus: \name|nil)…] deepest first.
	// (a) every registered deck of the row whose scope is absent from defs is
	// freed (an empty list frees them all); (b) per def a SIGNATURE (scope,
	// depth, cards id:unit:opts:rd:wr@variant, deckN, the deckMap pairs or the
	// deckArgs) — an entry with the same sig is KEPT, its tails survive, only
	// its sink target is refreshed; a different sig frees the old entry and
	// builds a new one (its bus is REUSED when the pair count is unchanged, so
	// the IN pair the sounding voices already write stays valid); (c) the
	// build: one Synth per card via the unit's SynthDef variant (~f2UnitDef —
	// the deploy's ~f2UnitEnsure lines built it), args [\out <wr pair | sink
	// input>, \gate 1, \chainIn <rd pair>] + [\i_free 0] when the def has it,
	// the tempo bus mapped when it has \tempo, a card without chainIn is
	// spawned but its stream dropped (warned once, like mkPost), a card whose
	// def is missing is skipped (~f2UnitGone); then the sink LAST; (d) the OUT
	// of a deck, resolved in a SECOND pass once every deck of the row exists
	// (a child needs its parent's IN pair, and the parent is built after it):
	// sink notNil → that deck's IN pair (~f2DeckIn), else bus notNil →
	// ~rack.bus[bus].index, else ~rack.bus[\main].index, else 0; (e) the
	// order (above); (f) params — live: every (\id__param, \scKey) of deckMap
	// whose node declares the param is mapped ONCE onto ~mbAt.(key) and
	// registered with ~f2StaticMapAdd so the smoother created later for that
	// key remaps it (~f2SmoothHook, exactly like a post card); bake: deckArgs
	// are plain synth args at creation. A deck param never rides an event (no
	// per-cell key, no f2map, no init line).
	// ~f2DeckIn.(rowKey, scope) → the IN pair index or nil (no such deck, or
	// its bus could not be allocated — the allocation failure is posted at
	// every failed build, like ~f2StackBusAt; the event then falls back to its
	// outBus).
	// ~f2FreeSceneDecks.(rowKey) — the row's stop snippet (conductor Stop /
	// stopRowPdef): the row's decks leave the registry at once and are FREED
	// after the voices' release (~f2StackBusAfterBeats.(0.4) ≥ 0.5 s — the
	// releasing voices sound through them, the post-group pattern): n_free the
	// group with the error suppressed, the static-map entries of the group
	// dropped, the bus freed. ~f2FreeAllDecks — /f2/hush: every deck of every
	// row at once (groups, buses, static maps, registry cleared) right after
	// ~f2PatGroup.freeAll — decks live outside the pattern group, a hush would
	// otherwise leave them running.
	// LIMITS: no ports, no telId, no resource buffers (sample / IR / curve) on
	// a deck card; bake mode bakes the values (a value change rebuilds the
	// deck — its tail restarts); a bus-allocation failure bypasses the deck.
	// Bodies avoid bare ~ (~f2DeckIn runs inside Event play through the
	// wrapper; the frees run from the hush OSCdef and from deferred clocks) —
	// a local `top` as \f2voice does; the rack is read through globalEnv
	// exactly as ~enrich reads it.
	~f2Decks = ~f2Decks ?? { IdentityDictionary.new };
	~f2DeckWarn = { |key, msg|
		var top = topEnvironment;
		if (top[\f2UnitWarnOnce].notNil) { top[\f2UnitWarnOnce].(key, msg) } {
			var seen = top[\f2DeckWarned];
			if (seen.isNil) { seen = IdentitySet.new; top[\f2DeckWarned] = seen };
			if (seen.includes(key.asSymbol).not) { seen.add(key.asSymbol); msg.postln };
		};
		nil
	};
	// the ladder group (lazy). register(true) assumes the group playing at
	// once; isPlaying turns false only when the server reports its end (a hush
	// does not free it, a CmdPeriod does). A group younger than a second is
	// trusted as it is; an older one that is not playing (dead, or created
	// against a stale target) is replaced.
	~f2DeckGroupAt = {
		var top = topEnvironment;
		var g = top[\f2DeckGroup];
		var pg = top[\f2PatGroup];
		var at = top[\f2DeckGroupAtT] ? 0;
		// §node-live confirmed by the server, or young enough not to have answered
		// yet (~f2NodeLive); isPlaying alone also believed a group whose /g_new was
		// refused, and every deck built into it was silent for the session
		if (g.isNil or: { topEnvironment[\f2NodeLive].(g, at).not }) {
			if (pg.notNil) {
				g = Group.after(pg);
			} {
				g = Group.tail(s.defaultGroup);
				top[\f2DeckWarn].value(\deck_group_tail,
					"⚠ [f2 deck] no pattern group — the deck group sits at the TAIL of the default group, after the rack: decks routed to a rack bus are silent until the next deploy");
			};
			g.register(true);
			top[\f2DeckGroup] = g;
			top[\f2DeckGroupAtT] = Main.elapsedTime;
		};
		g
	};
	// the resolved def of a deck card: the unit's SynthDef VARIANT for its opts
	// (~f2UnitDef — the base def until the variant is built), the unit itself
	// without opts or without f2units.
	~f2DeckCardDef = { |c|
		var top = topEnvironment;
		if (c[\opts].notNil and: { top[\f2UnitDef].notNil })
			{ top[\f2UnitDef].(c[\unit], c[\opts]) ? c[\unit].asSymbol } { c[\unit].asSymbol }
	};
	// the signature a kept deck is compared by (see (b) above); a String
	~f2DeckSig = { |d|
		var top = topEnvironment;
		var sg = d[\scope].asString ++ "#" ++ (d[\depth] ? 0).asString ++ "|c";
		(d[\cards] ? []).do { |c|
			var udef = top[\f2DeckCardDef].value(c);
			sg = sg ++ c[\id].asString ++ ":" ++ c[\unit].asString ++ ":"
				++ (c[\opts] !? { |o| o.keys.asArray.collect(_.asString).sort.collect { |kk|
					kk ++ "=" ++ (o[kk.asSymbol] ? o[kk]).asString }.join(",") } ? "")
				++ ":" ++ (c[\rd] ? 0).asString ++ ":" ++ (c[\wr] ? (-1)).asString
				++ (if (udef != c[\unit].asSymbol) { "@" ++ udef.asString } { "" }) ++ ";";
		};
		sg = sg ++ "|n" ++ (d[\deckN] ? 0).asString;
		d[\deckMap] !? { |m| sg = sg ++ "|m"; m.pairsDo { |k, v| sg = sg ++ k.asString ++ "=" ++ v.asString ++ ";" } };
		d[\deckArgs] !? { |m| sg = sg ++ "|a"; m.pairsDo { |k, v| sg = sg ++ k.asString ++ "=" ++ v.asString ++ ";" } };
		sg
	};
	// freeing ONE entry: n_free on its group (error suppressed — a hush or a
	// server restart may have taken it), its static-map entries dropped (by
	// group, like ~f2FreePost), its bus freed unless the caller keeps it for
	// the rebuilt deck (keepBus).
	~f2DeckFree = { |e, keepBus = false|
		var top = topEnvironment;
		var reg = top[\f2StaticMaps];
		if (e.notNil) {
			e[\grp] !? { |g|
				s.sendBundle(nil, [\error, 0], [\n_free, g.nodeID], [\error, 1]);
				reg !? {
					reg.keys.asArray.do { |k|
						var kept = reg[k].reject { |x| x[\grp] === g };
						if (kept.size == 0) { reg.removeAt(k) } { reg[k] = kept };
					};
				};
			};
			// the bus: freed only when it came from the CURRENT allocator (after a
			// server reboot an old index belongs to someone else — ~f2StackBusRel)
			if (keepBus.not and: { e[\alloc] === s.audioBusAllocator }) { e[\bus] !? { |b| try { b.free } } };
			e[\bus] = nil;
			e[\grp] = nil;
		};
		nil
	};
	// the IN pair of a row's deck, or nil
	~f2DeckIn = { |rowKey, scope|
		var reg = topEnvironment[\f2Decks];
		var row = reg !? { reg[rowKey.asSymbol] };
		var e = row !? { row[scope.asSymbol] };
		if (e.notNil and: { e[\bus].notNil }) { e[\bus].index } { nil }
	};
	// the OUT of an entry (see (d) above)
	~f2DeckOutIdx = { |rowKey, e|
		var top = topEnvironment;
		var rack = globalEnv.at(\rack);
		var buses = rack !? { rack[\bus] };
		var idx;
		e[\sinkScope] !? { |sc| idx = top[\f2DeckIn].value(rowKey, sc) };
		if (idx.isNil and: { e[\busName].notNil } and: { buses.notNil }) {
			idx = buses[e[\busName].asSymbol] !? { |b| b.index };
		};
		if (idx.isNil and: { buses.notNil }) { idx = buses[\main] !? { |b| b.index } };
		idx ? 0
	};
	// building ONE deck (see (c) above); nil when \f2chainOut is not loaded
	// (said once) or the bus could not be allocated (said at every attempt).
	// `oldBus` = the bus of the entry this one replaces, when its pair count
	// fits.
	~f2DeckBuild = { |rowKey, d, sig, oldBus|
		var top = topEnvironment;
		var scope = d[\scope].asSymbol;
		var cards = d[\cards] ? [];
		var n = (d[\deckN] ? cards.size).asInteger.max(0);
		var dArgs = d[\deckArgs], dMap = d[\deckMap];
		var bus, grp, sink, e, pair;
		var nodes = IdentityDictionary.new, nodeCtl = IdentityDictionary.new;
		if (SynthDescLib.global.at(\f2chainOut).isNil) {
			top[\f2DeckWarn].value(\deck_nosink,
				"⚠ [f2 deck] \\f2chainOut is not loaded (f2units missing) — decks are bypassed until it is");
			nil
		} {
			bus = if (oldBus.notNil and: { oldBus.numChannels == (2 * (n + 1)) }) { oldBus } { Bus.audio(s, 2 * (n + 1)) };
			if (bus.isNil) {
				("✗ f2: cannot allocate a deck bus (% ch) for % of row % — the server's audio bus pool is exhausted; raise s.options.numAudioBusChannels and reboot the server. The deck is bypassed.").format(2 * (n + 1), scope, rowKey).postln;
				nil
			} {
				pair = { |j| bus.index + (2 * j) };
				grp = Group.new(top[\f2DeckGroupAt].value, \addToTail);
				grp.register(true);
				cards.do { |c|
					var id = c[\id].asSymbol;
					var udef = top[\f2DeckCardDef].value(c);
					var ud = SynthDescLib.global.at(udef);
					var uc = if (ud.notNil) { ud.controlNames } { [] };
					var rd = (c[\rd] ? 0).asInteger.max(0), wr = (c[\wr] ? (-1)).asInteger;
					var ua = [\out, pair.(if (wr < 0) { n } { wr }), \gate, 1];
					if (uc.includes(\chainIn)) {
						ua = ua ++ [\chainIn, pair.(rd)];
					} {
						if (ud.notNil) {
							top[\f2DeckWarn].value(("deck_chainIn_" ++ udef.asString).asSymbol,
								"⚠ [f2 deck] %: card % (%) reads deck stage % but has no chainIn — stream dropped".format(scope, id, udef, rd));
						};
					};
					if (uc.includes(\i_free)) { ua = ua ++ [\i_free, 0] };
					// bake: this card's baked values (`id__param` split like mkPost splits pstMap)
					if (dArgs.notNil) {
						var pre = id.asString ++ "__";
						dArgs.pairsDo { |pk, v|
							var ks = pk.asString;
							if (ks.beginsWith(pre) and: { v.isNumber }) {
								var an = ks.copyToEnd(pre.size).asSymbol;
								if (uc.includes(an)) { ua = ua ++ [an, v] };
							};
						};
					};
					if (ud.notNil) {
						var nd = Synth(udef, ua, grp, \addToTail);
						nd.register(true);
						if (uc.includes(\tempo) and: { top[\f2TempoBus].notNil }) {
							nd.map(\tempo, top[\f2TempoBus].index);
						};
						nodes[id] = nd;
						nodeCtl[id] = uc;
					} {
						if (top[\f2UnitGone].notNil) {
							top[\f2UnitGone].(c[\unit], "deck " ++ scope.asString, id);
						} {
							("⚠ [f2 deck] %: card % has no SynthDef % — card skipped, and everything after it is silent".format(scope, id, udef)).postln;
						};
					};
				};
				e = (grp: grp, nodes: nodes, nodeCtl: nodeCtl, bus: bus, alloc: s.audioBusAllocator, sig: sig, scope: scope,
					deckN: n, depth: (d[\depth] ? 0).asInteger, at: Main.elapsedTime,
					sinkScope: d[\sink] !? { |x| x.asSymbol }, busName: d[\bus] !? { |x| x.asSymbol });
				// the sink LAST: the final pair → a preliminary out (the second pass
				// of ~f2DeckSync refreshes it once every deck of the row exists)
				e[\outIdx] = top[\f2DeckOutIdx].value(rowKey, e);
				sink = Synth(\f2chainOut, [\in, pair.(n), \out, e[\outIdx], \amp, 1], grp, \addToTail);
				sink.register(true);
				e[\sink] = sink;
				// live: the static maps (top.use: ~mb/~mbSm live inside ~mbAt)
				if (dMap.notNil) {
					top.use {
						dMap.pairsDo { |pk, key|
							var ks = pk.asString, i = ks.find("__"), id, an, nd, b;
							if (i.notNil and: { i > 0 }) {
								id = ks.copyFromStart(i - 1).asSymbol;
								an = ks.copyToEnd(i + 2).asSymbol;
								nd = nodes[id];
							};
							// a param the node's def declares; an id without a node (a
							// skipped card) or an unknown param is dropped silently
							if (nd.notNil and: { (nodeCtl[id] ? []).includes(an) }) {
								b = ~mbAt.(key.asSymbol);
								if (b.notNil) {
									nd.map(an, b.index);
									top[\f2StaticMapAdd].(key.asSymbol, nd, an, grp);
								};
							};
						};
					};
				};
				e
			}
		}
	};
	// the sync (see above)
	~f2DeckSync = { |rowKey, defs|
		var top = topEnvironment;
		var reg = top[\f2Decks];
		var rk = rowKey.asSymbol;
		var row, dg, ordered;
		if (reg.isNil) { reg = IdentityDictionary.new; top[\f2Decks] = reg };
		row = reg[rk];
		if (row.isNil) { row = IdentityDictionary.new; reg[rk] = row };
		defs = defs ? [];
		// (a) vanished decks
		// §deck-retire THE GROUP MAY GO NOW, THE BUS MAY NOT. This used to call
		// ~f2DeckFree with keepBus at its default false, which hands the index
		// back to s.audioBusAllocator in the same instant — and the compiled
		// program emits ~f2FreeSceneVoices one line BEFORE this sync
		// (src/lib/compiler.ts), which only gates the row's voices and frees them
		// 0.4 beats later. So a voice still writing this deck's IN pair is
		// guaranteed, not likely. Measured: the very next Bus.audio of the same
		// width was handed the vanished deck's index, and a synth left writing it
		// metered 0.27 on a deck of an UNRELATED row — the one allocator serves
		// every Bus.audio in the engine, so a stage bus or a rack bus can catch it
		// just as easily. The rebuild in (b) and the row stop in ~f2FreeSceneDecks
		// already park theirs for exactly this reason; this was the one path left.
		row.keys.asArray.do { |sc|
			if (defs.detect { |d| d[\scope].asSymbol == sc }.isNil) {
				var e = row[sc];
				// a bus from a previous server life is only forgotten, as everywhere
				var oldBus = if (e.notNil and: { e[\alloc] === s.audioBusAllocator }) { e[\bus] };
				top[\f2DeckFree].value(e, true);
				oldBus !? { top[\f2StackBusRetire].value((bus: oldBus, alloc: s.audioBusAllocator),
					top[\f2StackBusAfterBeats].value(0.4)) };
				row.removeAt(sc);
			};
		};
		// (b)/(c) keep or rebuild, in the given order (deepest first)
		defs.do { |d|
			var sc = d[\scope].asSymbol;
			var sig = top[\f2DeckSig].value(d);
			var e = row[sc];
			var oldBus;
			if (e.notNil and: { sig != e[\sig]
				or: { e[\grp].isNil }
				or: { top[\f2NodeLive].(e[\grp], e[\at]).not } }) {   // §node-live
				// its bus is handed to the rebuild (reused when the pair count fits,
				// else RETIRED after the voices' release — the sounding voices still
				// write it); a bus from a previous server life is only forgotten
				if (e[\alloc] === s.audioBusAllocator) { oldBus = e[\bus] };
				top[\f2DeckFree].value(e, true);
				row.removeAt(sc);
				e = nil;
			};
			if (e.isNil) {
				e = top[\f2DeckBuild].value(rk, d, sig, oldBus);
				if (e.notNil) { row[sc] = e };
				if (oldBus.notNil and: { e.isNil or: { e[\bus] !== oldBus } }) {
					top[\f2StackBusRetire].value((bus: oldBus, alloc: s.audioBusAllocator),
						top[\f2StackBusAfterBeats].value(0.4));
				};
			} {
				// kept: only its target is refreshed
				e[\sinkScope] = d[\sink] !? { |x| x.asSymbol };
				e[\busName] = d[\bus] !? { |x| x.asSymbol };
				e[\depth] = (d[\depth] ? 0).asInteger;
			};
		};
		// (d) second pass: every sink target, now that every deck of the row exists
		row.keysValuesDo { |sc, e|
			var idx = top[\f2DeckOutIdx].value(rk, e);
			if (e[\outIdx] != idx) {
				e[\outIdx] = idx;
				e[\sink] !? { |sk| sk.set(\out, idx) };
			};
		};
		// (e) deepest first inside the ladder
		if (row.size > 0) {
			dg = top[\f2DeckGroupAt].value;
			ordered = row.values.asArray.sort { |a, b|
				(a[\depth] > b[\depth]) or: {
					(a[\depth] == b[\depth]) and: { a[\scope].asString < b[\scope].asString } }
			};
			ordered.do { |e| e[\grp] !? { |g| g.moveToTail(dg) } };
		} {
			reg.removeAt(rk);
		};
		nil
	};
	// a row's stop: off the registry now, freed after the voices' release
	~f2FreeSceneDecks = { |rowKey|
		var top = topEnvironment;
		var reg = top[\f2Decks];
		var rk = rowKey.asSymbol;
		var row = reg !? { reg[rk] };
		if (row.notNil) {
			reg.removeAt(rk);
			SystemClock.sched(top[\f2StackBusAfterBeats] !? { |f| f.value(0.4) } ? 0.5, {
				row.values.asArray.do { |e| top[\f2DeckFree].value(e) };
				nil
			});
		};
		nil
	};
	// /f2/hush: every deck of every row, at once
	~f2FreeAllDecks = {
		var top = topEnvironment;
		var reg = top[\f2Decks];
		var dg = top[\f2DeckGroup];
		reg !? {
			reg.values.asArray.do { |row| row.values.asArray.do { |e| top[\f2DeckFree].value(e) } };
			reg.clear;
		};
		// belt and braces: whatever the bookkeeping missed inside the ladder
		dg !? { |g| s.sendBundle(nil, [\error, 0], [\g_freeAll, g.nodeID], [\error, 1]) };
		nil
	};
	Event.addEventType(\f2voice, { |server|
		var ev = currentEnvironment;
		var top = topEnvironment;
		var def = ev[\f2def];
		var cfg = ev[\f2cfg] ? IdentityDictionary.new;
		var instr = ev[\instrument];
		// §fix ev[\group] IN THE EVENT is a LAZY function (not a Node), and .nodeID on it failed
		//   («Message 'nodeID' not understood»). Take the REAL pattern group ~f2PatGroup: that is what
		//   Pdef plays into and what a redeploy or hush frees → the voices are cleaned up correctly.
		var grp = top[\f2PatGroup];
		var sd = SynthDescLib.global.at(instr);
		var ctrl = if (sd.notNil) { sd.controlNames } { [] };
		// §stack composite preset: cfg[\stack] = [(id, unit, ins: (arg: srcId)…)],
		// cfg[\stackOut] = output id. The voice's control set is the union of
		// every sub-unit's controls under `id__` prefixes plus the shared
		// gate/t_trig/freq/out/buf and the output unit's plain names (so an
		// un-prefixed amp/atk… addresses the output node).
		var stk = cfg[\stack];
		// §cards strip preset: cfg[\chain] = [(id, unit, opts?, rd, wr)…] — the ON
		// cards in strip order, cfg[\chainN] = number of private stages. The LAST
		// card writes the preset's out and owns the un-prefixed unit params. A
		// card with `opts` spawns a SynthDef VARIANT (~f2UnitDef in f2units);
		// chnDef caches id → resolved def name for this event (ctrl union,
		// mkVoice and the pool fingerprint all read it).
		var chn = cfg[\chain];
		var chnDef;
		// §cards-out the strip's output node (\f2chainOut, f2units): when its def
		// is loaded the final stage is a private slot and the bare `amp` is the
		// PRESET level; without it the last cards write the out directly (legacy
		// layout — cfgSig |sink0 respawns the pool once f2units arrives).
		var hasSink = false;
		// §post THE STRIP DIVIDER (docs/design/SCOPE-DECKS.md §5 stage 4,
		// docs/wiki/Card-Chains.md "The divider"): cfg[\post] = [(id, unit,
		// opts?, rd, wr)…] — the ON cards RIGHT of the divider, the preset's
		// SINGLETON processors: one instance per pool, never multiplied by
		// voices or copies, reading the SUM of every voice's (and copy's) final
		// stage. They live in a pool-level POST GROUP after the preset's voice
		// subgroup (pool[\post]: grp, nodes, sink, bus), with their own stage
		// numbering (rd 0 = the post-in pair, wr -1 = the sink's input) and
		// cfg[\postN] private post stages; cfg[\postMap] = [\id__param, \scKey
		// …] names the PRESET-LEVEL bus of every live post param — mapped once
		// at spawn (§post static maps, ~f2StaticMaps). Absent = no divider =
		// today's strip exactly (the layout below changes only when hasPost).
		var pst = cfg[\post];
		var pstN = (cfg[\postN] ? 0).asInteger;
		var pstMap = cfg[\postMap];
		var hasPost = false;
		var pstDef;
		var nStage = 0, postFinal = 0, postOff = 0;
		var mkPost, resArgs, cardSig, voiceGrp;
		var nv = ((cfg[\voices] ? 1).clip(1, 16)).asInteger;
		// §stack copies inside every voice (docs/wiki/Polyphony.md §5): a stacked
		// voice is a GROUP of nk copies — each a plain synth, a §stack group or a
		// §cards strip — all on one note; copy ci reads its own buses `<key>_s<ci>`.
		var nk = ((cfg[\copies] ? 1).clip(1, 8)).asInteger;
		var artic = cfg[\artic] ? \reattack;
		var hasFree = (ev[\f2hasFree] ? false);
		var voices = top[\f2Voices];
		var poolKey;
		var reserved = Set[\gate, \out, \i_out, \tel_bus, \i_free, \instrument, \type, \group,
			\f2def, \f2cfg, \f2map, \f2hasFree, \f2_cid, \f2lane, \dur, \sustain, \legato, \delta,
			\addAction, \server, \callback, \finish, \sendGate, \selfFree, \id, \play, \parent, \buf];
		var mkVoice, mkOne, pool, voice, idx, myGen, setA, susBeats, durB, cfgSig, gateOff, vgrp;
		var offAtA, nowT, stillOpen, holdCont, respawned;
		var bornA;   // §node-live the pool's per-voice spawn stamps
		// §steal-x a hold onset landing on an OPEN voice of ANOTHER lane (see the
		// LIMITS of §hold-note): the new note attacks, the stolen one is cut
		var stealX = false;
		// §hold-note the boundary tolerance (seconds), the ending-voice finder, the
		// deferred-retire flag and the continued voice it names (see §hold-retire)
		var holdTol, endingV, deferHold = false, contIdx, holdHow;
		// one warning per key (~f2UnitWarnOnce when f2units is loaded, else a plain post)
		var warnOnce = { |key, msg|
			if (top[\f2UnitWarnOnce].notNil) { top[\f2UnitWarnOnce].(key, msg) } { msg.postln };
		};
		// §tape units with a \tempo control follow the global tempo bus
		// (~f2TempoBus, written at 60 Hz by f2_remote_eval): mapped right after
		// the spawn, in every spawn path (plain synth, stack cards, strip cards).
		var tempoMap = { |node, names|
			if (names.includes(\tempo) and: { top[\f2TempoBus].notNil }) {
				node.map(\tempo, top[\f2TempoBus].index);
			};
			node
		};

		// §cards a cfg naming BOTH stack: and chain: is malformed (the compilers
		// never emit both): the strip wins, the stack is ignored — warned once.
		// The stack and strip branches below are mutually exclusive either way.
		if (stk.notNil and: { chn.notNil }) {
			warnOnce.(("cfg_both_" ++ def.asString).asSymbol,
				"⚠ [f2 chain] %: cfg has both stack: and chain: — the strip is used, the stack ignored".format(def));
			stk = nil;
		};
		// §cards-orphan a composite preset whose cfg carries NO graph: the
		// ~f2ReuseCfg line was written by an engine that predates §cards (the
		// compilers always emit `chain:`, even for an empty strip), so there is
		// nothing to spawn. An EMPTY strip is the safe reading — the preset goes
		// silent and says so once. Falling through to the plain-synth branch
		// would send the server /s_new with the def name "chain".
		if (chn.isNil and: { stk.isNil } and: { #[\chain, \stack].includes(instr) }) {
			warnOnce.(("cfg_nograph_" ++ def.asString).asSymbol,
				"⚠ [f2 chain] %: instrument % but its ~f2ReuseCfg line carries no chain:/stack: — the preset is SILENT (the engine that compiled it predates §cards: rebuild core/f2core)".format(def, instr));
			chn = [];
		};
		hasSink = chn.notNil and: { SynthDescLib.global.at(\f2chainOut).notNil };
		// §post a divider needs the output node (the post group's sink IS
		// \f2chainOut): in the legacy layout (f2units not loaded) the post cards
		// are skipped, warned once, and cfgSig |sink0 respawns the pool with them
		// once f2units arrives.
		hasPost = hasSink and: { pst.isArray };
		if (chn.notNil and: { pst.isArray } and: { hasSink.not }) {
			warnOnce.(("post_nosink_" ++ def.asString).asSymbol,
				"⚠ [f2 post] %: the strip has a divider but f2units is NOT loaded — its post cards are skipped until then".format(def));
		};

		if (stk.notNil and: { chn.isNil }) {
			ctrl = [\gate, \t_trig, \freq, \out, \buf];
			stk.do { |u|
				var ud = SynthDescLib.global.at(u[\unit]);
				if (ud.notNil) {
					var pre = u[\id].asString ++ "__";
					ctrl = ctrl ++ ud.controlNames.collect { |c| (pre ++ c.asString).asSymbol };
					if (u[\id] == cfg[\stackOut]) { ctrl = ctrl ++ ud.controlNames };
				};
			};
		};
		// §cards control union of a strip, same shape as the stack one: shared
		// names + `id__ctrl` of every card + the PRESET level `amp` (the output
		// node's; with the legacy layout the last card's plain names instead).
		// The variant's SynthDesc (or the base unit's — every variant declares
		// the same control set) supplies the names; without f2units (no
		// ~f2UnitDef) the base unit is used. An empty strip keeps the shared
		// names (+ amp).
		if (chn.notNil and: { stk.isNil }) {
			var outId = if (chn.size > 0) { chn.last[\id] } { nil };
			ctrl = [\gate, \t_trig, \freq, \out, \buf];
			if (hasSink) { ctrl = ctrl ++ [\amp] };
			chnDef = IdentityDictionary.new;
			chn.do { |c|
				// ~f2UnitDef answers the variant name only once the variant is BUILT
				// (else the base unit — and kicks the build): the fingerprint below
				// gains "@variant" when the def exists and the pool respawns once.
				var udef = if (c[\opts].notNil and: { top[\f2UnitDef].notNil })
					{ top[\f2UnitDef].(c[\unit], c[\opts]) ? c[\unit] } { c[\unit] };
				var ud = SynthDescLib.global.at(udef) ?? { SynthDescLib.global.at(c[\unit]) };
				chnDef[c[\id]] = udef;
				if (ud.notNil) {
					var pre = c[\id].asString ++ "__";
					ctrl = ctrl ++ ud.controlNames.collect { |cn| (pre ++ cn.asString).asSymbol };
					// legacy layout only: the last card owns the plain names
					if (hasSink.not and: { c[\id] == outId }) { ctrl = ctrl ++ ud.controlNames };
				};
			};
			// the stage count of the voice part (hoisted from mkOne: the post
			// group needs it for the bus size too): the stage bus covers every
			// slot a card names, even if chainN lags
			nStage = (cfg[\chainN] ? 0).asInteger;
			chn.do { |c|
				nStage = nStage.max((c[\rd] ? (-1)).asInteger + 1).max((c[\wr] ? (-1)).asInteger + 1);
			};
			// §post the post cards' defs (variants like the cards', resolved
			// through ~f2UnitDef — the base def until the variant is built, the
			// fingerprint |p respawns the pool then) and the POOL-LEVEL PAIRS at
			// the FRONT of the stage bus: pair 0 = the post-in (the sum of every
			// voice's final stage), pairs 1..postFinal-1 = the private post stages,
			// pair postFinal = the sink's input — the chain convention (the sink of
			// a strip reads slot chainN): postN with k post cards is k, card i reads
			// i and writes i + 1, the last writes -1 = post slot postN; the max over
			// the slots the cards name covers a postN that lags (as nStage does).
			// The post-in itself when every card right of the divider is bypassed.
			// postOff = how many pairs the per-voice stages are moved back by.
			// Post params are NOT in the ctrl union: they never ride an
			// event (the core delivers them on the preset-level key, §post static
			// maps), so nothing in the set/map loops addresses a post node.
			if (hasPost) {
				pstDef = IdentityDictionary.new;
				pst.do { |c|
					var udef = if (c[\opts].notNil and: { top[\f2UnitDef].notNil })
						{ top[\f2UnitDef].(c[\unit], c[\opts]) ? c[\unit] } { c[\unit] };
					pstDef[c[\id]] = udef;
					pstN = pstN.max((c[\rd] ? 0).asInteger + 1).max((c[\wr] ? (-1)).asInteger + 1);
				};
				postFinal = if (pst.size > 0) { pstN } { 0 };
				postOff = postFinal + 1;
			};
		};
		if (grp.isKindOf(Node).not) { grp = s.defaultGroup };   // not a Node → the server's default group
		// two-step (the trap: dict[k]=v returns the receiver); in practice the DSL init already made it
		if (voices.isNil) { voices = IdentityDictionary.new; top[\f2Voices] = voices };
		// §reuse poolKey = ROW|preset@group: a pool per (row × preset), so that stopping a row
		//   frees exactly its own voices (~f2FreeSceneVoices) and not someone else's.
		poolKey = ((ev[\f2scene] ? \_).asString ++ "|" ++ def.asString ++ "@" ++ grp.nodeID.asString).asSymbol;

		// §loop-order A DETERMINISTIC VOICE ORDER: a subgroup per (row × preset), inserted by
		// SORTING on defKey among the subgroups of the same parent. Node order used to depend on
		// the order of the FIRST onsets (addToHead at spawn) — and that wanders (rand branches,
		// redeploys). For port loops it is fatal: InFeedback gives 0 or 1 block of delay per hop
		// DEPENDING ON NODE ORDER, i.e. the same loop sounded different from run to run. Sorting
		// by defKey makes the order — and the loops' block delays — reproducible every time. The
		// parent is ~f2PatGroup; changing parent (hush → a new group) recreates the subgroup.
		// IMPORTANT: the parent's key in the entry is \par, NOT \parent: on Event/IdentityDictionary
		// \parent is the service slot of the prototype chain (a read goes into a parent lookup on
		// the Group → «Message not understood» and the event dies = a swallowed note). The try is
		// insurance: ANY failure of §loop-order degrades to a spawn straight into patGroup (the old
		// behaviour) rather than killing the note.
		vgrp = try {
			// §loop-order v3 THE dict[k]=v TRAP: assignment returns THE RECEIVING DICTIONARY (see
			// the canonical case at ~mbAt) — `top[\k] ?? { top[\k] = Dict.new }` handed back
			// topEnvironment on the FIRST spawn; keysValuesDo then walked the WHOLE environment and
			// failed on 'at' at the first Group or Bus. Only an explicit two-step will do.
			var vgs = top[\f2VGrp2];
			var e;
			if (vgs.isNil) { vgs = IdentityDictionary.new; top[\f2VGrp2] = vgs; top[\f2VGroups] = nil };
			e = vgs[poolKey];
			// §node-live a subgroup whose /g_new the server refused (its parent was
			// gone when it went out) reads isPlaying true for ever, so the entry was
			// kept and EVERY voice of this pool was then spawned into a group that
			// does not exist — refused in turn, and each refused voice floods
			// «/n_mapn Node N not found» once per mapped parameter per event. The
			// group is REGISTERED for that test to have an answer: it was not
			// before, so a RELOAD of this file over a sounding session drops each
			// pool's old entry once (an empty group abandoned per pool, taken by
			// the next hush) and builds a registered one — the same one-off a
			// reload already costs at §node-bus.
			if (e.notNil and: { (e[\par] !== grp)
				or: { top[\f2NodeLive].(e[\g], e[\at]).not } }) { vgs.removeAt(poolKey); e = nil };
			if (e.isNil) {
				var myDef = def.asString, pred, succ;
				vgs.keysValuesDo { |k, o|
					if (o[\par] === grp) {
						if (o[\def] < myDef) {
							if (pred.isNil or: { o[\def] > pred[\def] }) { pred = o };
						} {
							if (succ.isNil or: { o[\def] < succ[\def] }) { succ = o };
						};
					};
				};
				e = (par: grp, def: myDef, at: Main.elapsedTime,   // §node-live
					g: if (pred.notNil) { Group.after(pred[\g]) }
						{ if (succ.notNil) { Group.before(succ[\g]) } { Group.head(grp) } });
				e[\g].register(true);
				vgs[poolKey] = e;
			};
			e[\g]
		} { |err|
			("⚠ [f2 loop-order] " ++ err.errorString ++ " — spawning in patGroup").postln;
			grp
		};

		// §cards the RESOURCE arguments of a card (buffers, never knobs), shared
		// by the strip cards (mkOne) and the post cards (mkPost, §post): the
		// same card resolves the same buffers on either side of the divider.
		resArgs = { |c, uc|
			var ra = [];
			var cbuf, sres;
			// §smp a card's own RESOURCE opt `sample` wins over the preset
			// buffer (~f2SmpBuf); every other card keeps today's ev[\buf].
			cbuf = (top[\f2SmpBuf] !? { |f| f.(c[\opts]) }) ? ev[\buf];
			if (cbuf.notNil and: { uc.includes(\buf) }) { ra = ra ++ [\buf, cbuf] };
			// §conv-ir a convU card under `ir: sample` reads a PREPARED spectrum
			// buffer, not the sample itself (PartConv takes no sound file), so its
			// resource opts resolve through their own cache exactly as the
			// sampler's analyses do. Pending or unreadable ⇒ the null IR, and the
			// card passes the source through its wet path rather than dropping out.
			if (uc.includes(\irBuf) and: { top[\f2ConvIrRes].notNil }) {
				ra = ra ++ [\irBuf, top[\f2ConvIrRes].(c[\opts])];
			};
			// §curve the DRAWN POINT LIST (POLYMER.md §6.8, ENVELOPE.md §2.9):
			// `curve` names a RENDERED BUFFER PAIR and no graph, so it resolves
			// here exactly as `irSample` does — one 16384-sample cycle becomes the
			// 12-level mip bank `osc: scrawl` reads (`curveBuf`, the BASE of a
			// consecutive range) and the 16385-frame shape `env: segments` reads
			// (`shapeBuf`). Both are engine args and never knobs, so no card's
			// control budget moves. An empty `curve` is the schema default and
			// reads the DEFAULT DRAWING, not buffer 0 — a card nobody has drawn on
			// sounds. The key handed over is `<preset>|<card>`: the cache is keyed
			// on the drawing itself (two cards on one curve share one bank), and
			// this names the card whose voices ~f2CurveSwap moves when a render
			// that was still in flight at spawn lands.
			if (top[\f2CurveRes].notNil
				and: { uc.includes(\shapeBuf) or: { uc.includes(\curveBuf) } }) {
				var cres = top[\f2CurveRes].(c[\opts],
					(def.asString ++ "|" ++ c[\id].asString).asSymbol);
				if (uc.includes(\curveBuf)) { ra = ra ++ [\curveBuf, cres[\curveBuf]] };
				if (uc.includes(\shapeBuf)) { ra = ra ++ [\shapeBuf, cres[\shapeBuf]] };
			};
			// §smp the other RESOURCE opts (SAMPLER.md §6): `slicing slices beatLen
			// onsetSens pitchSens bpm` name an ANALYSIS, not a graph, so they resolve
			// to the slice-table buffer here exactly as `sample` resolves to `buf`.
			// The entry owns that bufnum for the life of the sample — a re-analysis
			// refills the table IN PLACE, so a note already sounding follows the new
			// grid and the pool has nothing to respawn for. `bpm: manual` reads the
			// card's own smpBpm knob ([RN] Automatic BPM Detection off): a live control
			// cannot key an analysis, so its value at spawn keys the entry instead.
			if (uc.includes(\sliceBuf) and: { top[\f2SmpRes].notNil }) {
				sres = top[\f2SmpRes].(c[\opts], cbuf,
					ev[(c[\id].asString ++ "__smpBpm").asSymbol]);
				if (sres.notNil) {
					ra = ra ++ [\sliceBuf, sres[\sliceBuf]];
					// §4 the pitch curve of the FILE, when this card asked for one
					// (`rootMode: analyzed`). -1 until the offline pass lands, and
					// the graph then reads the manual root — so a note played in
					// that window sounds, it just does not track yet.
					if (uc.includes(\pitchBuf)) {
						ra = ra ++ [\pitchBuf, (sres[\pitchBuf] ? -1)];
					};
					// §7 the two artefacts Spectral reads and nothing else does
					// (SAMPLER.md §6): the onset table Preserve Onsets asks «am I
					// on a transient» of, and the file's FFT frames. Both are -1
					// until their pass lands — the graph then behaves as if the
					// switch were off, and a spectral voice whose frames are not
					// there yet stays SILENT for that note rather than handing
					// PV_BufRd a bufnum that is not an analysis.
					if (uc.includes(\onsetBuf)) {
						ra = ra ++ [\onsetBuf, (sres[\onsetBuf] ? -1)];
					};
					if (uc.includes(\fftBuf)) {
						ra = ra ++ [\fftBuf, (sres[\fftBuf] ? -1)];
					};
				};
			};
			ra
		};
		// §cards one card's part of the pool fingerprint (cfgSig |c and |p):
		// id:unit:opts:rd:wr (opts = sorted k=v pairs; "@variant" once the
		// variant def is BUILT — until then the base def is spawned and the pool
		// respawns when the variant exists). `defs` is the id → resolved def
		// cache of that side of the divider (chnDef / pstDef).
		cardSig = { |c, defs|
			var udef = (defs !? { defs[c[\id]] }) ? c[\unit];
			c[\id].asString ++ ":" ++ c[\unit].asString ++ ":"
			++ (c[\opts] !? { |o| o.keys.asArray.collect(_.asString).sort.collect { |kk|
				kk ++ "=" ++ (o[kk.asSymbol] ? o[kk]).asString }.join(",") } ? "")
			++ ":" ++ (c[\rd] ? (-1)).asString ++ ":" ++ (c[\wr] ? (-1)).asString
			++ (if (udef != c[\unit]) { "@" ++ udef.asString } { "" })
		};
		// §post the GROUP of a voice (mkOne's strip group, mkVoice's copies
		// group): the tail of `par` — the preset's §loop-order subgroup, which the
		// post group follows (Group.after(vgrp)), so a voice respawned later still
		// executes before it. In the §loop-order FALLBACK the voices spawn straight
		// into the pattern group (par === grp) and the post group sits at ITS
		// tail: a voice added to the tail then would come AFTER the post group —
		// its final stage read a cycle before it is written, i.e. lost — so with a
		// live post group the voice group goes right BEFORE it instead.
		voiceGrp = { |par|
			// §node-live Group.before a group the server refused is refused in turn,
			// so the placement asks the same question the liveness guards ask
			if (hasPost and: { par === grp } and: { pool.notNil } and: { pool[\post].notNil }
				and: { top[\f2NodeLive].(pool[\post][\grp], pool[\post][\at]) }) {
				Group.before(pool[\post][\grp])
			} {
				Group.new(par, \addToTail)
			}
		};
		// §post THE POOL'S POST GROUP — built once per pool (after the voices,
		// when hasPost) and freed with it (the soft retire below, the scene stop
		// in ~f2FreeSceneVoices; a hush takes it with the pattern group). One
		// Group.after(vgrp): AFTER the preset's voice subgroup, so a voice
		// respawned later (\addToTail inside vgrp) still executes before it. In
		// it, in strip order, one Synth per post card — its SynthDef variant
		// like a card's (pstDef), i_free 0 (it never self-frees: it plays for
		// the pool, not for a note), gate 1 (a processor reading a stage runs
		// env = 1 anyway — §cards in f2units), chainIn = its rd pair (0 = the
		// post-in, the sum of every voice's final stage), out = its wr pair or
		// the sink's input, the same resource buffers as a card (resArgs), port
		// inputs on SLOT 0 (~f2PortInSlot.(pn, 0) — one instance, the writer's
		// pair 0), telId on the LAST post card (it is the strip's output card).
		// LAST, the sink \f2chainOut: the final post pair → the preset's out (a
		// port writer's slot 0, ~f2PortOutSlot.(po, 0) — the SUMMED signal into
		// slot 0 — else this event's rack bus) × the preset level (pool[\postOut]
		// / pool[\postAmp] follow the events, see §node-bus below). Then the
		// STATIC MAPS: every (id__param, key) of cfg[\postMap] whose node has
		// the param is mapped onto ~mbAt.(key) — the preset-level bus the core
		// writes — and registered in ~f2StaticMaps so the smoother created
		// later for that key takes the mapping with it (~f2SmoothHook). Units
		// with \tempo follow the tempo bus. Returns the proxy (grp, nodes, sink,
		// bus) the pool stores in pool[\post]; nil when the stage bus could not
		// be allocated (§bus-guard: the voices then write the out directly and
		// the next event tries again).
		mkPost = {
			var pg, nodes = IdentityDictionary.new, nodeCtl = IdentityDictionary.new, sink, sb, pamp, pout;
			var po = cfg[\portOut], pins = cfg[\portIns];
			var pslot = { |j| sb.index + (2 * j) };
			sb = top[\f2StackBusAt].(poolKey, (nStage * nv * nk) + postOff);
			if (sb.isNil) { nil } {
				// (§loop-order fallback, vgrp === grp: the tail of the pattern group —
				// voiceGrp then spawns every later voice group before it)
				pg = if (vgrp === grp) { Group.new(grp, \addToTail) } { Group.after(vgrp) };
				pg.register(true);
				pst.do { |c, pdi|
					var udef = (pstDef !? { pstDef[c[\id]] }) ? c[\unit];
					var ud = SynthDescLib.global.at(udef);
					var uc = if (ud.notNil) { ud.controlNames } { [] };
					var rd = (c[\rd] ? 0).asInteger.max(0), wr = (c[\wr] ? (-1)).asInteger;
					var ua = [\out, pslot.(if (wr < 0) { postFinal } { wr }), \gate, 1, \tel_bus, (ev[\tel_bus] ? 0)];
					if (uc.includes(\chainIn)) {
						ua = ua ++ [\chainIn, pslot.(rd)];
					} {
						if (ud.notNil) {
							warnOnce.(("chainIn_" ++ udef.asString).asSymbol,
								"⚠ [f2 post] %: post card % (%) reads post stage % but has no chainIn — stream dropped".format(def, c[\id], udef, rd));
						};
					};
					if (uc.includes(\i_free)) { ua = ua ++ [\i_free, 0] };
					ua = ua ++ resArgs.(c, uc);
					if (pins.notNil and: { top[\f2PortInSlot].notNil }) {
						var pre = c[\id].asString ++ "__";
						pins.keysValuesDo { |k, pn|
							var ks = k.asString;
							if (ks.beginsWith(pre)) {
								var an = ks.copyToEnd(pre.size).asSymbol;
								if (uc.includes(an)) {
									// §port-nil a nil slot = the port has no bus (the
									// allocator refused it); the card keeps its own default
									var sl = top[\f2PortInSlot].(pn, 0);
									if (sl.notNil) { ua = ua ++ [an, sl] };
								};
							};
						};
					};
					if (cfg[\telId].notNil and: { pdi == (pst.size - 1) } and: { uc.includes(\telId) }) {
						ua = ua ++ [\telId, cfg[\telId]];
					};
					if (ud.notNil) {
						var n = Synth(udef, ua, pg, \addToTail);
						n.register(true);
						nodes[c[\id]] = tempoMap.(n, uc);
						nodeCtl[c[\id]] = uc;
					} {
						// §cut as for a card: name the unit, the preset and the card, once
						if (top[\f2UnitGone].notNil) {
							top[\f2UnitGone].(c[\unit], def, c[\id]);
						} {
							("⚠ [f2 post] %: post card % has no SynthDef % — card skipped, and everything after it is silent".format(def, c[\id], udef)).postln;
						};
					};
				};
				pamp = ev[\amp];
				if (pamp.isNumber.not) { pamp = 1 };
				// §port-nil an unallocated port falls back to the direct out, not to nil
				pout = (if (po.notNil and: { top[\f2PortOutSlot].notNil }) { top[\f2PortOutSlot].(po, 0) }) ? (ev[\out] ? 0);
				sink = Synth(\f2chainOut, [\in, pslot.(postFinal), \out, pout, \amp, pamp], pg, \addToTail);
				sink.register(true);
				// the static maps (top.use: ~mb/~mbSm live inside ~mbAt)
				if (pstMap.notNil) {
					top.use {
						pstMap.pairsDo { |pk, key|
							var ks = pk.asString, i = ks.find("__"), id, an, n, b;
							if (i.notNil and: { i > 0 }) {
								id = ks.copyFromStart(i - 1).asSymbol;
								an = ks.copyToEnd(i + 2).asSymbol;
								n = nodes[id];
							};
							// a param the node's def declares (nodeCtl); an id without a
							// node (a skipped card) or an unknown param is dropped silently
							if (n.notNil and: { (nodeCtl[id] ? []).includes(an) }) {
								b = ~mbAt.(key.asSymbol);
								if (b.notNil) {
									n.map(an, b.index);
									top[\f2StaticMapAdd].(key.asSymbol, n, an, pg);
								};
							};
						};
					};
				};
				(grp: pg, nodes: nodes, sink: sink, bus: sb, at: Main.elapsedTime)   // §node-live
			}
		};
		// §stack mkOne builds ONE copy (ci) of voice vi under `par` — the preset
		// subgroup for a plain voice, the copy group of a stacked one. mkVoice
		// (below the builder) is what the pool calls.
		mkOne = { |vi = 0, ci = 0, par|
			var a = [\out, (ev[\out] ? 0), \tel_bus, (ev[\tel_bus] ? 0), \gate, 0];
			var po = cfg[\portOut], pins = cfg[\portIns];
			var sy;
			if (hasFree) { a = a ++ [\i_free, 0] };
			if (ev[\buf].notNil) { a = a ++ [\buf, ev[\buf]] };
			// §synth-mod ports (f2units.scd): the voice's output vi → a port slot; port inputs → the
			// writer's slots (vi % wv). The slots are fixed for the voice's whole life — set at
			// spawn; a missing helper shouts through §port-guard below, and the |h flag in cfgSig
			// rebuilds the pool once f2units has finished loading.
			if (po.notNil and: { top[\f2PortOutSlot].notNil }) {
				// §port-nil nil = no bus for that port; the voice keeps its direct out
				top[\f2PortOutSlot].(po, vi) !? { |sl| a[1] = sl };
			};
			// §port-guard a missing helper (f2units not loaded) used to degrade SILENTLY: the
			// port-writer's voice stayed on the direct output and «sounded outside the port» without
			// a single line in the console. Now it shouts — the cause is visible at once.
			if ((po.notNil or: { pins.notNil }) and: { top[\f2PortOutSlot].isNil }) {
				("⚠ [f2 ports] % requests ports (portOut/portIns) but f2units is NOT loaded — voice falls back to the direct out".format(def)).postln;
			};
			// §stack voice = a Group (tail of the preset subgroup) holding one Synth
			// per sub-unit in list order (sources before processors — loops are
			// legal, one block late through InFeedback like ports). Internal routes
			// are private stereo slots (~f2StackBusAt: source unit × voice, fixed at
			// spawn); the output unit writes the resolved out (a[1] = port slot or
			// ev out), every other unit writes its own source slot. External port
			// inputs address a sub-unit as `id__arg` in cfg[\portIns]. telId goes to
			// the output unit (vi 0), buf to every unit that has it. The returned
			// proxy is what the pool stores; see ~f2VSet/~f2VMap/~f2VNode.
			if (stk.notNil and: { chn.isNil }) {
				var vg = Group.new(par, \addToTail);
				var nodes = IdentityDictionary.new;
				var srcIds = [], srcSlot = IdentityDictionary.new;
				var outId = cfg[\stackOut];
				var sb;
				stk.do { |u| (u[\ins] ? ()).keysValuesDo { |an, src|
					if (srcIds.includes(src).not) { srcIds = srcIds.add(src) } } };
				sb = top[\f2StackBusAt].(poolKey, srcIds.size * nv * nk);   // §stack × copies
				// §bus-guard the same insurance as in the chain branch: an empty bus pool must not
				// kill the event (an error inside Event:play breaks the pattern's stream forever).
				srcIds.do { |id, si| srcSlot[id] = if (sb.isNil) { a[1] } { sb.index + (2 * ((((si * nv) + vi) * nk) + ci)) } };
				vg.register(true);
				stk.do { |u|
					var ud = SynthDescLib.global.at(u[\unit]);
					var uc = if (ud.notNil) { ud.controlNames } { [] };
					var uout = if (u[\id] == outId) { a[1] } { srcSlot[u[\id]] ? 0 };
					var ua = [\out, uout, \gate, 0, \tel_bus, (ev[\tel_bus] ? 0)];
					if (u[\id] == outId and: { srcSlot[u[\id]].notNil }) {
						("⚠ [f2 stack] %: output unit % also feeds a route — unsupported in v1 (route ignored)".format(def, u[\id])).postln;
					};
					if (uc.includes(\i_free)) { ua = ua ++ [\i_free, 0] };
					if (ev[\buf].notNil and: { uc.includes(\buf) }) { ua = ua ++ [\buf, ev[\buf]] };
					(u[\ins] ? ()).keysValuesDo { |an, src|
						if (uc.includes(an) and: { srcSlot[src].notNil }) { ua = ua ++ [an, srcSlot[src]] };
					};
					if (pins.notNil and: { top[\f2PortInSlot].notNil }) {
						var pre = u[\id].asString ++ "__";
						pins.keysValuesDo { |k, pn|
							var ks = k.asString;
							if (ks.beginsWith(pre)) {
								var an = ks.copyToEnd(pre.size).asSymbol;
								if (uc.includes(an)) {
									var sl = top[\f2PortInSlot].(pn, vi);   // §port-nil see mkPost
									if (sl.notNil) { ua = ua ++ [an, sl] };
								};
							};
						};
					};
					if (cfg[\telId].notNil and: { vi == 0 } and: { ci == 0 } and: { u[\id] == outId } and: { uc.includes(\telId) }) {
						ua = ua ++ [\telId, cfg[\telId]];
					};
					if (ud.notNil) {
						var n = Synth(u[\unit], ua, vg, \addToTail);
						n.register(true);   // liveness (~f2VPlaying): a self-freeing sub-unit marks the voice dead
						nodes[u[\id]] = tempoMap.(n, uc);
					} {
						// §cut same reason as the strip below: name the unit, the preset
						// and the successor, once — a skipped sub-module takes everything
						// routed through it with it.
						if (top[\f2UnitGone].notNil) {
							top[\f2UnitGone].(u[\unit], def, u[\id]);
						} {
							("⚠ [f2 stack] %: unit % has no SynthDef — sub-module skipped".format(def, u[\unit])).postln;
						};
					};
				};
				sy = (grp: vg, nodes: nodes, out: outId);
			};
			// §cards strip voice = a Group (tail of the preset subgroup) holding one
			// Synth per ON card in strip order (\addToTail ⇒ execution order =
			// strip order) and, LAST, the output node \f2chainOut. The stream lives
			// on private stereo STAGE slots (~f2StackBusAt: stage × voice, fixed at
			// spawn): a synth card writes stage `wr` (Out.ar sums — two synths side
			// by side are layers), a processor reads stage `rd` through `chainIn`
			// (In.ar: same cycle, no delay — its writers sit earlier in the group)
			// and writes `wr`. wr = -1 is the FINAL stage — a private slot as well
			// (slot chainN, hence (chainN + 1) × nv slots): the output node reads it
			// and writes the resolved preset out (a[1] = port slot or ev out) scaled
			// by the PRESET level, the bare `amp` of the event (each card's own
			// level is `id__amp`). Legacy layout (no \f2chainOut — f2units not
			// loaded): the last cards write a[1] directly and the plain params go
			// to the last card; cfgSig |sink0 respawns the pool once f2units is
			// in. A card with opts spawns its SynthDef VARIANT (chnDef: resolved by
			// ~f2UnitDef — the base def until the variant is built); external port
			// inputs address a card as `id__arg` in cfg[\portIns]; telId goes to
			// the last card (vi 0) — or, for a card that declares `vi`, to EVERY
			// voice with its index (§smp playheads, SAMPLER.md §3.3) — and buf to
			// every card that has it. Every node is registered (liveness,
			// ~f2VPlaying) and units with \tempo are mapped onto the tempo bus.
			// The proxy has the stack shape (+ sink), so every pool site works as is.
			// §post WITH A DIVIDER (hasPost) the voice holds the LEFT cards only:
			// the final stage (wr -1) of every voice and copy is ONE shared pair —
			// the post-in, pair 0 of the stage bus, where the voices sum — and the
			// per-voice stages sit postOff pairs further back; there is NO sink in
			// the voice group (the pool's post group has the one sink, mkPost) and
			// no left card takes telId (the strip's output card is the last post
			// card). Without a divider the layout is byte for byte the old one.
			if (chn.notNil and: { stk.isNil }) {
				var vg = voiceGrp.(par);   // §post before a live post group in the §loop-order fallback
				var nodes = IdentityDictionary.new;
				var outId = if (chn.size > 0 and: { hasPost.not }) { chn.last[\id] } { nil };
				var sb, slot, sink, pamp;
				if (hasSink) {
					// + the final stage; §stack × copies. §post: the per-voice stages
					// plus the pool-level pairs at the front (the shared final stage
					// among them) — the same count mkPost asks for, so both get one bus
					sb = top[\f2StackBusAt].(poolKey,
						if (hasPost) { (nStage * nv * nk) + postOff } { (nStage + 1) * nv * nk });
				} {
					if (nStage > 0) { sb = top[\f2StackBusAt].(poolKey, nStage * nv * nk) };
				};
				// §bus-guard the stage bus may have FAILED to allocate (the server's audio bus pool
				// is empty — ~f2StackBusAt has already said so out loud and, unlike the old
				// behaviour, did not cache the failure). `sb.index` on nil here used to raise RIGHT
				// INSIDE THE EVENT — and an error inside Event:play breaks the pattern's stream, so
				// the row went silent entirely and forever. Now the strip degenerates: the cards
				// write straight to the output (a sum instead of a chain), the sink is not spawned
				// (it would be reading its own output), the note lives, and the first trigger after
				// the buses come back assembles the strip properly.
				slot = { |k| if (sb.isNil) { a[1] } {
					if (hasPost) {
						// §post the final stage is the shared post-in pair; a private
						// stage sits behind the postOff pool-level pairs
						if (k >= nStage) { sb.index } { sb.index + (2 * (postOff + ((((k * nv) + vi) * nk) + ci))) }
					} {
						sb.index + (2 * ((((k * nv) + vi) * nk) + ci))
					}
				} };
				vg.register(true);
				// `cdi` — the card's index in the compiled strip: the playhead
				// telemetry below rides on it (SAMPLER.md §3.3), nothing else reads
				// it. It is NOT `ci`: that is mkOne's COPY index, and shadowing it here
				// made the telemetry guard below test the card instead of the copy —
				// a multi-card strip never handed telId to its last card, and every
				// copy of a stacked strip sent telemetry (channel flutter).
				chn.do { |c, cdi|
					var udef = (chnDef !? { chnDef[c[\id]] }) ? c[\unit];
					var ud = SynthDescLib.global.at(udef);
					var uc = if (ud.notNil) { ud.controlNames } { [] };
					var rd = (c[\rd] ? (-1)).asInteger, wr = (c[\wr] ? (-1)).asInteger;
					var uout = if (wr < 0) { if (hasSink) { slot.(nStage) } { a[1] } } { slot.(wr) };
					var ua = [\out, uout, \gate, 0, \tel_bus, (ev[\tel_bus] ? 0)];
					if (rd >= 0) {
						if (uc.includes(\chainIn)) {
							ua = ua ++ [\chainIn, slot.(rd)];
						} {
							// the compiler marked the card `proc` from a SynthDesc that had
							// chainIn; the def loaded now (or this variant) lacks it
							if (ud.notNil) {
								warnOnce.(("chainIn_" ++ udef.asString).asSymbol,
									"⚠ [f2 chain] %: card % (%) reads stage % but has no chainIn — stream dropped".format(def, c[\id], udef, rd));
							};
						};
					};
					if (uc.includes(\i_free)) { ua = ua ++ [\i_free, 0] };
					// the card's RESOURCE arguments (buffers: sample, IR, curve, slice
					// tables) — resArgs above, shared with the post cards of §post
					ua = ua ++ resArgs.(c, uc);
					if (pins.notNil and: { top[\f2PortInSlot].notNil }) {
						var pre = c[\id].asString ++ "__";
						pins.keysValuesDo { |k, pn|
							var ks = k.asString;
							if (ks.beginsWith(pre)) {
								var an = ks.copyToEnd(pre.size).asSymbol;
								if (uc.includes(an)) {
									var sl = top[\f2PortInSlot].(pn, vi);   // §port-nil see mkPost
									if (sl.notNil) { ua = ua ++ [an, sl] };
								};
							};
						};
					};
					// §smp playhead telemetry (SAMPLER.md §3.3 / §5): a card that
					// declares `vi` — samplerU, and nothing else — takes telId in
					// EVERY voice together with its voice index AND its card index, so
					// the front can draw one head per voice of THIS card
					// ('/f2_head' [vi, ci, pos, span, mode]). telId names the preset,
					// so without `ci` two samplerU cards in one strip (§8 decision 4)
					// would share one bucket of heads.
					// Every other card keeps today's rule exactly: telId goes to the
					// LAST card of voice 0 alone, or the `sc:<dk>` level channel would
					// flutter between voices. §stack copy 0 alone (ci is mkOne's copy
					// index): the layers of one voice play one note and must not
					// interleave one channel.
					if (cfg[\telId].notNil and: { ci == 0 } and: { uc.includes(\telId) }) {
						if (uc.includes(\vi)) {
							ua = ua ++ [\telId, cfg[\telId], \vi, vi];
							if (uc.includes(\ci)) { ua = ua ++ [\ci, cdi] };
						} {
							if (vi == 0 and: { c[\id] == outId }) { ua = ua ++ [\telId, cfg[\telId]] };
						};
					};
					if (ud.notNil) {
						var n = Synth(udef, ua, vg, \addToTail);
						n.register(true);   // liveness (~f2VPlaying): a doneAction:2 card that self-frees marks the voice dead
						nodes[c[\id]] = tempoMap.(n, uc);
					} {
						// §cut the def is not loaded. Skipping the node silently is the
						// failure we refuse: this card's stage is then never written, so
						// every card after it reads an empty bus and the preset goes quiet
						// from here on — which looks exactly like a bypass. ~f2UnitGone
						// names the unit, the preset, the card and, when the unit was CUT
						// rather than merely missing, what to rebuild the card on; it posts
						// once per (preset × unit), so a strip retriggering at 120 bpm says
						// it one time.
						if (top[\f2UnitGone].notNil) {
							top[\f2UnitGone].(c[\unit], def, c[\id]);
						} {
							("⚠ [f2 chain] %: card % has no SynthDef % — card skipped, and everything it fed is silent".format(def, c[\id], udef)).postln;
						};
					};
				};
				// §bus-guard without a stage bus there is no sink; §post with a
				// divider the sink is the pool's (mkPost), not the voice's
				if (hasSink and: { sb.notNil } and: { hasPost.not }) {
					// the output node, LAST in the group: final stage → resolved out × preset level
					pamp = ev[\amp];
					if (pamp.isNumber.not) { pamp = 1 };
					sink = Synth(\f2chainOut, [\in, slot.(nStage), \out, a[1], \amp, pamp], vg, \addToTail);
					sink.register(true);
				};
				sy = (grp: vg, nodes: nodes, out: outId, sink: sink, post: hasPost);
			};
			if (stk.isNil and: { chn.isNil } and: { pins.notNil } and: { top[\f2PortInSlot].notNil }) {
				pins.keysValuesDo { |argName, pn|
					if (ctrl.includes(argName)) {
						var sl = top[\f2PortInSlot].(pn, vi);   // §port-nil see mkPost
						if (sl.notNil) { a = a ++ [argName, sl] };
					};
				};
			};
			// §synth-mod telemetry: an `sc:*` channel is written by ONE voice of the preset (vi=0),
			// otherwise the voices' values would interleave (channel flutter).
			if (cfg[\telId].notNil and: { vi == 0 } and: { ci == 0 } and: { ctrl.includes(\telId) }) {
				a = a ++ [\telId, cfg[\telId]];
			};
			// §loop-order into ITS OWN subgroup, at the tail: a preset's voices go by vi and the
			// subgroups by defKey ⇒ the full node order is reproducible whatever the onset order.
			if (stk.isNil and: { chn.isNil }) {
				sy = Synth(instr, a, par, \addToTail);
				sy.register(true);   // assumePlaying=true: a fresh voice is «alive» (isPlaying) at once, not dead until /n_go
				tempoMap.(sy, ctrl);
			};
			sy;
		};
		// §stack a voice = one copy (nk 1: the node itself, exactly as before) or a
		// GROUP of nk copies at the tail of the preset subgroup — the proxy
		// (grp:, copies: [...]) the accessors demux: set/gate/freq to every copy,
		// map copy ci to `<key>_s<ci>`, nodeID = the group, alive = every copy alive.
		mkVoice = { |vi = 0|
			if (nk <= 1) {
				mkOne.(vi, 0, vgrp)
			} {
				var vg = voiceGrp.(vgrp);   // §post before a live post group in the §loop-order fallback
				var cps;
				vg.register(true);
				cps = Array.fill(nk, { |ci| mkOne.(vi, ci, vg) });
				(grp: vg, copies: cps)
			}
		};

		// the pool: the GROUP is compared by IDENTITY (===), not only by the nodeID in the key —
		// after a redeploy or hush the old group is freed (its voices dead), and SC may REISSUE the
		// same nodeID to a new group → the key would match while the voices are corpses (a flood of
		// «/n_mapn Node not found»). A different group → a fresh pool. (A single dead voice is
		// covered one by one below.) §orphan-fix A SNAPSHOT of cfg (voices+artic) in the pool. A
		//   structural redeploy on a voices/artic change does change the signature, BUT
		//   §smooth-restart swaps only the source Pdef and does NOT recreate the group — so the old
		//   pool survived with the FORMER voice count. On voices 3→1, voices 1..2 stopped receiving
		//   events: if they were at gate=1 (a note or a hold) they STUCK forever (the envelope never
		//   released, and x.set(gate,0) missed — that is an orphaned node, not the one the user
		//   sees). Snapshot diverged → silence ALL nodes of the old pool by nodeID (the «no such
		//   node» error is suppressed: the group may already have taken them) and rebuild the pool.
		// §cfg-sig the snapshot is EVERYTHING that is baked into the spawn arguments (see mkVoice):
		// the instrument, the output route (the portOut slot — the rack bus ev[\out] is NOT part of
		// it any more, see §node-bus below), the port inputs, telId, the sample buffer. It used to
		// hold voices|artic only — so a change of routing
		// (outBus → an «internal» port, a different port, a different fx bus, a change of the
		// preset's synth) honestly went through a structural redeploy and updated ~f2ReuseCfg, but
		// the pool's LIVE voices were not recreated (the snapshot matched) and went on writing to
		// the OLD bus until the pool happened to die (their row stopped, a hush, a voices/artic
		// change) — «I changed the output and it still sounds the old way; it applied on the Nth
		// restart of everything». Now any shift of the spawn config recreates the pool on the first
		// trigger after the redeploy.
		// §port-wv a port input's slot bakes `vi % wv` of the WRITER at spawn time
		// (~f2PortInSlot), so the current wv of every port this preset reads is
		// part of the fingerprint (|w below): a later writer deploy, or a change
		// of the writer's voices, respawns the READER on its next trigger. It used
		// to be left out — the reader kept the stale modulus until its own pool
		// happened to die. The lookup goes to the registry itself, not ~f2PortAt:
		// the fingerprint must not ensure a port as a side effect; a port not
		// ensured yet is what mkOne will ensure with the default wv, 16.
		// §node-bus the rack bus (ev[\out]) used to sit in |o next to the port: the
		// voice's \out was baked at spawn, so a preset played under two tree nodes
		// with different buses respawned its pool on every alternation. Now \out
		// is SET per event on the output-writing node (below, after the remap),
		// |o carries the port slot alone ("" for a direct-out preset — one
		// respawn of every direct-out pool on the first trigger after this file
		// is reloaded, nothing more) and the pool survives a bus change.
		cfgSig = nv.asString ++ "|" ++ artic.asString
			++ "|x" ++ nk.asString   // §stack copies are spawn-baked
			++ "|s" ++ instr.asString
			++ "|o" ++ (cfg[\portOut] ? "").asString
			++ "|t" ++ (cfg[\telId] ? 0).asString
			++ "|b" ++ (ev[\buf].tryPerform(\bufnum) ? ev[\buf] ? "").asString
			// CAREFUL: the argument is NOT named `pi` — that is the reserved constant π in sclang
			// (the lexer hands back a numeric literal → «syntax error, unexpected PIE»).
			++ "|i" ++ (cfg[\portIns] !? { |pins|
				pins.keys.asArray.collect(_.asString).sort.collect { |k|
					k ++ ":" ++ pins[k.asSymbol].asString
				}.join(",")
			} ? "")
			++ "|w" ++ (cfg[\portIns] !? { |pins|
				pins.keys.asArray.collect(_.asString).sort.collect { |k|
					var pn = pins[k.asSymbol].asSymbol;
					var pe = top[\f2Ports] !? { |d| d[pn] };
					((pe !? { pe[\wv] }) ? 16).asString
				}.join(",")
			} ? "")
			// §port-guard a flag for whether the port helpers existed AT SPAWN TIME (only for
			// presets with ports): a voice born BEFORE f2units loaded stays on the direct output —
			// when the helpers appear the snapshot diverges and the very next trigger rebuilds the
			// pool with the real routing.
			++ (if (cfg[\portOut].notNil or: { cfg[\portIns].notNil })
				{ "|h" ++ top[\f2PortOutSlot].notNil.asString } { "" })
			// §units-ver a units reload bumps ~f2UnitsVer ⇒ every pool fingerprint
			// diverges ⇒ pools respawn on their next trigger with the FRESH defs.
			// Without this, nodes spawned before the reload kept playing the stale
			// compiled graph — file replaced, sound unchanged, "fix did nothing".
			++ "|u" ++ (top[\f2UnitsVer] ? 0).asString
			// §stack the graph itself (units, routes, output) is spawn-baked too
			++ (stk !? { |st| "|k" ++ st.collect { |u|
				u[\id].asString ++ ":" ++ u[\unit].asString ++ ":"
				++ (u[\ins] ? ()).keys.asArray.collect(_.asString).sort.collect { |kk|
					kk ++ ">" ++ (u[\ins][kk.asSymbol]).asString }.join(",")
			}.join(";") ++ ">" ++ cfg[\stackOut].asString } ? "")
			// §cards the strip is spawn-baked too: id:unit:opts:rd:wr per card
			// (opts = sorted k=v pairs; "@variant" once the variant def is BUILT —
			// until then the base def is spawned and the pool respawns when the
			// variant exists), then >chainN and the output-node layout.
			++ (chn !? { |ch| "|c" ++ ch.collect { |c| cardSig.(c, chnDef) }.join(";")
				++ ">" ++ (cfg[\chainN] ? 0).asString
			// §cards-out the output-node layout is spawn-baked too (final stage
			// slot + \f2chainOut vs. the legacy direct write): flips once f2units loads
			++ (if (hasSink) { "|sink1" } { "|sink0" }) } ? "")
			// §post the divider is spawn-baked too: the post cards (same shape as
			// |c, with their own numbering) and postN — a card moved across the
			// divider, a post card added, bypassed or re-menued, or the divider
			// removed, respawns the pool (and rebuilds the post group with it).
			// A strip without a divider adds nothing here.
			++ (pst !? { |ps| "|p" ++ ps.collect { |c| cardSig.(c, pstDef) }.join(";")
				++ ">" ++ (cfg[\postN] ? 0).asString } ? "");
		pool = voices[poolKey];
		// §hold-note the offAt bookkeeping is read BEFORE the pool decisions: the
		// retire rule below and the voice pick both ask «is a voice of this pool
		// ending at this boundary?». nowT is the wall clock of the language (the
		// same clock the offAt entries are written in); holdTol is 0.08 beat in
		// seconds — tempo-invariant, and wide enough to hold the 0.03-beat margin
		// of a hold gate-off plus the language's scheduling jitter.
		nowT = Main.elapsedTime;
		holdTol = 0.08 * TempoClock.default.beatDur;
		// the voice whose gate ENDS at this boundary: offAt within holdTol ahead of
		// nowT (a scheduled off still pending) AND whose lane (pool[\lane][v], the
		// f2lane of the event that last played it) equals the event's lane — see
		// §hold-note below for the lane rule. lanes nil (a pool from before the
		// rule) or both lanes nil (a compiler that sends no f2lane): nil == nil is
		// true in sclang, so the old lane-agnostic behaviour is kept. Several →
		// the nearest off. None → nil: every open voice still has time left (an
		// overlapping note), the ending voices belong to another lane, or the
		// pool is silent (a fresh onset).
		endingV = { |offs, lanes, myLane|
			var best;
			(offs ? []).do { |t, v|
				if ((nowT >= (t - holdTol)) and: { nowT < t }
					and: { lanes.isNil or: { lanes[v] == myLane } }) {
					if (best.isNil or: { t < offs[best] }) { best = v };
				};
			};
			best
		};
		// §hold-retire DEFERRED retire on a sounding hold. The fingerprint check
		// below fires on the first event after a structural edit (copies, voices,
		// any cell edit). For a hold preset that event may be the CONTINUATION of
		// a run that is sounding right now, and a respawn would re-attack it in
		// the middle of the note. So: signature diverged AND hold AND a voice of
		// the OLD pool is ending at this boundary (a continuation by the rule of
		// endingV) → the old pool serves this event, marked pool[\retire] = the
		// new signature, and stays in the old cfg (nv/nk of ITS spawn — the arrays
		// and the copies proxies are sized by them, and mkOne must rebuild a dead
		// voice in the old layout). The retire happens on the first event that is
		// NOT a continuation — a fresh onset, i.e. the old note has ended. The
		// non-hold path, a channel gate, a changed group (the old voices are
		// corpses) and a pool from before this rule (no \nk) retire at once, as
		// before.
		deferHold = false;
		if (pool.notNil and: { pool[\grp] === grp } and: { pool[\cfgSig] != cfgSig }
			and: { artic == \hold } and: { pool[\artic] == \hold } and: { pool[\nk].notNil }
			and: { cfg[\gateSrc].isNil }) {
			contIdx = endingV.(pool[\offAt], pool[\lane], ev[\f2lane]);
			// a continued voice that is DEAD has nothing to keep sounding: the
			// §orphan-fix respawn below would rebuild it with the NEW graph (mkVoice
			// closes over the new cfg) in the OLD layout (nv/nk of the old pool) —
			// retire at once instead, as a fresh onset would
			if (contIdx.notNil and: { top[\f2VPlaying].(pool[\synths][contIdx],
				(pool[\bornAt] ? [])[contIdx]).not }) { contIdx = nil };
			if (contIdx.notNil) {
				deferHold = true;
				pool[\retire] = cfgSig;
				nv = pool[\nv]; nk = pool[\nk];
			};
		};
		if (pool.notNil and: { deferHold.not } and: { (pool[\grp] !== grp) or: { pool[\cfgSig] != cfgSig } }) {
			// §cfg-sig SOFT retire. The old voices used to be hard-freed here (n_free
			// mid-sound = a click on every strip / menu / routing edit). Now they get
			// gate 0 at once and are freed 0.4 s later (the ~f2FreeSceneVoices
			// pattern); the pool entry is dropped immediately, so the new pool is
			// built alongside. A stack/strip pool also owns its stage bus: the
			// registry entry is detached now (the new pool allocates a fresh bus
			// instead of sharing slots with the releasing voices — a shared slot
			// would sum both generations for 0.4 s) and freed with the old voices.
			var old = pool;
			var sreg = top[\f2StackBus], sbe = sreg !? { sreg[poolKey] };
			sbe !? { sreg.removeAt(poolKey); top[\f2StackBusRetire].value(sbe, 0.5) };
			old[\synths].do { |v|
				var nid = top[\f2VNode].(v);
				if (nid.notNil) { s.sendBundle(nil, [\error, 0], [\n_set, nid, \gate, 0], [\error, 1]) };
			};
			// §post the old pool's post group is freed WITH its voices, after their
			// release — it is what they sound through for those 0.4 s (its bus is
			// the retired entry above; the new pool's post group gets the fresh one)
			SystemClock.sched(0.4, {
				old[\synths].do { |v|
					var nid = top[\f2VNode].(v);
					if (nid.notNil) { s.sendBundle(nil, [\error, 0], [\n_free, nid], [\error, 1]) };
				};
				old[\post] !? { |p| top[\f2FreePost].value(p) };
				nil
			});
			voices.removeAt(poolKey); pool = nil;
		};
		if (pool.isNil) {
			pool = (synths: Array.fill(nv, { |i| mkVoice.(i) }), rr: 0, gen: Array.fill(nv, 0), grp: grp, cfgSig: cfgSig,
				artic: artic, nv: nv, nk: nk,   // §hold-retire the layout a deferred event must keep
				lane: Array.fill(nv, nil),      // §hold-note the lane each voice last played
				// §node-live when each voice's /s_new went out: inside ~f2NodeGrace an
				// unconfirmed voice is alive (the confirmation is still in flight),
				// after it only the server's own /n_go counts
				bornAt: Array.fill(nv, Main.elapsedTime),
				outAt: Array.fill(nv, ev[\out] ? 0));   // §node-bus the out each voice writes (mkOne baked this event's)
			voices[poolKey] = pool;
		};
		// §post the pool's post group: built once, after the voices (the same
		// stage bus — mkOne allocated it with the pool-level pairs in front);
		// rebuilt when its group is gone (something freed it under the pool) and
		// retried when the stage bus could not be allocated (mkPost gave nil).
		// pool[\postOut] / pool[\postAmp] remember what the sink was spawned
		// with, so the per-event sets below go out only on a change. Not on a
		// §hold-retire deferred event: that pool is the OLD one in its old
		// layout (its cfg may have had no divider at all), and a post group
		// built now would ask ~f2StackBusAt for a different pair count — the
		// bus under the sounding voices would be reallocated. The retire that
		// follows the held note builds the new pool with its post group.
		if (hasPost and: { deferHold.not }) {
			// §node-live a post group the server refused reads isPlaying true for
			// ever; judged by that alone it was never rebuilt and its cards, and
			// the preset's whole output through them, stayed silent
			if (pool[\post].notNil and: { top[\f2NodeLive].(pool[\post][\grp], pool[\post][\at]).not }) {
				top[\f2FreePost].value(pool[\post]);
				pool[\post] = nil;
			};
			if (pool[\post].isNil) {
				pool[\post] = mkPost.();
				pool[\postOut] = ev[\out] ? 0;
				pool[\postAmp] = if (ev[\amp].isNumber) { ev[\amp] } { 1 };
			};
		};
		// §hold-note HOLD PER NOTE. A hold event CONTINUES a voice only when that
		// voice's gate is ending at this boundary (endingV): the adjacent cell of a
		// run arrives 0.03 beat before its predecessor's deferred gate-off, lands
		// on the same voice, bumps gen and cancels that off — one merged gate
		// across the run. Otherwise it is a NEW note and takes the round-robin
		// voice exactly as reattack does: an overlapping hold note of the same
		// preset (a par of two blocks with different offsets, a short hold nested
		// inside a long one) gets its own voice, its own gate front, its own pitch
		// latch (holdCont is per voice), its own bus mapping (lastMap is per idx)
		// and its own gate-off (gen is per idx — another voice's events never
		// cancel it). The old rule stuck EVERY hold event of the preset to one
		// voice (pool[\hidx]): the second onset became a continuation, the first
		// note's off was cancelled by the gen bump, and its offAt was overwritten
		// (a nested short note shut the long one early). pool[\hidx] survives as
		// the last-continued voice — diagnostics only. A channel gate (gateSrc)
		// writes no offAt, so it keeps the sticky voice: its cells carry
		// parameters, not gates, and must keep addressing one node.
		//
		// THE LANE RULE. The compiler tags every cell event with f2lane = the
		// cell's chain of par branches plus its row (a Symbol: for each ancestor
		// container whose op is par, "/t:<containerId>:<childIndex>"; a row r ≥ 1
		// of a multi-row block appends "/r<r>", row 0 adds nothing — it is the
		// block's base lane, so a single-row block or a row 0 under a seq/wseq
		// root has the empty lane, and row i of consecutive blocks in a seq is
		// ONE lane: their touching cells continue the voice, as single-row
		// blocks do). A continuation must match the lane:
		// endingV only answers a voice whose lane (pool[\lane][v], written at
		// every pick) equals the event's. Without it the two rows of one block —
		// two parallel branches of the phase tree, cells touching at the same
		// boundaries — zipped across voices: row 1's onset at a boundary where
		// row 0's cell ends was taken as a continuation of row 0's voice (and
		// vice versa), both rows' events at one boundary fought for the same
		// ending voice, and a run hopped voices every time the other row started
		// or ended a cell (a fresh attack + a release each hop). Now a run stays
		// on one voice for its whole life; a cross-lane touching cell is a new
		// note and takes a free voice (the free-voice scan is lane-agnostic: a
		// free voice is free for anyone). A pool without \lane (built before
		// this rule) gets the array lazily; its voices carry lane nil until they
		// are picked again.
		//
		// LIMITS of the pick, by reading, not by ear:
		// - THE STEAL. Every voice busy → the round-robin voice is taken with
		//   its gate still open. Two cases, told apart by the lane the voice
		//   last played (§steal-x, stealX below — read BEFORE the lane is
		//   overwritten; nil == nil counts as the same lane):
		//   · ANOTHER LANE's note is on it → a cross-lane steal, and the new
		//     note sounds as a NEW note: holdCont is false, so \freq is set and
		//     latched at this moment (and f2map maps it); the gate takes the
		//     micro-dip re-attack (gate 0 now, gate 1 by bundle in 4 ms — the
		//     branch reattack/legato use on an open voice); the gate-off goes
		//     at the NEW cell's end, no max with the stolen end. The stolen
		//     note is cut — that is the decision: the note of this moment wins
		//     over the older one, and a harmony-bound preset latches the bus
		//     value of its own onset. Add voices to keep both.
		//   · THE SAME LANE (a busy voice of this lane not found by endingV, or
		//     an old compiler sending no f2lane) → the merge, as before: gate 1
		//     on an open gate has no edge and holdCont is true, so the new note
		//     gets NO attack and keeps the OLD pitch latch (§h-latch v2 skips
		//     \freq) — it only remaps the voice onto the new cell's buses and
		//     extends the gate-off to the later end.
		// - MONO (voices 1): idx is always 0, so every overlap lands on the open
		//   voice and the same two cases apply — a second lane's onset is the
		//   cross-lane steal (re-attack, fresh latch, the first note cut at the
		//   new note's start); a same-lane overlap is the merge (no attack, no
		//   re-latch, gate-off at the later end, the voice remapped to the new
		//   cell's buses).
		// - A STRUCTURAL REDEPLOY OF THE ROW (any edit that changes the compiled
		//   structure: a cell, a block's height, the tree) never meets a stale
		//   lane tag, because it never meets the old pool: the compiled row code
		//   opens with ~f2FreeSceneVoices.(\<row>) (both compilers, §reuse),
		//   which drops every pool of the row and gates its voices off AT THE
		//   EVAL, mid-loop, while the Pdef swap waits for the loop boundary
		//   (§sync quant). Every note of the row sounding at the edit releases
		//   then; the next cell event of the old stream builds a fresh pool (new
		//   synths, lane nil, a fresh latch) and re-attacks — on every lane,
		//   whatever the articulation. So a lane renamed by the edit (a par put
		//   above a row: "" → "/t:<id>:<i>") starts over with the pool.
		//   A pool that outlives its row code (a cfgSig change without a row
		//   redeploy: a writer's voices |w, a units reload |u, a variant def
		//   |c) keeps lane tags that still match. Only a reload of THIS file
		//   over a sounding pool built before the lane code re-attacks: its
		//   voices get lane nil lazily, nil ≠ a Symbol, one fresh onset per
		//   running voice, then correct.
		// - A GAP SHORTER THAN 0.03 BEAT between two hold cells of one preset
		//   on one lane (a rest or a foreign cell) is bridged: the off of the
		//   first cell is still pending at the second onset, so it counts as a
		//   continuation (the core sees two runs). See the durB floor below for
		//   cells shorter than 0.05 beat, where the window widens.
		//
		// DIAGNOSTIC: topEnvironment[\f2DebugHold] = true posts one line per
		// hold event — "[f2 hold] <poolKey> cid <f2_cid> lane <lane> voice <idx>
		// <cont|fresh|steal> off-in <ms> respawned <bool>": cont = the voice was
		// found by endingV, steal = every voice busy — "steal from <lane>" names
		// the stolen lane on a cross-lane steal (§steal-x, the re-attack), "steal
		// (merge)" is the same-lane merge —, fresh = a free voice; off-in = that
		// voice's pending gate-off relative to now, at the moment of the decision
		// (negative = the voice was free). Off by default; set the flag to nil
		// to stop.
		offAtA = pool[\offAt];
		if (offAtA.isNil) { offAtA = Array.fill(nv, 0); pool[\offAt] = offAtA };
		if (pool[\lane].isNil) { pool[\lane] = Array.fill(pool[\nv] ? nv, nil) };
		holdHow = nil;
		if (nv <= 1) {
			idx = 0;
			// mono: the label only (the pick is fixed); computed under the flag
			if (artic == \hold and: { top[\f2DebugHold] == true } and: { cfg[\gateSrc].isNil }
				and: { endingV.(offAtA, pool[\lane], ev[\f2lane]) == 0 }) { holdHow = \cont };
		} {
			if (artic == \hold) {
				idx = if (cfg[\gateSrc].notNil) { pool[\hidx] ? 0 } {
					contIdx ?? { endingV.(offAtA, pool[\lane], ev[\f2lane]) } };
				if (idx.notNil and: { cfg[\gateSrc].isNil }) { holdHow = \cont };
			};
			if (idx.isNil) {
				idx = pool[\rr]; pool[\rr] = (pool[\rr] + 1) % nv;
				// §hold-note a fresh hold onset prefers a FREE voice (by the offAt
				// bookkeeping), scanning round-robin from rr. On an OPEN voice the
				// event counts as a continuation (holdCont: gate 1 on an open gate has
				// no edge, the pitch stays latched) — the note is SWALLOWED. With a
				// long hold sounding and short notes nested inside it, rr alternated
				// and every other nested note vanished into the long one while a
				// voice sat idle. Every voice busy → steal rr (the merge), as before.
				if (artic == \hold and: { cfg[\gateSrc].isNil } and: { nowT < (offAtA[idx] ? 0) }) {
					var k = 1;
					while { (k < nv) and: { nowT < (offAtA[(idx + k) % nv] ? 0) } } { k = k + 1 };
					if (k < nv) { idx = (idx + k) % nv; pool[\rr] = (idx + 1) % nv };
				};
			};
		};
		pool[\hidx] = idx;
		// §steal-x the OLD lane of the picked voice decides: a hold onset on a
		// voice still open by the offAt bookkeeping whose last note belongs to
		// another lane is a cross-lane steal (a continuation found by endingV or
		// contIdx always matches the lane, so it never trips this). Read here,
		// before pool[\lane][idx] is overwritten below the diagnostic post.
		stealX = (artic == \hold) and: { cfg[\gateSrc].isNil }
			and: { nowT < (offAtA[idx] ? 0) } and: { pool[\lane][idx] != ev[\f2lane] };
		if (holdHow.isNil) { holdHow = if (nowT < (offAtA[idx] ? 0)) { \steal } { \fresh } };
		voice = pool[\synths][idx];
		// §node-live the born stamp of THIS slot (nil on a pool from before the
		// rule — then only a confirmed node counts, which is the safe reading)
		bornA = pool[\bornAt];
		if (bornA.isNil) { bornA = Array.fill(pool[\nv] ? nv, nil); pool[\bornAt] = bornA };
		if (voice.isNil or: { top[\f2VPlaying].(voice, bornA[idx]).not }) {
			// §orphan-fix before replacing, silence the previous node by nodeID: if isPlaying is
			//   false on a voice that is still ALIVE (register(true) without /n_go), replacing it in
			//   the pool would orphan a sounding node (gate stuck). A dead node: error suppressed, no-op.
			// §cards a proxy counts as dead when ANY card node self-freed
			//   (~f2VPlaying); the n_free goes to its GROUP (~f2VNode), so the
			//   surviving cards and the sink are freed with it — nothing leaks.
			// §node-live a voice the SERVER never confirmed (isPlaying true from
			//   register(true), isRunning still false past the grace) is refused,
			//   not dead: its /s_new never made a node. It is replaced like any
			//   corpse — but say so ONCE per preset, because the cause outlives
			//   the voice (a group that is gone, a SynthDef the server has not
			//   got, maxNodes) and a respawn per event would otherwise be the only
			//   sign. Before this the voice was never replaced at all and each
			//   event mapped every parameter onto it: «/n_mapn Node N not found»
			//   once per parameter per event, the same id, until the row stopped.
			if (voice.notNil and: { top[\f2VRefused].(voice) }) {
				warnOnce.(("refused_" ++ def.asString).asSymbol,
					"⚠ [f2 voice] %: the server refused voice % (node %) — its /s_new made no node (the group it was spawned into is gone, % is not on the server, or maxNodes is reached). The voice is silent and is being respawned; check the server's post window for the /s_new or /g_new that failed.".format(def, idx, top[\f2VNode].(voice), instr));
			};
			voice !? { |v| var nid = top[\f2VNode].(v);
				if (nid.notNil) { s.sendBundle(nil, [\error, 0], [\n_free, nid], [\error, 1]) } };
			voice = mkVoice.(idx); pool[\synths][idx] = voice; respawned = true;
			// §map-skip THE SLOT'S LAST-MAP MEMORY DIES WITH THE NODE IT DESCRIBED.
			// The map below is conditional now, and a fresh node is mapped to NOTHING:
			// left in place, lastMap[idx] would claim every parameter of this slot was
			// already mapped, the new voice would never be mapped at all, and its
			// parameters would sit at their SynthDef defaults for the life of the voice
			// — silently. This is the one site: a cfgSig change drops the whole pool
			// entry (§cfg-sig soft retire) and a row redeploy drops it with the pool
			// (~f2FreeSceneVoices), so lastMap never outlives them.
			pool[\lastMap] !? { |la| la[idx] = nil };
			bornA[idx] = Main.elapsedTime;
			// §node-bus mkOne baked this event's out into the fresh voice
			pool[\outAt] !? { |oa| oa[idx] = ev[\out] ? 0 };
		};
		// §hold-note the diagnostic post (see the comment block above); the
		// pending off is read here, before the new off is written further down,
		// and the voice's OLD lane (the stolen one) before it is overwritten
		if (artic == \hold and: { top[\f2DebugHold] == true }) {
			"[f2 hold] % cid % lane % voice % % off-in % respawned %".format(
				poolKey, ev[\f2_cid], ev[\f2lane], idx,
				if (holdHow == \steal) {
					if (stealX) { "steal from " ++ pool[\lane][idx].asString } { "steal (merge)" }
				} { holdHow },
				(((offAtA[idx] ? 0) - nowT) * 1000).round(0.1), respawned ? false).postln;
		};
		pool[\lane][idx] = ev[\f2lane];   // §hold-note the lane this voice now plays
		// §gen-fix THE ROOT BUG (there since §reuse itself): `arr[i] = v` in sclang returns THE
		// ARRAY ITSELF, not the value (the same trap documented for dict[k]=v).
		// Because of `myGen = (pool[\gen][idx] = …)` myGen was AN ARRAY, and the gen guard
		// `pool[\gen][idx] == myGen` (number == array) was ALWAYS false → the gate-off was
		// ALWAYS cut → gates piled up at 1 → sticking. That is where «hold always stuck» came
		// from, and why reatk/legato came back to life exactly when the gate-off went out as a
		// server bundle WITHOUT the guard, and stuck again when the guard returned in §gate-v3.
		pool[\gen][idx] = pool[\gen][idx] + 1;
		myGen = pool[\gen][idx];

		// §h-latch v2 poly sample-and-hold on the GATE. A hold-run continuation
		// event (same pooled voice, gate still open, not a fresh synth, no channel
		// gate) must NOT re-pitch the sounding note: the pitch latched at the gate
		// front holds until the next real gate trigger — melody/tree changes land
		// on the next attack, never mid-note. Only \freq is frozen; every other
		// param keeps updating per cell as before. The offAt bookkeeping is
		// hoisted from the articulation block below (and read at the pool
		// decisions above, §hold-note) so the freq/set sections can tell a
		// gate-opening event from a continuation. Per kind of event, for a
		// harmony-bound preset (detunedFreq = a Pfunc reading the voice bus, a
		// number per event): reattack and legato latch \freq at every cell; a
		// hold fresh onset (a free voice, or another lane's onset while this
		// lane's run continues) latches at its own moment — two lanes latched at
		// different moments hold different pitches of the same voice's
		// trajectory; a hold continuation keeps its onset pitch; a hold STEAL
		// (every voice busy) is a continuation by this test and keeps the
		// STOLEN note's pitch when the stolen note is of the SAME lane (the
		// merge), and is a NEW note that latches at its own moment when it is of
		// ANOTHER lane (§steal-x: stealX makes holdCont false — see the LIMITS of
		// §hold-note above); a respawned voice is a fresh synth and latches; the
		// §hold-retire deferred event is a continuation of the old pool and
		// keeps; a channel-gated preset (gateSrc) never continues and latches at
		// every cell — its gate is the bus, so the latch lands on whatever note
		// the bus holds open.
		stillOpen = nowT < (offAtA[idx] ? 0);
		holdCont = (artic == \hold) and: { stillOpen } and: { stealX.not }
			and: { cfg[\gateSrc].isNil } and: { (respawned ? false).not };

		// map the live arguments → per-cell buses (top.use: ~mb/~mbSm live inside ~mbAt)
		// §map-seed cell-boundary bus handoff: the NEXT cell's bus holds its
		// base/stale value until the engine's next tick (~16 ms), so a remap
		// TELEPORTED continuously-scrubbed params (tape grPos burst-played the
		// wrong spot every cell — the rasp) and blipped any param toward base.
		// Before remapping, the RAW bus of the new key is seeded with the LIVE
		// value of the previously mapped bus (getSynchronous, local server), so
		// the handoff is seamless and the next engine tick simply confirms it.
		// v2: every seeded key is reported back to the core as /f2_dirty — the
		// engine forgets its per-key diff and re-sends its OWN value on the next
		// tick (~16 ms). Without that, a mod whose computed value never changes
		// (const lock, slow S&H) would keep the seeded neighbour value forever:
		// the diff would never fire again and the stomp would stick.
		// §map-skip THE MAP IS ISSUED ONLY WHEN THE BUS INDEX MOVED.
		// Every event used to re-map every mapped parameter, per copy, whether or not
		// anything had changed — one bundle of three messages each, on sclang's single
		// thread, at note rate. The comparison that decides it was already here (it
		// serves the §map-seed handoff above); only the map itself was unconditional.
		//
		// §collapse is what makes the saving large. A parameter nothing drives now
		// shares ONE key per (preset, param) — the same bus for every cell, scene and
		// row — so a voice moving from cell to cell keeps the same bus for it, and on
		// the owner's save 97.59 % of keys are of that kind. Before the collapse the
		// key was per cell and the bus genuinely changed, so there was little to skip.
		//
		// The skip is only as good as its invalidation, and getting THAT wrong is
		// worse than not skipping at all, because the failure is a parameter frozen at
		// its default for the life of a voice with no line in any log. Two things hold
		// it up, and a third is named here only to be dismissed:
		//   · lm — per VOICE SLOT (lastMap[idx]): the bus each (param, copy) of this
		//     slot's node was last put on. Cleared where the node is respawned, which
		//     is the ONE site that replaces a node under a pool that survives — a
		//     cfgSig change drops the pool entry and a row redeploy drops the pool.
		//   · the bus INDEX itself, which is why a smoother appearing later needs no
		//     invalidation: ~mbAt answers ~mbSm[k] once that exists (f2_modsmooth.scd),
		//     a different index, and the comparison sees it like any other move.
		//   · the post sink, which is NOT skipped at all — the reason is at the branch.
		//
		// Knowingly given up: the repetition used to re-heal a map message lost in
		// transit. The server is local (the §map-seed handoff below already relies on
		// that, with getSynchronous) and every n_set on this path — gate, freq, t_trig
		// — has always been sent exactly once. topEnvironment[\f2MapAlways] = true
		// restores the unconditional behaviour for a session; the live check
		// sc/nrt/live-voices.scd §G measures both arms through it.
		if (ev[\f2map].notNil) {
			top.use {
				var lmAll = pool[\lastMap];
				var lm, dirty, always = top[\f2MapAlways] == true;
				if (lmAll.isNil) { lmAll = IdentityDictionary.new; pool[\lastMap] = lmAll };
				lm = lmAll[idx];
				if (lm.isNil) { lm = IdentityDictionary.new; lmAll[idx] = lm };
				ev[\f2map].pairsDo { |param, key|
					if (ctrl.includes(param) and: { (holdCont and: { param == \freq }).not }) {
						// §stack copy ci of a stacked voice reads `<key>_s<ci>` (Polyphony.md
						// §6.4) — the core delivers one value per copy; a plain voice reads
						// the key itself. The handoff below runs per copy: each remembers
						// the bus IT was on.
						var keys = if (nk > 1) { nk.collect { |ci| (key.asString ++ "_s" ++ ci).asSymbol } } { [key] };
						keys.do { |kk, ci|
							var b = ~mbAt.(kk);
							var lmk = if (nk > 1) { (param.asString ++ "_s" ++ ci).asSymbol } { param };
							if (b.notNil) {
								var prev = lm[lmk];
								// §map-skip prev is the bus THIS SLOT'S NODE was last put on
								var moved = prev.isNil or: { prev.index != b.index };
								if (prev.notNil and: { prev.index != b.index }) {
									try {
										var live = prev.getSynchronous;
										var raw = ~mbRawAt !? { ~mbRawAt.(kk) } ? b;
										raw.set(live);
										if (raw.index != b.index) { b.set(live) };
										dirty = dirty.add(kk);
									};
								};
								lm[lmk] = b;
								// §post a mapped PRESET level (`amp` in f2map) has one
								// addressee with a divider — the pool's sink — and follows
								// the bus of the last event (copy 0's key); the per-voice
								// demux would drop it (no sink in the voice)
								// §map-skip AND THIS ONE IS DELIBERATELY NOT SKIPPED. The post
								// branch fires for ONE parameter (the preset level) once per
								// event, so skipping it would save about a three-hundredth of
								// the map traffic — against which it would need a last-map
								// memory of its own, because the sink is one node for the
								// WHOLE POOL and any voice's event may be the one that maps it:
								// a per-voice memory would let one voice's `already mapped` hide
								// a sink that is new, and pool[\post] is re-created above
								// whenever the server refused or freed the old group. That is a
								// second silent-failure path for a rounding error of a saving,
								// and it is not worth it.
								if (hasPost and: { param == \amp }) {
									if (ci == 0) { pool[\post] !? { |p| top[\f2MapQuiet].(p[\sink], [\amp, b.index]) } };   // §node-live
								} {
									if (always or: { moved }) {
										if (nk > 1) {
											top[\f2VMap].(voice[\copies][ci], param, b.index);
										} {
											top[\f2VMap].(voice, param, b.index);
										};
									};
								};
							};
						};
					};
				};
				if (dirty.notNil and: { dirty.size > 0 }) {
					(~f2CoreAddr ? ~f2BackendAddr ? NetAddr("127.0.0.1", 57121)).sendMsg('/f2_dirty', *dirty);
				};
			};
		};
		// §node-bus THE RACK BUS PER EVENT. ev[\out] is resolved by ~enrich (the
		// wrapper: the event's outBus — the tree node's bus, put on the event by
		// the compilers — else the preset def's outBus, else main). mkOne baked
		// it at spawn; from here on it is SET on the node that writes the
		// preset's output — the strip's sink, a stack's output node, the plain
		// synth (~f2VDemux routes a plain \out there; a copies proxy fans it to
		// every copy) — so one preset under two tree nodes with different buses
		// keeps its pool and moves its output with each event. pool[\outAt] is
		// the out each voice currently writes (initialised at spawn): the set
		// goes out only when it changes for THIS voice — a bus set on every event
		// of every voice is exactly the traffic this avoids. A port-writing
		// preset (cfg[\portOut]) is left alone: its out IS the port slot, taken
		// at spawn, and ev[\out] does not apply to it — as before. \out is in
		// the reserved set, so the static loop below never sends it.
		// §post with a divider the ONE node that writes the preset's output is
		// the pool's sink (pool[\post][\sink]), not a per-voice node: the bus
		// goes there, once per change (pool[\postOut]), and the voices' outAt
		// bookkeeping is left alone (no voice node reads it).
		if (cfg[\portOut].isNil and: { ev[\out].notNil } and: { ctrl.includes(\out) }) {
			if (hasPost) {
				if (pool[\postOut] != ev[\out]) {
					pool[\postOut] = ev[\out];
					pool[\post] !? { |p| p[\sink] !? { |sk| sk.set(\out, ev[\out]) } };
				};
			} {
				var outA = pool[\outAt];
				if (outA.isNil) { outA = Array.fill(pool[\nv] ? nv, nil); pool[\outAt] = outA };
				if (outA[idx] != ev[\out]) {
					outA[idx] = ev[\out];
					top[\f2VSet].(voice, [\out, ev[\out]]);
				};
			};
		};
		// pitched synths: as in the default event — \freq gets ~detunedFreq (freq+detune; §h-latch
		// harmony puts the number LATCHED at the onset here); the fallback is ~freq.
		// §h-latch v2: continuing a hold run does NOT touch the pitch (see holdCont above).
		if (ctrl.includes(\freq) and: { holdCont.not }) {
			var fr = ev.use { try { (~detunedFreq).value } { nil } };
			if (fr.isNumber.not) { fr = ev.use { try { (~freq).value } { nil } } };
			if (fr.isNumber) { top[\f2VSet].(voice, [\freq, fr]) };
		};
		// static numeric controls (not reserved, not in f2map) → set
		setA = [];
		ev.keysValuesDo { |k, v|
			if (reserved.includes(k).not and: { v.isNumber } and: { ctrl.includes(k) }
				and: { (holdCont and: { k == \freq }).not }) {
				setA = setA ++ [k, v];
			};
		};
		if (setA.size > 0) { top[\f2VSet].(voice, setA) };
		// §post the bare PRESET level of the event goes to the pool's sink (the
		// demux dropped it from setA — no sink in the voice), only when it
		// changed (pool[\postAmp]); a mapped amp went through f2map above and
		// is not a number here.
		if (hasPost and: { ev[\amp].isNumber } and: { pool[\postAmp] != ev[\amp] }) {
			pool[\postAmp] = ev[\amp];
			pool[\post] !? { |p| p[\sink] !? { |sk| sk.set(\amp, ev[\amp]) } };
		};
		// §cell-trig per-cell onset pulse (compiler emits cellTrig only for
		// grainU presets): fires on EVERY event of the reused voice — including
		// hold continuations that never re-front the gate — so the tape motor
		// (grainU mode=1) re-anchors its head to the just-remapped-and-seeded
		// grPos bus at each musical boundary; tempo-mismatch drift is bounded
		// to one cell instead of accumulating for bars. t_trig is a TrigControl
		// (auto-resets after one control block); other units are unaffected
		// because their cfg carries no cellTrig. §cards: a strip's cfg names its
		// tape CARDS (`cellTrig: [\smp, \gr]`) and only those nodes are pulsed
		// (`id__t_trig`; an id without a node is dropped by the demux); a
		// legacy/stack preset keeps the voice-wide `cellTrig: 1`.
		if (cfg[\cellTrig].isArray) {
			top[\f2VSet].(voice, cfg[\cellTrig].collect { |id| [(id.asString ++ "__t_trig").asSymbol, 1] }.flatten);
		} {
			if (cfg[\cellTrig] == 1) { top[\f2VSet].(voice, [\t_trig, 1]) };
		};
		// ARTICULATION — all three modes: gate=1 plus a DEFERRED gate-off with a gen guard. An
		// adjacent cell of THE SAME voice bumps gen; its gate-off cancels the previous one (overlaps
		// are not cut). The mode is ONLY the moment of the gate-off relative to the cell boundary (dur):
		//   reattack — gate-off BEFORE the next onset (a gap of dur·0.85): on the next cell gate 0→1
		//              is a clean RE-ATTACK with air around it (percussive, staccato).
		//   legato   — gate-off JUST BEFORE the boundary (dur−ε, ε small): the envelope retriggers
		//              every cell but WITHOUT audible silence (joined up) — sus synths do not stick.
		//   hold     — gate-off JUST AFTER the boundary (dur+ε): the adjacent cell of THE SAME synth
		//              arrives at the boundary (earlier) and cancels it → one MERGED gate across the
		//              whole run of adjacent cells of one synth (gate ×N); the release comes only at a
		//              rest \x or at a boundary with a DIFFERENT synth (this voice gets no new notes
		//              there, so there is nobody to cancel). Modulation: preset scope runs on
		//   continuously (the scope's window does not break), cell scope is reset by remapping the
		//   voice onto the new cell's bus (above) — «cell scope is the exception».
		// §synth-mod A CHANNEL gate (cfg[\gateSrc] = an SC bus key): the voice's \gate is mapped onto
		// a bus — the core writes the opening and closing (the contract: if the source disappears the
		// core sends 0 and the gate is shut). Cell events then do NOT touch gate or sched — they
		// carry parameters and pitch and hold the modulation windows open.
		if (cfg[\gateSrc].notNil) {
			top.use {
				var gb = ~mbAt.(cfg[\gateSrc]);
				if (gb.notNil) { top[\f2VMap].(voice, \gate, gb.index) };
			};
		} {
			// §gate-v3 A GATE LIFECYCLE that survives OVERLAPS (polyphony, parallel rows of one
			// preset, dense grids). Three diseases of the earlier versions:
			//   1) a coincident onset on an OPEN voice: set(gate,1) while gate=1 — NO EDGE, EnvGen
			//      does not retrigger → the note «vanishes into nothing»;
			//   2) a gate stuck at 1 (a lost off): a percussive envelope (sus 0) has died away, every
			//      further 1→1 is mute → the voice is DEAD, «every nth trigger disappears» (round
			//      robin hands it every nv-th note);
			//   3) a blind (no gen guard) server-side off: a stale off from the adjacent cell killed
			//      a fresh note on THE SAME voice under overlap.
			// The fix: the language SCHEDULES the off (two clocks, TempoClock+SystemClock) with a gen
			// guard (bumping gen at the onset cancels stale offs; a double reset is idempotent), and
			// delivery is a server bundle WITHOUT isPlaying (a false false swallowed the off — the old
			// sticking). At the onset: if by the offAt bookkeeping the voice is STILL OPEN, a micro-dip
			// (gate 0 now, gate 1 by bundle in 4 ms) instead of a mute 1→1; otherwise a plain set.
			// Self-healing: even with wrong bookkeeping this cycle's offs close the gate by the end of
			// the cell — the next onset gets its edge.
			// offAtA/nowT/stillOpen live in the outer scope now (§h-latch v2 needs
			// the gate-front decision before the freq/set sections above).
			var beatDur = TempoClock.default.beatDur;
			// §hold-note THE FLOOR. ev[\dur] is the cell's beat length after the
			// ~w split (dur · w / Σw for a wseq child, dur / n for a seq), so a
			// hold continuation is found for cells of ANY unequal lengths: the
			// off is always durB + 0.03 beat after the onset and the next onset
			// of the lane arrives at durB — 0.03 beat ahead of the off, inside
			// holdTol (0.08). A cell shorter than 0.05 beat is clamped to 0.05,
			// which moves its hold off to 0.08 beat after ITS onset instead of
			// 0.03 after the boundary: a touching same-lane cell still cancels
			// it (a continuation bumps gen), so no run breaks and no note is cut,
			// but a lone sub-0.05-beat hold note sounds 0.08 beat, and a gap up
			// to 0.08 beat minus the RAW cell length (ev[\dur], not the clamped
			// durB) after it is bridged (0.03 for a normal cell).
			// The clamp keeps the reattack and legato offs strictly positive.
			durB = (ev[\dur] ? 1).max(0.05);
			susBeats = if (artic == \hold)
				{ durB + 0.03 }
				{ if (artic == \legato) { (durB - 0.008).max(0.02) } { durB * (ev[\legato] ? 0.85) } };
			// §hold-note a hold event on a voice that is still open never SHORTENS
			// its life: the gate-off goes at the later of the two ends, and the
			// bookkeeping says the same (offAt = max). The gen bump above cancelled
			// the previous off, so the off has to be RESCHEDULED at the old time —
			// a bookkeeping-only max would claim an open gate the server had shut.
			// Continuation: the old end is 0.03 beat away, the new one wins. A
			// same-lane steal (every voice busy) or a same-lane mono overlap: the
			// run merges and plays out to the later end — a nested short note no
			// longer cuts the long one. §steal-x a CROSS-LANE steal is a new note:
			// its off goes at ITS end, the stolen note's end is dropped with the
			// stolen note (the gen bump cancelled its off).
			if (artic == \hold and: { stillOpen } and: { stealX.not }) {
				susBeats = susBeats.max((offAtA[idx] - nowT) / beatDur);
			};
			offAtA[idx] = nowT + (susBeats * beatDur);
			// §steal-x the cross-lane steal takes the micro-dip too: the voice is
			// open on another lane's note, and 1 → 1 would be no attack
			if (stillOpen and: { (artic != \hold) or: { stealX } }) {
				s.sendBundle(nil,   [\error, 0], [\n_set, top[\f2VNode].(voice), \gate, 0], [\error, 1]);
				s.sendBundle(0.004, [\error, 0], [\n_set, top[\f2VNode].(voice), \gate, 1], [\error, 1]);
			} {
				top[\f2VSet].(voice, [\gate, 1]);
			};
			gateOff = {
				if (pool[\gen][idx] == myGen) {
					s.sendBundle(nil, [\error, 0], [\n_set, top[\f2VNode].(voice), \gate, 0], [\error, 1]);
				};
				nil
			};
			TempoClock.default.sched(susBeats, gateOff);
			SystemClock.sched((susBeats * beatDur).max(0.005), gateOff);
		};
	});

	~play = { |key, data, dur=4, quant=4, layers|
		// §node-live a pattern group whose /g_new the server refused reads isPlaying
		// true for ever, and every voice spawned into it would be refused too; the
		// live test falls back to the default group instead, as it does for a group
		// that has really gone
		var grp = if (~f2NodeLive.(~f2PatGroup, ~f2PatGroupAt))
			{ ~f2PatGroup } { s.defaultGroup };
		var basePat = Pn(~toPat.value(data, dur), inf);
		var pattern, final;
		// Layer system: independent layers merged per-event via Prout zipper.
		// Can't use Pchain — ~toPat yields complete events that ignore inval.
		// Can't use Plazy — variable capture on reassigned `pattern` breaks stream.
		// Solution: direct Prout with .keys.includes check (Event proto has defaults
		// like degree:0, scale:major — must check own keys, not [k].isNil).
		// Pn(Prout, inf) restarts all streams each cycle.
		if (layers.notNil and: { layers.isKindOf(Array) and: { layers.size > 0 } }) {
			var validLayers = layers.select(_.isKindOf(Pattern));
			if (validLayers.size > 0) {
				pattern = Prout({ |inval|
					var ms = basePat.asStream;
					var ls = validLayers.collect(_.asStream);
					var ev;
					ev = ms.next(inval);
					while { ev.notNil } {
						// Only merge layers for non-rest events.
						// Rests pass through — melody pointer stays put.
						if (ev[\type] != \rest) {
							ls.do { |layerStream|
								var le = layerStream.next(ev);
								if (le.notNil and: { le.isKindOf(Event) }) {
									le.keysValuesDo { |k, v|
										if (v.notNil) {
											if (ev.keys.includes(k).not) { ev.put(k, v) };
										};
									};
								};
							};
						};
						inval = ev.yield;
						ev = ms.next(inval);
					};
				});
				pattern = Pn(pattern, inf);
			} {
				pattern = basePat;
			};
		} {
			pattern = basePat;
		};
		// Cell telemetry: send f2_cid via OSC before enriching
		~f2CellAddr = ~f2CellAddr ?? { NetAddr("127.0.0.1", 57130) };
		final = Pcollect({ |ev|
			var cid = ev[\f2_cid];
			if (cid.notNil) {
				try { ~f2CellAddr.sendMsg('/f2_cell', cid) } {};
				ev.removeAt(\f2_cid);
			};
			~enrich.value(ev)
		}, pattern);
		"[f2] ~play.(\\%, dur:%, group:%)".format(key, dur, grp.nodeID).postln;
		// §sync quant OF THE Pdef PROXY ITSELF (not only the player): swapping the source on a
		// REDEPLOY is scheduled by Pdef.quant, not by the .play argument. The default (1 beat)
		// swapped the new cycle in on ANY beat → SC's origin ≠ the engine's origin (frac(beat/dur))
		// → the modulation windows slid by (the swap beat mod dur) FOREVER: the audible cell got
		// only the base (knob) while the modulation was composed for another one. The swap is
		// strictly on the ROW's LOOP boundary — the same grid on which the engine introduces
		// deferred structure (§smooth-restart).
		Pdef(key).quant_(quant);
		Pdef(key, final).play(TempoClock.default,
			(group: grp, addAction: \addToHead), quant);
	};

	~enrich = { |ev|
		var r = globalEnv.at(\rack);
		var res = ev.copy;
		var instr = res[\instrument];
		var samplesDict = globalEnv.at(\samples) ?? { Dictionary.new };
		var defsDict = globalEnv.at(\defs) ?? { Dictionary.new };
		var modalDict = globalEnv.at(\modalBuffers) ?? { Dictionary.new };

		// 1. MERGE DEFAULTS FIRST
		var defResolved = false;
		if (res[\type] != \rest) {
			if (instr.notNil and: { defsDict[instr].notNil }) {
				var def = defsDict[instr];
				res = def.copy.putAll(res);
				if (def[\instrument].notNil) {
					res[\instrument] = def[\instrument];
					instr = res[\instrument];
					defResolved = true;
				};
			};
		};

		// 2. Audio Samples handling
		// Skip if: defs resolved instrument, OR instrument has a SynthDesc (is a real synth)
		if (defResolved.not and: { instr.notNil } and: { samplesDict[instr].notNil }) {
			if (SynthDescLib.global.synthDescs[instr].notNil) {
				// instr is a real SynthDef — don't replace with gran
				"[f2 enrich] % is a SynthDef, skipping sample override".format(instr).postln;
			} {
				res[\buf] = samplesDict[instr];
				res[\instrument] = \gran;
				instr = \gran;
			};
		};

		// 3. Modal Data Injection
		if (res[\material].notNil and: { modalDict[res[\material]].notNil }) {
			var buffs = modalDict[res[\material]];
			res[\f] = buffs[\f];
			res[\a] = buffs[\a];
			res[\d] = buffs[\d];
		};
		// Fallback
		if (instr.notNil and: { modalDict[instr].notNil }) {
			var buffs = modalDict[instr];
			res[\f] = buffs[\f]; res[\a] = buffs[\a]; res[\d] = buffs[\d];
		};

		res[\out] = r.bus.main.index;
		res[\tel_bus] = r.bus.tel.index;

		// 4a. Self-freeing synths (DetectSilence / doneAction:2):
		// modalS kills itself via DetectSilence. But SC Event also sends
		// gate:0 after 'sustain' seconds → /n_set on dead node → error.
		// And long decayScale causes node accumulation.
		//
		// Fix: sustain = dur (SC sends harmless gate:0 right when next note starts).
		// Safety n_free scheduled slightly after, error-suppressed.
		// No more timing races, no abrupt cuts.
		{
			var maxLife, prevCb, safetyTime;
			if (res[\selfFree] == true) {
				maxLife = (res[\dur] ?? 1) * TempoClock.default.beatDur;
				// Safety: actual synth life depends on decayScale, NOT on dur
				safetyTime = ((res[\decayScale] ?? 1.0) * 1.5).max(maxLife) + 2.0;
				prevCb = res[\callback];
				res[\sustain] = maxLife;
				res[\sendGate] = false;
				res.removeAt(\selfFree);
				res[\callback] = { |ev|
					prevCb.value(ev);
					if (ev[\id].notNil and: { ev[\type] != \rest }) {
						// Safety net: generous, synths self-free via doneAction:2
						SystemClock.sched(safetyTime, {
							ev[\id].asArray.do { |id|
								s.sendBundle(nil,
									[\error, 0],
									[\n_free, id],
									[\error, 1]
								);
							};
						});
					};
				};
			};
		}.value;

		// 4. FX Param Locks (error-safe: skip bad params with warning)
		// Reserved: setting these via Ndef.set breaks proxy routing/volume
		{
			var ndefReserved = Set[\amp, \out, \i_out, \gate, \fadeTime, \in, \tel_bus, \bus, \group, \addAction, \server, \instrument, \type, \dur, \sustain, \sendGate, \callback, \finish, \selfFree, \id, \freq, \midinote, \note, \degree];
			globalEnv.at(\dsl).fxTargets.keysValuesDo { |key, ndefName|
				if (res[key].notNil) {
					var val = res[key];
					var prevFunc = res[\finish];
					res[\finish] = {
						prevFunc.value;
						try {
							if (val.isKindOf(Event)) {
								// Safe pair-level iteration (asPairs.select was broken — misaligned pairs)
								var safePairs = [];
								val.keysValuesDo { |k, v|
									if (ndefReserved.includes(k).not and: { v.notNil and: { v.isNumber } }) {
										safePairs = safePairs ++ [k, v];
									};
								};
								if (safePairs.size > 0) {
									"[f2 fxLock] % → Ndef(%) .set(%)".format(key, ndefName, safePairs).postln;
									Ndef(ndefName).set(*safePairs);
								};
							} {
								if (val.isNumber and: { ndefReserved.includes(key).not }) {
									Ndef(ndefName).set(key, val)
								};
							};
						} { |err|
							"[f2 warn] FX param lock %: % — skipped".format(key, err.errorString).postln;
						};
					};
					res.removeAt(key);
				}
			};
		}.value;

		// §reuse: a persistent voice instead of a spawn per note. Conditions: the toggle is on, this
		//   is not a rest, the preset has a cfg (res[\f2def] from the def), the synthdef is gated, and
		//   this is NOT a harmonic voice (detunedFreq → a voice bus, a different path). \f2voice takes
		//   a voice from the pool (see addEventType).
		// §cards-orphan a COMPOSITE preset (instrument \chain / \stack) has no
		//   SynthDef of its own, so \f2voice is its ONLY spawn path — it takes
		//   that road whatever the ~f2Reuse toggle says and whatever the cfg
		//   carries. Without this the default event type asks the server for a
		//   def literally named "chain": the post window fills with
		//   «FAILURE IN SERVER /s_new SynthDef not found» + «/n_set Node N not
		//   found» pairs that name neither the preset nor the cause. \f2voice
		//   plays an empty strip instead and says once what is wrong (the cfg
		//   line came from an engine older than §cards — rebuild core/f2core).
		if (res[\type] != \rest and: { #[\chain, \stack].includes(res[\instrument]) }
			and: { res[\f2def].notNil }) {
			res[\f2cfg] = (globalEnv.at(\f2ReuseCfg) ? IdentityDictionary.new)[res[\f2def]];
			res[\f2hasFree] = false;
			res[\type] = \f2voice;
		};
		if ((globalEnv.at(\f2Reuse) ? true) and: { res[\type] != \rest }
			and: { res[\type] != \f2voice }
			and: { res[\f2def].notNil }) {
			var rcfg = (globalEnv.at(\f2ReuseCfg) ? IdentityDictionary.new)[res[\f2def]];
			var rsd = SynthDescLib.global.at(res[\instrument]);
			// §artic EVERY gated synth goes through \f2voice — otherwise the reatk/legato/hold
			//   articulation and the voice pool do not work at all (the old guard also demanded
			//   \i_free, and EVERY project synth without it played by spawning — «the modes make no
			//   difference»). A synth WITHOUT \i_free frees itself on release: the pool sees that
			//   (isPlaying) and recreates the voice — for reatk and legato that is equivalent to
			//   spawning, while hold MERGES a run of adjacent cells (the gate does not fall inside
			//   the run — the synth is alive). Harmonic presets (detunedFreq) are no longer excluded:
			//   the frequency is latched as a number at the onset (§h-latch), so reuse does not get in
			//   the voice's way.
			// §stack a composite preset has no SynthDef of its own (instrument
			// \stack): its cfg carries the sub-unit list and \f2voice spawns the
			// group — reuse-eligible by construction. §cards strips (instrument
			// \chain, cfg[\chain]) take the same road.
			if (rcfg.notNil and: { rcfg[\stack].notNil or: { rcfg[\chain].notNil }
				or: { rsd.notNil and: { rsd.controlNames.includes(\gate) } } }) {
				res[\f2cfg] = rcfg;
				res[\f2hasFree] = rsd.notNil and: { rsd.controlNames.includes(\i_free) };
				res[\type] = \f2voice;
			};
		};
		res;
	};

	// ═══════════════════════════════════════════════════════════
	// D2. LAYER SYSTEM — Independent Pchain layers
	// ═══════════════════════════════════════════════════════════
	//
	// Three-tree architecture:
	//   Tree 1 (main)     — rhythm + presets → full events with dur (existing ~toPat)
	//   Tree 2 (melody)   — degree/scale/root → value stream, cycles independently
	//   Tree 3 (dynamics) — amp/sustain/articulation → value stream, cycles independently
	//
	// Layers are compiled via ~toValPat (no dur) and wrapped in Pbind.
	// Pchain merges them: main tree provides dur/instrument, layers provide
	// degree, amp, etc. Each layer cycles at its own rate — a 5-note melody
	// over a 16-step rhythm creates polyrhythmic interplay.
	//
	// Usage:
	//   ~play.(\track, mainTree, 16, 4, [
	//       ~layer.(\degree, ~q[0, 3, 5, 7, 2]),
	//       ~layer.(\amp, ~q[1.0, 0.5, 0.8, 0.3])
	//   ]);
	//
	//   // With scale changes:
	//   ~play.(\track, mainTree, 16, 4, [
	//       ~mlayer.(~q[
	//           ~m[~q[0, 2, 4, 7], (scale: Scale.minor)],
	//           ~m[~q[5, 3, 1, 0], (scale: Scale.major, root: 3)]
	//       ])
	//   ]);
	//
	// ═══════════════════════════════════════════════════════════

	// ~toValPat: compile DSL tree → Pattern of bare values (no dur)
	// Same operators as ~toPat, but atoms produce values, not timed events.
	// Structure nodes control ORDER of values, not their timing.

	~toValPat = { |obj|
		if (obj.isNil) { Pseq([Rest()], 1) }
		{
		if (obj.isKindOf(Function)) {
			Plazy({ ~toValPat.value(obj.value) })
		}
		{
		if (obj.isKindOf(Event) and: { obj[\dsl_type].notNil }) {
			var type = obj[\dsl_type];

			case

			// ─── STRUCTURE ───

			{ type == \seq } {
				var list = obj[\list];
				if (list.isNil or: { list.size == 0 }) {
					Pseq([Rest()], 1)
				} {
					Pseq(list.collect { |item| ~toValPat.value(item) }, 1)
				}
			}
			{ type == \par } {
				// par in value context = chord (simultaneous notes)
				var list = obj[\list];
				if (list.every(_.isNumber)) {
					// Pure numbers → array-as-degree (SC plays chord)
					Pseq([list], 1)
				} {
					// Mixed content → Ptuple (parallel value streams)
					Ptuple(list.collect { |item| ~toValPat.value(item) }, 1)
				}
			}
			{ type == \bind } {
				// ~m in value context: head provides core values,
				// modifiers add extra keys (scale, root, octave, etc.)
				Plazy({
					var head = obj[\head];
					var params = obj[\args];
					var pureParams, headStream, headLen, mods, headPat;

					// Function modifiers wrap the head first (same as ~toPat)
					params.do { |p|
						if (p.isKindOf(Function)) {
							head = try { p.(head) } { |err|
								"[f2 warn] layer bind mod fn: %".format(err.errorString).postln;
								head
							};
						};
					};

					pureParams = params.reject(_.isKindOf(Function));
					headStream = ~toValPat.value(head);

					// Count the length of the head if it's a ~q (for Pn cycling)
					headLen = inf;
					if (head.isKindOf(Event) and: { head[\dsl_type] == \seq }) {
						headLen = head[\list].size;
					};
					if (head.isKindOf(Event) and: { head[\dsl_type] == \rep }) {
						headLen = head[\times] ? 2;
					};

					// Build modifiers as Pbind layers
					mods = pureParams.collect { |p|
						if (p.isKindOf(Event) and: { p[\dsl_type].notNil }) {
							// Nested DSL node as modifier
							var mtype = p[\dsl_type];
							if (#[\pick, \ramp, \osc, \drift, \slew, \stepR, \lfoR, \envR].includes(mtype)) {
								// Modulation nodes already produce Pbind(\param, stream)
								// Reuse ~toPat — they don't need dur anyway
								~toPat.value(p, 1)
							} {
								// Structure node as modifier → value stream for \degree
								Pbind(\degree, ~toValPat.value(p))
							}
						} {
							if (p.isKindOf(Event)) {
								// Raw event modifier → Pbind of all keys
								Pbind(*p.asPairs)
							} {
								if (p.isNumber) {
									Pbind(\degree, p)
								} {
									if (p.isKindOf(Pattern)) { p }
									{ Pbind() }
								}
							}
						}
					};

					// Wrap head value stream as Pbind(\degree, ...)
					// headStream yields bare values → map to \degree key
					headPat = Pbind(\degree, headStream);

					if (mods.size > 0) {
						// headPat (degree from head) has HIGHER priority,
						// but mods can add scale, root, octave, etc.
						Pchain(headPat, *mods)
					} { headPat }
				})
			}
			{ type == \wseq } {
				// Weighted sequence in value context:
				// weight → repeat count (rounded to integer, min 1)
				var pairs = obj[\pairs];
				Pseq(pairs.collect { |pair|
					var val = pair[0], w = pair[1].round.asInteger.max(1);
					Pn(~toValPat.value(val), w)
				}, 1)
			}
			{ type == \rand } {
				Plazy({ ~toValPat.value(obj[\list].choose) })
			}
			{ type == \wrand } {
				Plazy({
					var pairs = obj[\pairs];
					var items = pairs.collect(_[0]);
					var weights = pairs.collect(_[1]).normalizeSum;
					~toValPat.value(items.wchoose(weights))
				})
			}
			{ type == \rep } {
				var times = obj[\times] ? 2;
				Pn(~toValPat.value(obj[\item]), times)
			}

			// ─── MODULATION (reuse ~toPat — they already produce Pbind, no dur) ───

			{ type == \pick } { ~toPat.value(obj, 1) }
			{ type == \ramp } { ~toPat.value(obj, 1) }
			{ type == \fxRamp } { ~toPat.value(obj, 1) }
			{ type == \osc }  { ~toPat.value(obj, 1) }
			{ type == \drift } { ~toPat.value(obj, 1) }
			{ type == \slew }  { ~toPat.value(obj, 1) }
			{ type == \stepR } { ~toPat.value(obj, 1) }
			{ type == \lfoR }  { ~toPat.value(obj, 1) }
			{ type == \envR }  { ~toPat.value(obj, 1) }

			// ─── FALLBACK ───
			{ true } { Pseq([Rest()], 1) };
		}

		// ─── NON-DSL OBJECTS ───
		{
			if (obj.isKindOf(Pattern)) { obj }
			{
			if (obj.isKindOf(Array)) {
				// Array: if all numbers → chord, else → sequence
				if (obj.every(_.isNumber)) {
					Pseq([obj], 1)
				} {
					Pseq(obj.collect { |item| ~toValPat.value(item) }, 1)
				}
			}
			{
				if (obj.isKindOf(Symbol)) {
					// Symbols in value context (scale names, etc.)
					if (obj == \x) { Pseq([Rest()], 1) }
					{ Pseq([obj], 1) }
				}
				{
					if (obj.isNumber) {
						Pseq([obj], 1)
					}
					{
						if (obj.isKindOf(Event)) {
							// Raw event → pass through as partial event
							Pseq([obj], 1)
						}
						{ Pseq([obj], 1) }
					}
				}
			}
			}
		}
		}
		}
	};

	// ~layer: wrap a DSL value tree into an infinite Pbind layer
	// key: event key to fill (\degree, \amp, \sustain, etc.)
	//      if nil, tree must produce Events (via ~m with modifiers)
	// tree: DSL tree using standard operators (~q, ~r, ~w, ~n, ~c, ~m)
	// Returns: infinite-cycling Pattern suitable for Pchain with ~play
	//
	// Examples:
	//   ~layer.(\degree, ~q[0, 3, 5, 7])
	//   ~layer.(\amp, ~q[1.0, 0.5, 0.8, 0.3, 1.0, 0.2])
	//   ~layer.(\degree, ~r[~q[0,2,4], ~q[0,3,7], ~q[0,5,9]])
	//   ~layer.(\degree, ~w[0, 3, 3, 1, 5, 2])
	//   ~layer.(nil, ~m[~q[0,2,4,7], (scale: Scale.minor)])

	~layer = { |key, tree|
		var valPat = Pn(~toValPat.value(tree), inf);
		if (key.notNil) {
			Pbind(key, valPat)
		} {
			// Tree produces Events directly (via ~m with modifiers)
			// Already contains key mappings
			valPat
		}
	};

	// ~mlayer: melody layer — degree tree + optional scale/root/octave
	// Convenience for the most common layer type.
	//
	// Examples:
	//   ~mlayer.(~q[0, 3, 5, 7, 2])
	//   ~mlayer.(~q[0, 3, 5, 7], Scale.minor, 0, 4)
	//   ~mlayer.(~q[
	//       ~m[~q[0, 2, 4, 7], (scale: Scale.minor)],
	//       ~m[~q[5, 3, 1, 0], (scale: Scale.major, root: 3)]
	//   ])

	~mlayer = { |degreeTree, scale, root, octave|
		var binds = [\degree, Pn(~toValPat.value(degreeTree), inf)];
		if (scale.notNil) { binds = binds ++ [\scale, scale] };
		if (root.notNil) { binds = binds ++ [\root, root] };
		if (octave.notNil) { binds = binds ++ [\octave, octave] };
		Pbind(*binds)
	};

	// ~dlayer: dynamics layer — articulation tree for amp/sustain/stretch
	// Provides named articulation presets that map to concrete param values.
	//
	// Articulation atoms:
	//   \hit    → (amp: 1.0)                    — normal
	//   \ghost  → (amp: 0.15)                   — barely audible
	//   \accent → (amp: 1.3)                    — emphasis
	//   \duck   → (amp: 0, sustain: 0.001)      — negative space
	//   \choke  → (sustain: 0.05)               — cut short
	//   \swell  → (amp: ramp 0.3→1.0)           — within-step crescendo
	//   number  → (amp: number)                  — direct amp value
	//
	// Examples:
	//   ~dlayer.(~q[\hit, \hit, \accent, \ghost, \duck, \hit, \ghost, \hit])
	//   ~dlayer.(~q[1.0, 0.5, 1.2, 0.3])
	//   ~dlayer.(~r[\hit, \accent, \ghost])

	~articulationMap = Dictionary.newFrom([
		\hit,    (amp: 1.0),
		\ghost,  (amp: 0.15),
		\accent, (amp: 1.3),
		\duck,   (amp: 0, sustain: 0.001),
		\choke,  (sustain: 0.05),
		\soft,   (amp: 0.4),
		\mf,     (amp: 0.7),
		\ff,     (amp: 1.5)
	]);

	~dlayer = { |tree|
		// Compile tree to value stream, then map articulation symbols to events
		var valPat = Pn(~toValPat.value(tree), inf);
		Pcollect({ |val|
			var mapped;
			if (val.isKindOf(Symbol)) {
				mapped = ~articulationMap[val];
				if (mapped.notNil) { mapped.copy } { () }
			} {
				if (val.isNumber) { (amp: val) }
				{
					if (val.isKindOf(Event)) { val }
					{ () }
				}
			}
		}, valPat)
	};

	// ═══════════════════════════════════════════════════════════
	// E. TEMPLATE MACRO
	// ═══════════════════════════════════════════════════════════

	~mkTemplate = { |... variants|
		{ |fill, variant, modul|
			var expanded = variants.collect { |vFunc|
				var inner = vFunc.value(fill);
				if (modul.notNil) { ~m[inner, modul] } { inner };
			};
			if (variant.notNil) { expanded[variant] } { expanded.choose }
		}
	};

	// ═══════════════════════════════════════════════════════════
	// F. GEOMETRY & POSITION HELPERS
	// ═══════════════════════════════════════════════════════════

	~geoUtil = (
		calcOffset: { |self, shape, phase, radius|
			var angle = phase * 2pi;
			var dx = 0, dy = 0;
			switch(shape,
				\circle, { dx = cos(angle); dy = sin(angle); },
				\line,   { dx = (phase - 0.5) * 2; dy = 0; },
				\tri,    { var q = (phase*3).round(1)%3; var a=(q*(2pi/3))-(pi/2); dx=cos(a); dy=sin(a); },
				\square, { var q = (phase*4).round(1)%4; dx=case{q==0}{-1}{q==1}{1}{q==2}{1}{q==3}{-1}; dy=case{q==0}{1}{q==1}{1}{q==2}{-1}{q==3}{-1}; },
				\pent,   { var q = (phase*5).round(1)%5; var a=(q*(2pi/5))-(pi/2); dx=cos(a); dy=sin(a); },
				\hex,    { var q = (phase*6).round(1)%6; var a=(q*(2pi/6)); dx=cos(a); dy=sin(a); },
				\x,      { var q = (phase*4).round(1)%4; dx=case{q==0}{0}{q==1}{1}{q==2}{0}{q==3}{-1}; dy=case{q==0}{1}{q==1}{0}{q==2}{-1}{q==3}{0}; },
				\star,   { var st=5; var ps=phase*st; var idx=floor(ps); var in=(ps%1)>0.5; var r=if(in){0.4}{1.0}; var a=(idx*(2pi/st))-(pi/2); if(in){a=a+(pi/st)}; dx=cos(a)*r; dy=sin(a)*r; },
				\spiral, { var t=3; var r=phase; var a=phase*2pi*t; dx=cos(a)*r; dy=sin(a)*r; }
			);
			[dx * radius, dy * radius]
		}
	);

	~geo = { |center, shape=\circle, points=4, radius=0.2, mode=\wide|
		var c = center ?? [0.5, 0.5];
		var phases = Array.fill(points, { |i| i / points });
		phases.collect { |p|
			var p1 = p;
			var p2 = switch(mode, \pair, {p+0.02}, \wide, {p+0.5}, \ortho, {p+0.25}, \tri, {p+0.33}, {p+0.5});
			var d1 = ~geoUtil.calcOffset(shape, p1, radius);
			var d2 = ~geoUtil.calcOffset(shape, p2, radius);
			[(c[0]+d1[0]).clip(0,1), (c[1]+d1[1]).clip(0,1), (c[0]+d2[0]).clip(0,1), (c[1]+d2[1]).clip(0,1)]
		}
	};

	// ═══════════════════════════════════════════════════════════
	// G. SEQUENCER RECIPES
	// ═══════════════════════════════════════════════════════════

	~sRUp = { |instr, len=8|
		~m[ ~n[instr, len],
			~ramp[\amp, 0.15, 1.0, \exp],
			~ramp[\pan, -1, 1],
			~ramp[\drive, 1, 20]
		]
	};

	~sRDown = { |instr, len=6|
		~m[ ~n[instr, len],
			~ramp[\amp, 0.8, 0.05, \exp],
			~osc[\pan, [0, -0.5, 0.5, -0.8, 0.8, -1]],
			~ramp[\rate, 1.0, 1.8, \exp]
		]
	};

	~sRattle = { |instr, len=16, durStart=1.0, durEnd=0.5, dyn=0.5|
		var baseAmp = (instr[\amp] ?? 0.8);
		~m[ ~n[instr, len],
			~ramp[\stretch, durStart, durEnd, \exp],
			~osc[\amp, [baseAmp, baseAmp * (1.0 - dyn)]],
			~ramp[\rub, 0.0, 0.2, \rand]
		]
	};

	~sRBurn = { |instr, len=16|
		~m[ ~n[instr, len],
			(stretch: 0.5, amp: 0.9),
			~ramp[\drive, 10, 50, \exp],
			~ramp[\pan, -0.2, 0.2, \rand]
		]
	};

	~sRChaos = { |instr, len=8|
		~m[ ~n[instr, len],
			~ramp[\stretch, 0.2, 1.5, \rand],
			~ramp[\amp, 0.2, 1.0, \rand],
			~ramp[\pan, -1.0, 1.0, \rand]
		]
	};

	~sAutoDefault = Routine {
		loop {
			yield(~sRUp); yield(~sRDown); yield(~sRattle);
			yield(~sRBurn); yield(~sRChaos);
		}
	};

	~sAuto = { |instr, len=8, logic|
		var routine = logic ?? ~sAutoDefault;
		var func = routine.next;
		if(func.isNil) { routine.reset; func = routine.next ?? ~sRUp; };
		func.value(instr, len);
	};

	~sAutoDefault.reset;

	// ═══════════════════════════════════════════════════════════
	// G2. TELEMETRY HELPER
	// ═══════════════════════════════════════════════════════════
	//
	// Call inside SynthDef body — produces UGen graph at compile time.
	// Format: [synthType, colorID, env, amp, pan, posX, posY, p0, p1, p2, p3]
	//
	// Classes:
	//   positioned (foldS, pluckS, modalS): posX=srcX, posY=srcY
	//   simple     (kickS, snareS, hatS):  posX=pan→[0,1], posY=freq→[0,1]
	//   tonal      (clayPS, amS):          posX=pan→[0,1], posY=freq→[0,1]

	~mkTel = { |synthType, colorID, env, amp, pan, posX, posY,
		p0=0, p1=0, p2=0, p3=0, telBus|
		SendReply.kr(Impulse.kr(30), '/f2_tel',
			[synthType, colorID, env, amp, pan, posX, posY, p0, p1, p2, p3]);
		Out.kr(telBus, [env, posX, posY, p0]);
	};

	// ═══════════════════════════════════════════════════════════
	// G3. DENSITY ENGINE — palettes, layers, stacking
	// ═══════════════════════════════════════════════════════════

	~pal = ();

	// basic: repeat voice, ghost on high density
	~pal[\basic] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { v }
		{ d <= 3 } { ~n[v, d] }
		{ true }   { ~n[~r[v, g, v], d] }
	};

	// fill: micro-fills with accent toward end
	~pal[\fill] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { v }
		{ d <= 3 } {
			~m[~q[v, g, v], ~osc[\amp, [0.5, 0.3, 0.1]]]
		}
		{ d <= 5 } {
			~m[~q[v, \x, g, v, v],
				~osc[\amp, [0.4, 0.0, 0.3, 0.6, 1.0]],
				~ramp[\crinkle, 0.0, 0.4, \exp]]
		}
		{ true } {
			~m[~q[g, v, \x, g, v, g, v],
				~osc[\amp, [0.3, 0.5, 0.0, 0.3, 0.6, 0.8, 1.0]],
				~ramp[\clickVol, 0.2, 0.8, \lin]]
		}
	};

	// gate: density → amp modulation depth
	~pal[\gate] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { v }
		{ d <= 2 } { ~m[~n[v, 2], ~osc[\amp, [1.0, 0.4]]] }
		{ d <= 4 } { ~m[~n[v, d], ~osc[\amp, [1.0, 0.2, 0.6, 0.15]]] }
		{ true }   { ~m[~n[~r[v, g], d],
			~osc[\amp, [1.0, 0.1, 0.5, 0.1, 0.8, 0.1]],
			~osc[\crinkle, [0.0, 0.3, 0.0, 0.5, 0.0, 0.7]]] }
	};

	// space: density → wetter, wider, further
	~pal[\space] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { ~m[v, (roomSize: 0.05, amp: 0.9)] }
		{ d <= 3 } { ~m[~n[v, d],
			(roomSize: 0.3, amp: 0.7),
			~drift[\mic1X, 0.5, 0.1, 3]] }
		{ d <= 5 } { ~m[~n[~r[v, g, v], d],
			~ramp[\roomSize, 0.1, 0.6, \exp],
			~ramp[\amp, 0.8, 0.5, \lin],
			~drift[\mic1X, 0.5, 0.1, 4],
			~drift[\mic2Y, 0.5, 0.1, 4]] }
		{ true }   { ~m[~n[~r[v, g], d],
			(roomSize: 0.7, amp: 0.4),
			~pick[#[mic1X, mic1Y, mic2X, mic2Y],
				~geo.([0.5,0.5], \hex, 6, 0.2), 4]] }
	};

	// roll: accelerating buildup — ghost only in tail
	~pal[\roll] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { v }
		{ d <= 3 } { ~m[~n[v, d], ~ramp[\amp, 0.4, 1.0, \exp]] }
		{ d <= 5 } { ~m[~q[v, v, g, v, v],
			~ramp[\amp, 0.3, 1.0, \exp],
			~ramp[\stretch, 1.2, 0.8, \lin]] }
		{ true }   { ~m[~n[~r[v, v, g], d],
			~ramp[\amp, 0.2, 1.0, \exp],
			~ramp[\clickVol, 0.3, 0.9, \exp]] }
	};

	// sweep: density → rising amp sweep (replaces mkSweep factory)
	~pal[\sweep] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { v }
		{ d <= 3 } { ~m[~n[v, d], ~ramp[\amp, 0.2, 1.0, \lin]] }
		{ true }   { ~m[~n[~r[v, g, v], d],
			~ramp[\amp, 0.2, 1.0, \exp],
			~osc[\amp, [1.0, 0.3, 0.7, 0.2, 0.8, 0.15, 1.0]]] }
	};

	// dark: density → crinkle + roomSize grows
	~pal[\dark] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { ~m[v, (crinkle: 0.1, roomSize: 0.2)] }
		{ d <= 3 } { ~m[~n[v, d], ~ramp[\crinkle, 0.0, 0.5, \exp], ~ramp[\roomSize, 0.1, 0.5, \lin]] }
		{ true }   { ~m[~n[~r[v, g], d],
			~ramp[\crinkle, 0.0, 0.8, \exp],
			~ramp[\roomSize, 0.2, 0.8, \lin],
			~osc[\amp, [0.8, 0.4, 0.6, 0.3]]] }
	};

	// stutter: burst of notes with random amp
	~pal[\stutter] = { |d, v, g|
		d = d ? 0; d = d.asInteger;
		case
		{ d == 0 } { \x }
		{ d == 1 } { v }
		{ d <= 3 } { ~m[~n[v, d],
			~ramp[\amp, 0.2, 1.0, \rand],
			~ramp[\stretch, 0.8, 1.2, \rand]] }
		{ true }   { ~m[~n[~r[v, g, v, g], d],
			~ramp[\amp, 0.1, 1.0, \rand],
			~ramp[\pan, -0.5, 0.5, \rand]] }
	};

	// --- Core density functions ---

	~cellDens = { |voice, ghost, densities, palette, mod|
		var pal = palette ? ~pal[\basic];
		var items = densities.collect { |d|
			try {
				if (d.isKindOf(Event)) {
					var dVal = d[\dens] ?? 1;
					// Extract DSL mods (ramps, mod functions) stored under f2mods key
					var dslMods = d[\f2mods];
					var modEv = d.copy;

					var base = pal.(dVal, voice, ghost);
					var allMods = [];
					modEv.removeAt(\dens);
					modEv.removeAt(\f2mods);
					// Filter: only keep keys with valid values
					modEv = modEv.select({ |v| v.notNil and: { v != "" } });

					if (modEv.size > 0) { allMods = allMods.add(modEv) };
					if (dslMods.notNil and: { dslMods.isKindOf(Array) }) {
						dslMods.select(_.notNil).do { |dm|
							if (dm.isKindOf(Function)) {
								// Mod library: {|pat| ~m[pat, ...]} — call with base
								base = try { dm.(base) } { |err|
									"[f2 warn] step mod fn: % — skipped".format(err.errorString).postln;
									base
								};
							} {
								allMods = allMods.add(dm);
							};
						};
					};
					if (allMods.size > 0) {
						(dsl_type: \bind, head: base, args: allMods)
					} { base };
				} {
					pal.(d.asInteger, voice, ghost)
				}
			} { |err|
				"[f2 warn] cellDens step %: % — rest".format(d, err.errorString).postln;
				\x
			};
		};
		var pat = (dsl_type: \seq, list: items);
		if(mod.notNil) {
			// mod can be:
			// - Function: ~mod[\wobMic].(0.1, 4) returns { |pat| ~m[pat, ...] }
			// - Event: (crinkle: 0.5) from synthLock
			// - DSL node: (dsl_type: \ramp, ...) from ~ramp[...]
			if (mod.isKindOf(Function)) {
				try { mod.(pat) } { |err|
					"[f2 warn] mod function: % — skipped".format(err.errorString).postln;
					pat
				}
			} {
				// Non-function: wrap as ~m[pat, mod]
				(dsl_type: \bind, head: pat, args: [mod])
			}
		} { pat }
	};

	~layer = { |voice, ghost, dens, palette, mod|
		(voice: voice, ghost: ghost, dens: dens,
			palette: palette ? ~pal[\basic], mod: mod)
	};

	~stackLayers = { |layers, globalMod|
		var validLayers = layers.collect { |l|
			try {
				~cellDens.(l[\voice], l[\ghost], l[\dens],
					l[\palette], l[\mod])
			} { |err|
				"[f2 warn] layer %: % — skipped".format(l[\voice], err.errorString).postln;
				nil
			}
		}.select(_.notNil);
		if (validLayers.size == 0) {
			"[f2 warn] all layers failed — rest".postln;
			\x
		} {
			var pat = (dsl_type: \par, list: validLayers);
			if(globalMod.notNil) {
				if (globalMod.isKindOf(Function)) {
					try { globalMod.(pat) } { |err|
						"[f2 warn] globalMod: % — skipped".format(err.errorString).postln;
						pat
					}
				} {
					(dsl_type: \bind, head: pat, args: [globalMod])
				}
			} { pat }
		}
	};

	// Convenience: pad layer with degree & drift
	~padLayer = { |voice, deg, mod|
		var pat = ~m[~n[voice, 2],
			~osc[\degree, if(deg.isKindOf(Array)) { deg } { [deg] }],
			~drift[\mic1X, 0.5, 0.1, 3],
			~drift[\mic2Y, 0.5, 0.08, 5]];
		if(mod.notNil) { mod.(pat) } { pat }
	};

	// ═══════════════════════════════════════════════════════════
	// G4. BUILT-IN MODIFIERS
	// ═══════════════════════════════════════════════════════════

	~mod = ();

	~mod[\wobMic] = { |amt=0.1, spd=4|
		{ |pat| ~m[pat,
			~drift[\mic1X, 0.5, amt, spd], ~drift[\mic1Y, 0.5, amt, spd],
			~drift[\mic2X, 0.5, amt, spd], ~drift[\mic2Y, 0.5, amt, spd]] }
	};

	~mod[\spread] = { |shape=\hex, pts=6, r=0.25, scope=4|
		{ |pat| ~m[pat,
			~pick[#[mic1X, mic1Y, mic2X, mic2Y],
				~geo.([0.5, 0.5], shape, pts, r), scope]] }
	};

	~mod[\swell] = { |from=0.2, to=1.0, curve=\exp|
		{ |pat| ~m[pat, ~ramp[\amp, from, to, curve]] }
	};

	~mod[\fade] = { |from=1.0, to=0.05, curve=\exp|
		{ |pat| ~m[pat, ~ramp[\amp, from, to, curve]] }
	};

	~mod[\morph] = { |fromX=0.2, toX=0.8|
		{ |pat| ~m[pat,
			~ramp[\mic1X, fromX, toX, \lin],
			~ramp[\mic2X, toX, fromX, \lin]] }
	};

	~mod[\shimmer] = { |lo=0.5, hi=1.0|
		{ |pat| ~m[pat,
			~osc[\amp, [hi, lo, hi*0.8, lo*1.2]],
			~osc[\clickVol, [0.6, 0.3, 0.5, 0.25]]] }
	};

	~mod[\darken] = {
		{ |pat| ~m[pat,
			~ramp[\crinkle, 0.0, 0.6, \exp],
			~ramp[\roomSize, 0.1, 0.7, \lin]] }
	};

	~mod[\micSnap] = { |ax=0.1, ay=0.1, bx=0.9, by=0.9|
		{ |pat| ~m[pat,
			~osc[\mic1X, [ax, bx]], ~osc[\mic1Y, [ay, by]],
			~osc[\mic2X, [bx, ax]], ~osc[\mic2Y, [by, ay]]] }
	};

	~mod[\diagCrawl] = { |spd=3|
		{ |pat| ~m[pat,
			~ramp[\srcX, 0.1, 0.9, \lin],
			~ramp[\srcY, 0.9, 0.1, \lin],
			~drift[\mic1X, 0.3, 0.15, spd],
			~drift[\mic2Y, 0.7, 0.15, spd]] }
	};

	~mod[\spiralScatter] = { |r=0.3, pts=12|
		{ |pat| ~m[pat,
			~pick[#[mic1X, mic1Y, mic2X, mic2Y],
				~geo.(nil, \spiral, pts, r), \event]] }
	};

	~mod[\ampGate] = { |vals|
		{ |pat| ~m[pat, ~osc[\amp, vals]] }
	};

	~mod[\crinkGate] = { |vals|
		{ |pat| ~m[pat, ~osc[\crinkle, vals]] }
	};

	~mod[\nudge] = { |amount=0.15|
		{ |pat| ~m[pat,
			~osc[\stretch, [1.0, 1.0 - amount, 1.0 + amount, 1.0]]] }
	};

	// ═══════════════════════════════════════════════════════════
	// H. AUTO-CONTROL & GUI (unchanged)
	// ═══════════════════════════════════════════════════════════

	~makeControls = { |instrName|
		var defaults = ~defs[instrName];
		if (defaults.notNil) {
			"> Creating controls for %... <".format(instrName).postln;
			defaults.keysValuesChange { |key, val|
				if (val.isNumber) {
					var ndefName = (instrName ++ "_" ++ key).asSymbol;
					if (Ndef(ndefName).source.isNil) {
						Ndef(ndefName, val);
						("[@] Created Ndef(\\" ++ ndefName ++ ") -> " ++ val).postln;
					};
					Ndef(ndefName)
				} {
					val
				}
			};
		} { "[Err] Instrument def not found: %".format(instrName).warn };
	};

	~showGui = { |instrName|
		var prefix = instrName.asString ++ "_";
		var controlKeys = Ndef.all[s.name].keys.select({ |k|
			k.asString.beginsWith(prefix)
		}).asArray.sort;

		if (controlKeys.size > 0) {
			var rowHeight = 30;
			var rowGap = 4;
			var pad = 10;
			var winWidth = 620;
			var maxVisibleRows = 14;
			var contentHeight = controlKeys.size * (rowHeight + rowGap) + (pad * 2);
			var winHeight = contentHeight.min(maxVisibleRows * (rowHeight + rowGap) + (pad * 2));
			var win, scroll, canvas;
			var findSpec = { |name|
				var s1, s2, camel;
				s1 = name.asSymbol.asSpec;
				if (s1.notNil) { s1 } {
					// Try gr-prefixed: density → grDensity
					camel = name.asString;
					camel = ("gr" ++ camel[0].toUpper ++ camel[1..]).asSymbol;
					s2 = camel.asSpec;
					if (s2.notNil) { s2 } { ControlSpec(0, 1) };
				};
			};

			win = Window("Controls: " ++ instrName,
				Rect(100, 100, winWidth, winHeight)).front;
			win.view.background_(Color.grey(0.15));

			scroll = ScrollView(win, win.view.bounds)
				.resize_(5)
				.hasBorder_(false)
				.background_(Color.grey(0.15));

			canvas = CompositeView(scroll, Rect(0, 0, winWidth - 20, contentHeight));
			canvas.addFlowLayout(pad@pad, rowGap@rowGap);

			controlKeys.do { |key|
				var paramName = key.asString.replace(prefix, "");
				var ndef = Ndef(key);
				var curVal = ndef.source ? 0;
				var spec = findSpec.(paramName);
				var sliderWidth = winWidth - 40;

				EZSlider(canvas, sliderWidth @ rowHeight, paramName,
					spec, { |sl| ndef.source_(sl.value) },
					curVal, labelWidth: 110, numberWidth: 60);
			};
		} {
			"[Err] No controls found for '%'.".format(instrName).warn;
			"Did you run ~makeControls.(\\% )?".format(instrName).postln;
		};
	};

	~showControls = { |instrName|
		var pattern = "ProxyMixer(s, 8, options: [\name -> '" ++ instrName ++ "_'])";
		pattern.interpret;
	};

	// ═══════════════════════════════════════════════════════════
	// H2. GENERALIZED VISUALIZER
	// ═══════════════════════════════════════════════════════════
	//
	// SendReply contract (all synths):
	//   [srcX, srcY, mic1X, mic1Y, mic2X, mic2Y, colorID, synthType, env]
	//   synthType: 0=modalS(legacy), 1=foldS, 2=pluckS
	//   Legacy modalS sends 7 values → synthType defaults to 0
	//
	// Each synthType gets its own drawFunc branch.

	~showVis = {
		var win, view, oscFunc;
		var voices = Dictionary.new;

		var palette = [
			[Color.new(1, 0.5, 0),   Color.new(1, 0.0, 0.8)],
			[Color.cyan,             Color.blue],
			[Color.yellow,           Color.green(0.8, 0.5)],
			[Color.white,            Color.gray],
			[Color.red,              Color.new(0.5, 0, 0)]
		];

		win = Window("F2 Visualizer", Rect(720, 400, 500, 500)).front;
		win.view.background_(Color.black);

		oscFunc = OSCdef(\f2_vis_main, { |msg|
			var nodeID = msg[1];
			var data = msg[3..];
			voices[nodeID] = (data: data, time: Process.elapsedTime);
			{ win.refresh }.defer;
		}, '/f2_tel');

		win.onClose = { oscFunc.free; };

		view = UserView(win, win.view.bounds);
		view.clearOnRefresh = false;

		view.drawFunc = { |u|
			var w = u.bounds.width;
			var h = u.bounds.height;
			var now = Process.elapsedTime;

			Pen.fillColor = Color.black.alpha_(0.2);
			Pen.fillRect(u.bounds);

			Pen.strokeColor = Color.gray(0.2);
			12.do { |i|
				var pos = (i / 11) * w;
				Pen.line(0@pos, w@pos);
				Pen.line(pos@0, pos@h);
			};
			Pen.stroke;

			voices.keysDo { |id|
				var voice = voices[id];
				var d = voice.data;
				var lastTime = voice.time;

				if ((now - lastTime) > 0.15) {
					voices.removeAt(id);
				} {
					// ─── PARSE STANDARD TELEMETRY ───
					var synthType = if(d.size > 0) { d[0].asInteger } { 0 };
					var colID     = if(d.size > 1) { d[1].asInteger } { 0 };
					var env       = if(d.size > 2) { d[2].clip(0, 1) } { 0.5 };
					var ampVal    = if(d.size > 3) { d[3].clip(0, 1) } { 0.5 };
					var pan       = if(d.size > 4) { d[4] } { 0 };
					var posX      = if(d.size > 5) { d[5].clip(0, 1) } { 0.5 };
					var posY      = if(d.size > 6) { d[6].clip(0, 1) } { 0.5 };
					var p0        = if(d.size > 7) { d[7] } { 0 };
					var p1        = if(d.size > 8) { d[8] } { 0 };
					var p2        = if(d.size > 9) { d[9] } { 0 };
					var p3        = if(d.size > 10) { d[10] } { 0 };

					var colors = palette.wrapAt(colID);
					var c1 = colors[0]; var c2 = colors[1];

					var typeInfo = globalEnv.at(\synthTypes)[synthType];
					var cls = if(typeInfo.notNil) { typeInfo.class } { \positioned };

					case

					// ─── POSITIONED CLASS (foldS, pluckS, modalS) ───
					{ cls == \positioned } {
						var sx = posX * w; var sy = posY * h;
						// p0=micSpread, p1=crinkle/roughness, p2=roomSize, p3=modDepth
						var micSpread = p0.clip(0, 1);
						var crinkle = p1.clip(0, 1);
						var room = p2.clip(0, 1);
						var modD = p3.clip(0, 1);

						case
						// ─── TYPE 0: modalS — original dots + lines ───
						{ synthType == 0 } {
							var r = 3 + (env * 8);
							Pen.fillColor = Color.green(0.9, 0.6 + (env * 0.4));
							Pen.fillOval(Rect.aboutPoint(sx@sy, r, r));
							// aura for roomSize
							if (room > 0.1) {
								var aR = r + (room * 15);
								Pen.strokeColor = c1.alpha_(room * 0.3);
								Pen.width = 0.5 + (room * 2);
								Pen.strokeOval(Rect.aboutPoint(sx@sy, aR, aR));
							};
						}
						// ─── TYPE 1: foldS — bend arc + pulsing ───
						{ synthType == 1 } {
							var srcR = 3 + (env * 8);
							// arc from modDepth
							var arcR = 8 + (modD * 20);
							var arcAlpha = 0.2 + (env * 0.6);
							// crinkle → jaggedness
							var n = (crinkle * 8).ceil.asInteger.max(0);

							Pen.width = 1 + (env * 2);
							Pen.strokeColor = c1.blend(c2, 0.5).alpha_(arcAlpha);
							Pen.strokeOval(Rect.aboutPoint(sx@sy, arcR, arcR * (1 - (crinkle * 0.3))));

							// crinkle ticks
							if (n > 0) {
								n.do { |i|
									var angle = (i / n) * 2pi;
									var ix = sx + (cos(angle) * arcR * 0.8);
									var iy = sy + (sin(angle) * arcR * 0.8 * (1 - (crinkle * 0.3)));
									var ox = sx + (cos(angle) * (arcR + 3 + (crinkle * 4)));
									var oy = sy + (sin(angle) * (arcR + 3 + (crinkle * 4)));
									Pen.strokeColor = c2.alpha_(0.3 + (env * 0.4));
									Pen.width = 0.5 + (crinkle * 1.5);
									Pen.line(ix@iy, ox@oy); Pen.stroke;
								};
							};

							// room → halo
							if (room > 0.1) {
								Pen.fillColor = c1.alpha_(room * 0.08);
								Pen.fillOval(Rect.aboutPoint(sx@sy, arcR + (room * 15), arcR + (room * 15)));
							};

							// source dot
							Pen.fillColor = c1.alpha_(0.5 + (env * 0.5));
							Pen.fillOval(Rect.aboutPoint(sx@sy, srcR, srcR));
						}
						// ─── TYPE 2: pluckS — vibrating string ───
						{ synthType == 2 } {
							var vibAmt = env * 10;
							var stringLen = 15 + (micSpread * 30);
							var angle = modD * 2pi;
							var x1 = sx - (cos(angle) * stringLen * 0.5);
							var y1 = sy - (sin(angle) * stringLen * 0.5);
							var x2 = sx + (cos(angle) * stringLen * 0.5);
							var y2 = sy + (sin(angle) * stringLen * 0.5);
							var dx = x2 - x1; var dy = y2 - y1;
							var len = (dx.squared + dy.squared).sqrt.max(1);
							var nx = dy.neg / len; var ny = dx / len;

							Pen.width = 1 + (env * 1.5);
							Pen.strokeColor = c1.blend(c2, 0.5).alpha_(0.4 + (env * 0.5));
							Pen.moveTo(x1@y1);
							12.do { |i|
								var t = (i + 1) / 13;
								var px = x1 + (dx * t);
								var py = y1 + (dy * t);
								var disp = sin(t * pi) * sin(t * 6 * pi) * vibAmt;
								Pen.lineTo((px + (nx * disp))@(py + (ny * disp)));
							};
							Pen.lineTo(x2@y2);
							Pen.stroke;

							// bridge dots
							Pen.fillColor = c1.alpha_(0.8);
							Pen.rotate(0.785, x1, y1);
							Pen.fillRect(Rect.aboutPoint(x1@y1, 3, 3));
							Pen.rotate(-0.785, x1, y1);
							Pen.fillColor = c2.alpha_(0.8);
							Pen.rotate(0.785, x2, y2);
							Pen.fillRect(Rect.aboutPoint(x2@y2, 3, 3));
							Pen.rotate(-0.785, x2, y2);

							// pluck point
							Pen.fillColor = Color.green(0.9, 0.6 + (env * 0.4));
							Pen.fillOval(Rect.aboutPoint(sx@sy, 3 + (env * 3), 3 + (env * 3)));
						}
						// ─── POSITIONED FALLBACK ───
						{ true } {
							var r = 4 + (env * 10);
							Pen.fillColor = c1.alpha_(0.5 + (env * 0.5));
							Pen.fillOval(Rect.aboutPoint(sx@sy, r, r));
							if (room > 0.1) {
								Pen.strokeColor = c2.alpha_(room * 0.3);
								Pen.width = 0.5;
								Pen.strokeOval(Rect.aboutPoint(sx@sy, r + (room * 12), r + (room * 12)));
							};
						};
					}

					// ─── SIMPLE CLASS (kickS, snareS, hatS) ───
					{ cls == \simple } {
						var cx = posX * w; var cy = (1 - posY) * h;
						var sz = 3 + (env * ampVal * 20);
						var timbre = p0.clip(0, 1);

						case
						// kick — impact burst
						{ synthType == 3 or: { synthType == 9 } } {
							var r = 4 + (env * 25);
							var inner = 2 + (env * 8);
							Pen.width = 1.5 + (env * 3);
							Pen.strokeColor = c1.blend(c2, env).alpha_(env * 0.8);
							Pen.strokeOval(Rect.aboutPoint(cx@cy, r, r));
							Pen.fillColor = c1.alpha_(0.5 + (env * 0.5));
							Pen.fillOval(Rect.aboutPoint(cx@cy, inner, inner));
						}
						// snare — scatter burst
						{ synthType == 4 } {
							var n = 6; var r = 3 + (env * 15);
							n.do { |i|
								var angle = (i / n) * 2pi + (env * 1.5);
								var px = cx + (cos(angle) * r);
								var py = cy + (sin(angle) * r);
								var ssz = 1.5 + (env * 3 * (i.odd.asInteger));
								var col = if(i.even) { c1 } { c2 };
								Pen.fillColor = col.alpha_(0.4 + (env * 0.5));
								Pen.fillOval(Rect.aboutPoint(px@py, ssz, ssz));
							};
							Pen.fillColor = Color.white.alpha_(env);
							Pen.fillOval(Rect.aboutPoint(cx@cy, 2 + (env * 4), 2 + (env * 4)));
						}
						// hat — sparkle
						{ synthType == 5 or: { synthType == 8 } } {
							var ssz = 2 + (env * 6);
							Pen.width = 0.8 + (env * 1.5);
							Pen.strokeColor = c1.blend(c2, 0.5).alpha_(0.5 + (env * 0.5));
							Pen.line((cx-ssz)@cy, (cx+ssz)@cy); Pen.stroke;
							Pen.line(cx@(cy-ssz), cx@(cy+ssz)); Pen.stroke;
							Pen.strokeColor = c2.alpha_(env * 0.6);
							Pen.line((cx-ssz*0.7)@(cy-ssz*0.7), (cx+ssz*0.7)@(cy+ssz*0.7)); Pen.stroke;
							Pen.line((cx+ssz*0.7)@(cy-ssz*0.7), (cx-ssz*0.7)@(cy+ssz*0.7)); Pen.stroke;
							Pen.fillColor = Color.white.alpha_(env);
							Pen.fillOval(Rect.aboutPoint(cx@cy, 1.5, 1.5));
						}
						// simple fallback — square
						{ true } {
							Pen.fillColor = c1.alpha_(0.4 + (env * 0.6));
							Pen.fillRect(Rect.aboutPoint(cx@cy, sz, sz));
							Pen.strokeColor = c2;
							Pen.width = 1 + (timbre * 3);
							Pen.strokeRect(Rect.aboutPoint(cx@cy, sz, sz));
						};
					}

					// ─── TONAL CLASS (amS, clayPS) ───
					{ cls == \tonal } {
						var cx = posX * w; var cy = (1 - posY) * h;
						var r = 5 + (env * ampVal * 12);
						var brightness = p0.clip(0, 1);

						// carrier ring
						Pen.width = 1 + (env * 1.5);
						Pen.strokeColor = c1.alpha_(0.4 + (env * 0.5));
						Pen.strokeOval(Rect.aboutPoint(cx@cy, r, r));
						// modulator ring
						if (p1 > 0.1) {
							var mr = r * 0.6;
							Pen.strokeColor = c2.alpha_(0.3 + (env * 0.4));
							Pen.strokeOval(Rect.aboutPoint(cx@cy, mr, mr));
						};
						// core dot (brightness → saturation)
						Pen.fillColor = c1.blend(Color.white, brightness * 0.5).alpha_(0.5 + (env * 0.5));
						Pen.fillOval(Rect.aboutPoint(cx@cy, 3 + (env * 3), 3 + (env * 3)));
					}

					// ─── UNKNOWN CLASS FALLBACK ───
					{ true } {
						var cx = posX * w; var cy = (1 - posY) * h;
						var r = 4 + (env * 10);
						Pen.fillColor = c1.alpha_(0.5 + (env * 0.5));
						Pen.fillOval(Rect.aboutPoint(cx@cy, r, r));
					};
				};
			};
		};
		view.animate = true;
	};

	// Legacy alias
	~showModalVis = ~showVis;

	~pat = { |func|
		{ |argum|
			var stream = if(argum.isArray) { Pseq(argum, inf).asStream } { Pfunc({ argum }).asStream };
			{ func.value(stream) }
		}
	};

	// ═══════════════════════════════════════════════════════════
	// I. RACK BUILDER v2 — audio-rate bus routing
	// ═══════════════════════════════════════════════════════════
	//
	// FIX: Old code used Ndef.map(\in, Ndef(prev)) which maps a
	// kr control to an audio bus via /n_mapa. The control samples
	// audio at control rate (~689 Hz @ blockSize 64), then K2A
	// stretches each sample for 64 audio frames → bitcrush.
	//
	// New code uses .set(\in, bus.index) so effects receive the
	// bus INDEX as a plain number, then read audio-rate data with
	// In.ar(in, 2). No control-rate bottleneck, clean signal.
	//
	// Effects contract:
	//   { |in ...args|  var sig = In.ar(in, 2); ... }
	//   \in = bus index (integer). Always read with In.ar(in, 2).

	// ~makeRack: auto-forks so it works from ANY context (eval, boot, REPL)
	// Aliases: each effect gets both bare name AND band.name in fxTargets
	//   e.g. fxTargets[\chamber] AND fxTargets[\high.chamber]
	// If same effect on multiple bands, bare name → last one; use alias for specific.
	~makeRack = { |config, onDone|
		var env = currentEnvironment;
		{
			env.use {
			var r = ~rack;
			var d = ~dsl;
			var cross = config[\cross] ?? [200, 2500];
			var bandOutputs = Dictionary.new;
			var masterNdef, masterBus;

			r.dsl_ref = d;
			d.fxTargets = Dictionary.new; // clear stale targets
		d.fxAliasMap = Dictionary.new;

			"> Rebuilding rack...".postln;
			"[@] crossfreqs: %".format(cross).postln;

			Ndef.clear;
			if (r.fxGroup.notNil && r.fxGroup.isPlaying) { r.fxGroup.free };

			// Ordered groups
			r.fxGroup   = Group.tail(s.defaultGroup);
			r.srcGroup  = Group.head(r.fxGroup);
			r.bandGroup = Group.after(r.srcGroup);
			r.chainGroup = Group.after(r.bandGroup);
			r.masterGroup = Group.after(r.chainGroup);
			r.outGroup  = Group.after(r.masterGroup);
			s.sync;

			// ─── OUTPUT shell ───
			Ndef(\OUT).reshaping = \none;
			Ndef(\OUT).ar(2);
			Ndef(\OUT).group = r.outGroup;
			Ndef(\OUT)[0] = { DC.ar(0 ! 2) };
			Ndef(\OUT).play(0, 2);

			// ─── SOURCE ───
			Ndef(\src).reshaping = \none;
			Ndef(\src).ar(2);
			Ndef(\src).group = r.srcGroup;
			Ndef(\src)[0] = { In.ar(r.bus.main.index, 2) };
			"[@] src (bus %) -> Ndef(\\src)".format(r.bus.main.index).postln;

			// ─── CROSSOVER BANDS ───
			[\band_L, \band_M, \band_H].do { |key|
				Ndef(key).reshaping = \none;
				Ndef(key).ar(2);
				Ndef(key).group = r.bandGroup;
			};

			Ndef(\band_L)[0] = { LPF.ar(LPF.ar(Ndef(\src).ar, cross[0]), cross[0]) };
			"[@] Ndef(\\src) -> [lpf %Hz] -> Ndef(\\band_L)".format(cross[0]).postln;

			Ndef(\band_M)[0] = {
				var lowCut = HPF.ar(HPF.ar(Ndef(\src).ar, cross[0]), cross[0]);
				LPF.ar(LPF.ar(lowCut, cross[1]), cross[1]);
			};
			"[@] Ndef(\\src) -> [bpf %-%Hz] -> Ndef(\\band_M)".format(cross[0], cross[1]).postln;

			Ndef(\band_H)[0] = { HPF.ar(HPF.ar(Ndef(\src).ar, cross[1]), cross[1]) };
			"[@] Ndef(\\src) -> [hpf %Hz] -> Ndef(\\band_H)".format(cross[1]).postln;

			// ─── PER-BAND CHAINS ───
			[\low, \mid, \high].do { |band|
				var list = config[band];
				var sourceKey = ("band_" ++ band.asString.first.toUpper).asSymbol;
				var currentBus = Ndef(sourceKey).bus.index;

				if (list.notNil and: { list.size > 0 }) {
					"[@] processing band: %...".format(band).postln;

					list.do { |modName, i|
						var ndefKey = (i.asString ++ "_" ++ band ++ "_" ++ modName).asSymbol;
						var alias  = (band.asString ++ "." ++ modName.asString).asSymbol;
						var func = r.repo[modName];

						if (func.notNil) {
							Ndef(ndefKey).reshaping = \none;
							Ndef(ndefKey).ar(2);
							Ndef(ndefKey).group = r.chainGroup;
							Ndef(ndefKey)[0] = func;
							Ndef(ndefKey).set(\in, currentBus);
							Ndef(ndefKey).set(\tel_bus, r.bus.tel.index);
							"[@]   bus % -> [%] -> % (bus %) alias: %".format(
								currentBus, modName, ndefKey, Ndef(ndefKey).bus.index, alias).postln;
							d.fxTargets[modName] = ndefKey;  // bare (last wins)
							d.fxTargets[alias]   = ndefKey;  // band-specific
							d.fxAliasMap[modName] = modName;
							d.fxAliasMap[alias]   = modName;
							currentBus = Ndef(ndefKey).bus.index;
						} {
							"[@]   [error] effect '%' not found in repo".format(modName).warn;
						};
					};
				};
				bandOutputs[band] = currentBus;
			};

			// ─── MASTER: sum three bands ───
			Ndef(\master).reshaping = \none;
			Ndef(\master).ar(2);
			Ndef(\master).group = r.masterGroup;
			Ndef(\master)[0] = {
				In.ar(bandOutputs[\low], 2) +
				In.ar(bandOutputs[\mid], 2) +
				In.ar(bandOutputs[\high], 2)
			};
			masterBus = Ndef(\master).bus.index;

			"[@] sum(bus %, %, %) -> Ndef(\\master) (bus %)".format(
				bandOutputs[\low], bandOutputs[\mid], bandOutputs[\high], masterBus).postln;

			// ─── MASTER CHAIN ───
			if (config[\master].notNil and: { config[\master].size > 0 }) {
				"[@] processing master chain...".postln;
				config[\master].asArray.do { |modName, i|
					var ndefKey = (i.asString ++ "_master_" ++ modName).asSymbol;
					var alias   = ("master." ++ modName.asString).asSymbol;
					var func = r.repo[modName];

					if (func.notNil) {
						Ndef(ndefKey).reshaping = \none;
						Ndef(ndefKey).ar(2);
						Ndef(ndefKey).group = r.masterGroup;
						Ndef(ndefKey)[0] = func;
						Ndef(ndefKey).set(\in, masterBus);
						Ndef(ndefKey).set(\tel_bus, r.bus.tel.index);
						"[@]   bus % -> [%] -> % (bus %) alias: %".format(
							masterBus, modName, ndefKey, Ndef(ndefKey).bus.index, alias).postln;
						d.fxTargets[modName] = ndefKey;
						d.fxTargets[alias]   = ndefKey;
						d.fxAliasMap[modName] = modName;
						d.fxAliasMap[alias]   = modName;
						masterBus = Ndef(ndefKey).bus.index;
					}
				};
			};

			// ─── FINAL OUTPUT ───
			Ndef(\OUT).fadeTime = 0.1;
			Ndef(\OUT)[0] = {
				var sig = In.ar(masterBus, 2);
				sig = LeakDC.ar(sig);
				sig = Sanitize.ar(sig);
				Limiter.ar(sig, 0.95);
			};

			"[@] bus % -> [limit/sanitize] -> Ndef(\\OUT)".format(masterBus).postln;
			"> Rack is ready.".postln;

			// §fx-base: Ndef.clear above wiped every engine fx mapping — re-map all
			// registered (fx, param) pairs onto their mb buses against the FRESH
			// fxTargets, and refresh their bases from the rebuilt effects.
			if (~f2FxReapply.notNil) { ~f2FxReapply.value };

			// callback if provided
			if (onDone.notNil) { onDone.value };
			}; // env.use
		}.fork;
	};

	// ═══════════════════════════════════════════════════════════
	// J. LOADERS (unchanged)
	// ═══════════════════════════════════════════════════════════

	~loadFolder = { |subDir, type|
		var p = rootPath +/+ subDir;
		"> Loading % from: %".format(subDir, p).postln;
		// §fx-guard skipping the catalogue silently hid an empty fx repo (dead buses) — so it shouts
		if (File.exists(p).not) { "✗ ~loadFolder: % NOT FOUND — skipped (bad root?)".format(p).postln };
		if (File.exists(p)) {
			PathName(p).entries.do { |f|
				if (f.extension == "scd") {
					try {
						if (type == \fx) {
							var func = f.fullPath.load;
							if (func.isKindOf(Function)) {
								if (func.def.argNames.includes(\in)) {
									~rack.repo[f.fileNameWithoutExtension.asSymbol] = func;
									("[Fx]  " ++ f.fileNameWithoutExtension ++ ".").postln;
								} { ("[Err] " ++ f.fileName ++ " ignored.").postln; };
							}
						} { f.fullPath.load; ("[Def] " ++ f.fileNameWithoutExtension ++ ".").postln; }
					} { |e| ("[Err] " ++ f.fileName ++ ".").postln; };
				}
			}
		}
	};

	~loadModalSamples = {
		var p = rootPath +/+ "ModalSamples";
		"> Loading ModalSamples from: %".format(p).postln;
		if (File.exists(p)) {
			PathName(p).entries.do { |f|
				if (f.extension == "json") {
					try {
						var rawData = File.readAllString(f.fullPath).interpret;
						var gridSize = 12; var numModes = 32; var numPoints = gridSize * gridSize;
						var freqs = FloatArray.newClear(numPoints * numModes);
						var amps = FloatArray.newClear(numPoints * numModes);
						var decays = FloatArray.newClear(numPoints * numModes);
						rawData.do({ |val, i|
							var pointIdx = (i / 3 / numModes).floor; var modeIdx = ((i / 3) % numModes).floor; var type = i % 3; var tIdx = (pointIdx * numModes) + modeIdx;
							case {type==0}{freqs[tIdx]=val} {type==1}{amps[tIdx]=val} {type==2}{decays[tIdx]=val};
						});
						~modalBuffers[f.fileNameWithoutExtension.asSymbol] = (
							f: Buffer.loadCollection(s, freqs, numModes), a: Buffer.loadCollection(s, amps, numModes), d: Buffer.loadCollection(s, decays, numModes)
						);
						("[ModS] " ++ f.fileNameWithoutExtension ++ ".").postln;
					} { |e| ("[Err] Failed to load modal sample " ++ f.fileName ++ ": " ++ e).postln; };
				}
			}
		};
		s.sync;
	};

	// §smp SAMPLER.md §6: a samplerU card names its own file in the RESOURCE opt
	// `sample` (decision 4 — two Sampler cards in one strip must be able to hold
	// different files, which a preset-wide buf cannot express). The opt changes
	// no graph, so it never reaches the variant name: \f2voice resolves it here
	// at spawn. An empty or unknown name falls back to the preset-level buffer
	// (Preset.sample → ev[\buf]). The four analysis buffers of §6 (sliceBuf /
	// onsetBuf / pitchBuf / fftBuf) are resolved beside it, in the chain loop
	// below, through ~f2SmpRes — each -1 until its own pass has landed.
	~f2SmpBuf = { |opts|
		var nm = opts !? { |o| o[\sample] };
		var d = topEnvironment[\samples];
		var b;
		if (nm.notNil and: { nm.asString.isEmpty.not } and: { d.notNil }) {
			b = d[nm.asSymbol];
			if (b.isNil and: { topEnvironment[\f2UnitWarnOnce].notNil }) {
				topEnvironment[\f2UnitWarnOnce].(("smp_nosample_" ++ nm).asSymbol,
					"⚠ [f2 smp] sample % is not loaded — the card falls back to the preset sample".format(nm));
			};
		};
		b
	};

	~loadSamples = {
	var p = rootPath +/+ "Samples";
	"> Loading Samples from: %".format(p).postln;
	~samples = ~samples ?? IdentityDictionary.new;
	if (File.exists(p)) {
		PathName(p).deepFiles.do { |f|
			if (#["wav","aif","aiff","flac","ogg"].includesEqual(f.extension.toLower)) {
				try {
					var rel = f.fullPath.replace(p ++ "/", "");
					var key = rel.splitext.first.replace("/", "_").asSymbol;
					~samples[key] = Buffer.readChannel(s, f.fullPath, channels: [0]);
					("[Smp] " ++ key ++ ".").postln;
				} { |e| ("[Err] Failed to load sample " ++ f.fileName ++ ": " ++ e).postln; };
			}
		}
	};
	// §smp the analysis artefacts of §6 belong to the sample buffers that were
	// just replaced: their slice tables are dropped so the next spawn re-resolves
	// (and re-analyses) against the new files.
	topEnvironment[\f2SmpForget] !? { |f| f.() };
	// §conv-ir and the prepared IR spectra, for the same reason: they were read
	// from the files these buffers just replaced.
	topEnvironment[\f2ConvIrForget] !? { |f| f.() };
	// §curve the rendered drawings: their bufnums were handed out by an allocator
	// whose buffers have just been replaced under them, so they are dropped and
	// the next spawn re-renders (the twin of the two above, called beside them).
	topEnvironment[\f2CurveForget] !? { |f| f.() };
	s.sync;
};

	~loadFolder.("Synths", \def);
	~loadFolder.("Effects", \fx);
	if(globalEnv.at(\loadSamples).notNil) { ~loadSamples.() };
	~loadModalSamples.();
	~loadSamples.();

	~exportContext = {
		var ctx, toJSON, sysKeys, knownSpecs;

		toJSON = { |obj|
			if (obj.isNil) { "null" } {
				// §smp an opt schema carries `res: true` (SAMPLER.md §3) — a Boolean
				// must land in the JSON as one, not as its class name
				if (obj.isKindOf(Boolean)) { obj.asString } {
				if (obj.isNumber) { obj.asString } {
					if (obj.isKindOf(Symbol)) {
						"\"" ++ obj.asString ++ "\""
					} {
						if (obj.isKindOf(String)) {
							// Escape backslashes first, then quotes
							var s = obj.asString;
							s = s.replace("\\", "\\\\");
							s = s.replace("\"", "\\\"");
							"\"" ++ s ++ "\""
						} {
							if (obj.isKindOf(Array)) {
								"[" ++ obj.collect({ |item| toJSON.(item) }).join(", ") ++ "]"
							} {
								if (obj.isKindOf(Dictionary) or: { obj.isKindOf(Event) }) {
									"{" ++ obj.keys.asArray.sort.collect({ |k|
										"\"" ++ k.asString ++ "\": " ++ toJSON.(obj[k])
									}).join(", ") ++ "}"
								} {
									"\"" ++ obj.class.name ++ "\""
								}
							}
						}
					}
				}
				}
			}
		};

		sysKeys = IdentitySet.new;
		[\instrument, \selfFree, \scale, \type, \args,
			\group, \addAction, \out, \tel_bus, \in, \finish, \callback,
			\sustain, \sendGate, \isRest, \delta, \dur, \legato,
			\dsl_type, \list, \voice, \ghost, \dens, \palette, \mod,
			\doneAction, \gate, \id, \server, \msgFunc, \hasGate,
			\parent, \proto, \know].do { |k| sysKeys.add(k) };

		ctx = (
			defs: ~defs.keys.asArray.sort,
			palettes: ~pal.keys.asArray.select({ |k| k.isKindOf(Symbol) }).sort,
			fxTargets: ~dsl.fxTargets.keys.asArray.sort,
			fxTargetMap: {
				var m = Dictionary.new;
				~dsl.fxTargets.keysValuesDo { |k, v| m[k] = v.asString };
				m
			}.value,
			fxAliasMap: {
				var m = Dictionary.new;
				if (~dsl.fxAliasMap.notNil) {
					~dsl.fxAliasMap.keysValuesDo { |k, v| m[k] = v.asString };
				};
				m
			}.value,
			mods: (),
			fxArgs: (),
			specs: (),
			synthParams: ()
		);

		// 1. Mods
		ctx[\modArgOrder] = ();
		~mod.keysValuesDo { |modName, modFunc|
			try {
				var argNames = modFunc.def.argNames;
				var defaults = modFunc.def.prototypeFrame;
				var modInfo = ();
				if (argNames.notNil) {
					argNames.do { |argName, i|
						var val = defaults[i];
						if (val.isKindOf(Symbol)) {
							// Store as string with \ prefix — toJSON escapes → GUI gets \hex
							modInfo[argName] = "\\" ++ val.asString
						} {
							if (val.isKindOf(Array)) {
								modInfo[argName] = "[" ++ val.collect(_.asString).join(",") ++ "]"
							} {
								modInfo[argName] = if (val.isNil) { 0 } { val }
							}
						}
					}
				};
				ctx[\mods][modName] = modInfo;
				if (argNames.notNil) {
					ctx[\modArgOrder][modName] = argNames;
				};
			} { |err|
				"[ctx warn] mod %: %".format(modName, err.errorString).postln
			};
		};


		// 5. SynthDef descriptors from SynthDescLib (args + defaults)
		ctx[\synthDescs] = ();
		SynthDescLib.global.synthDescs.keysValuesDo { |name, desc|
			// §cards SynthDef VARIANTS (`unit__k_v…`, built by ~f2UnitDef) are not
			// instruments — skipped; the base def carries the unit's knobs.
			if (name.asString.contains("__").not) {
				try {
					var params = ();
					desc.controls.do { |ctrl|
						if (sysKeys.includes(ctrl.name).not) {
							params[ctrl.name] = ctrl.defaultValue ?? 0;
						}
					};
					if (params.size > 0) { ctx[\synthDescs][name] = params };
				} { }
			};
		};
		// 5b. §poly unit schema (f2units ~f2UnitOpts / ~f2UnitSpecs, POLYSYNTH.md
		// §3): per unit the structural menus (values / def / label — an opt
		// selects the SynthDef variant) and the knob ranges (min / max / warp /
		// unit / label / sel). Plain dictionaries: toJSON above renders Events
		// and IdentityDictionaries as objects, #[…] literals as arrays and
		// symbols as strings. Empty objects until f2units has loaded.
		ctx[\unitOpts] = topEnvironment[\f2UnitOpts] ? ();
		ctx[\unitSpecs] = topEnvironment[\f2UnitSpecs] ? ();
		// 5c. §cut units CUT OUT of the engine (~f2UnitsCut, units v49: amU / envcaU / onsetU) → what
		// to rebuild the card as. This is NOT legacy: a legacy unit stays in the library, reaches
		// SynthDesc and is merely hidden from the menu; a cut one is nowhere at all, so an old save's
		// card finds not one control and is drawn EMPTY — it looks like a bypass and will never make
		// a sound. The engine prints ~f2UnitGoneMsg to the post window, but a musician is not looking
		// there: with this line the card says the same thing itself.
		ctx[\unitsCut] = topEnvironment[\f2UnitsCut] ? ();
		// 5d. §sc-deps WHAT THIS ENGINE CAN ACTUALLY BUILD. The filter models are a static
		// table on the front (UNIT_BUILT), and until now that was safe because every unit
		// built every model. It is not safe any more: four of the eleven play `SVF` from
		// sc3-plugins, and on a machine without the pack ~f2FltBuilt drops them — so the card
		// would go on offering a model the engine answers with its default. These two lines
		// are the engine telling the card what it has: the per-unit built list, and which
		// capabilities are missing (`#[\pv, \svf]`, empty on a full install). The card falls
		// back to its static table when the key is absent, so an older engine changes nothing.
		ctx[\fltBuilt] = topEnvironment[\f2FltBuilt] ? ();
		ctx[\extMissing] = topEnvironment[\f2ExtMissing] ? #[];

		// 6. Defs detail — alias → { instrument, numeric + symbol params }
		ctx[\defsDetail] = ();
		~defs.keysValuesDo { |k, v|
			var detail = ();
			detail[\instrument] = v[\instrument].asString;
			v.keysValuesDo { |pk, pv|
				if (sysKeys.includes(pk).not) {
					if (pv.isNumber) { detail[pk] = pv }
					{ if (pv.isKindOf(Buffer)) { detail[pk] = pv.bufnum }
					{ if (pv.isKindOf(Symbol)) { detail[pk] = pv.asString } } }
				}
			};
			ctx[\defsDetail][k] = detail;
		};

		// 6b. Sample names — from ~samples dictionary
		ctx[\sampleNames] = ~samples.keys.asArray.sort.collect(_.asString);

		// Sample name → bufnum mapping for UI
		ctx[\sampleBufs] = ();
		~samples.keysValuesDo { |k, v|
			if (v.isKindOf(Buffer)) { ctx[\sampleBufs][k.asString] = v.bufnum };
		};

		// 6d. §smp the slicing analysis of the samples the offline pass has finished
		// (SAMPLER.md §6). It rides in the CONTEXT, per sample, exactly as sampleBufs
		// does: it describes a FILE, not a voice — it changes only when a sample or an
		// analysis opt changes, never per note — so a live telemetry channel would
		// carry the same numbers over and over for nothing. The payload itself is
		// built by ~f2SmpAnalysisCtx (f2units, beside the pass that produces it);
		// f2units not loaded ⇒ an empty object, exactly as before this stage.
		ctx[\sampleAnalysis] = (topEnvironment[\f2SmpAnalysisCtx] !? { |f|
			try { f.value(~samples) } { |e|
				"[ctx warn] sampleAnalysis: %".format(e.errorString).postln; nil
			}
		}) ? ();

		// 6c. Modal buffer names
		if (~modalBuffers.notNil) {
			ctx[\modalNames] = ~modalBuffers.keys.asArray.sort.collect(_.asString);
		};

		// 2. FX args
		if (~rack.notNil and: { ~rack.repo.notNil }) {
			~rack.repo.keysValuesDo { |fxName, fxFunc|
				try {
					var argNames = fxFunc.def.argNames;
					var defaults = fxFunc.def.prototypeFrame;
					var fxInfo = ();
					if (argNames.notNil) {
						argNames.do { |argName, i|
							if (sysKeys.includes(argName).not) {
								var val = defaults[i];
								if (val.notNil and: { val.isNumber }) { fxInfo[argName] = val }
							}
						}
					};
					if (fxInfo.size > 0) { ctx[\fxArgs][fxName] = fxInfo };
				} { |err|
					"[ctx warn] fx %: %".format(fxName, err.errorString).postln
				};
			};
		};

		// 3. Specs — hardcoded known ranges (safe, no Spec.specs iteration)
		knownSpecs = ();
		knownSpecs[\amp] = (min:0, max:1, warp:"lin");
		knownSpecs[\pan] = (min: -1, max:1, warp:"lin");
		knownSpecs[\drive] = (min:1, max:100, warp:"exp");
		knownSpecs[\mix] = (min:0, max:1, warp:"lin");
		knownSpecs[\crinkle] = (min:0, max:1, warp:"lin");
		knownSpecs[\roomSize] = (min:0, max:1, warp:"lin");
		knownSpecs[\clickVol] = (min:0, max:1, warp:"lin");
		knownSpecs[\roughness] = (min:0, max:1, warp:"lin");
		knownSpecs[\decayScale] = (min:0.1, max:10, warp:"exp");
		knownSpecs[\srcX] = (min:0, max:1, warp:"lin");
		knownSpecs[\srcY] = (min:0, max:1, warp:"lin");
		knownSpecs[\mic1X] = (min:0, max:1, warp:"lin");
		knownSpecs[\mic1Y] = (min:0, max:1, warp:"lin");
		knownSpecs[\mic2X] = (min:0, max:1, warp:"lin");
		knownSpecs[\mic2Y] = (min:0, max:1, warp:"lin");
		knownSpecs[\freq] = (min:20, max:20000, warp:"exp");
		knownSpecs[\rate] = (min:0.1, max:10, warp:"exp");
		knownSpecs[\stretch] = (min:0.1, max:4, warp:"exp");
		knownSpecs[\atk] = (min:0.001, max:4, warp:"exp");
		knownSpecs[\dec] = (min:0.01, max:4, warp:"exp");
		knownSpecs[\sus] = (min:0, max:1, warp:"lin");
		knownSpecs[\rel] = (min:0.01, max:8, warp:"exp");
		knownSpecs[\rattle] = (min:0, max:1, warp:"lin");
		knownSpecs[\stiffness] = (min:0, max:1, warp:"lin");
		knownSpecs[\posX] = (min:0, max:1, warp:"lin");
		knownSpecs[\posZ] = (min:0, max:1, warp:"lin");
		knownSpecs[\reflect] = (min:0, max:1, warp:"lin");
		knownSpecs[\brightness] = (min:0, max:1, warp:"lin");
		knownSpecs[\tail] = (min:0, max:1, warp:"lin");
		knownSpecs[\density] = (min:0, max:1, warp:"lin");
		knownSpecs[\shimmer] = (min:0, max:1, warp:"lin");
		knownSpecs[\feedback] = (min:0, max:1, warp:"lin");
		knownSpecs[\time] = (min:0.01, max:4, warp:"exp");
		knownSpecs[\damp] = (min:0, max:1, warp:"lin");
		knownSpecs[\depth] = (min:0, max:1, warp:"lin");
		// §loop-cond the conditioner on unit port inputs (f2units): loop gain / damping / saturation
		knownSpecs[\inGain] = (min:0, max:2, warp:"lin");
		knownSpecs[\inDamp] = (min:0, max:1, warp:"lin");
		knownSpecs[\inSat] = (min:0, max:1, warp:"lin");
		// §glitch-units modalU/pluckU/noiseU/combU/foldU
		knownSpecs[\inharm] = (min:0, max:1, warp:"lin");
		knownSpecs[\bright] = (min:0, max:1, warp:"lin");
		knownSpecs[\decMul] = (min:0.02, max:4, warp:"exp");
		knownSpecs[\click] = (min:0, max:2, warp:"lin");
		knownSpecs[\noiseAmt] = (min:0, max:1, warp:"lin");
		knownSpecs[\fb] = (min:0, max:1, warp:"lin");
		knownSpecs[\plDamp] = (min:0, max:1, warp:"lin");
		knownSpecs[\burst] = (min:0, max:2, warp:"lin");
		knownSpecs[\burstFreq] = (min:200, max:12000, warp:"exp");
		knownSpecs[\res] = (min:0, max:1, warp:"lin");
		knownSpecs[\pEnv] = (min:0, max:1, warp:"lin");
		knownSpecs[\pDec] = (min:0.005, max:0.5, warp:"exp");
		knownSpecs[\crackle] = (min:0, max:1, warp:"lin");
		knownSpecs[\combFreq] = (min:18, max:2000, warp:"exp");
		knownSpecs[\fDrive] = (min:0, max:1, warp:"lin");
		knownSpecs[\foldAmt] = (min:0, max:1, warp:"lin");
		knownSpecs[\crush] = (min:0, max:1, warp:"lin");
		// §mod-suite shiftU/shimU/vocU
		knownSpecs[\shift] = (min: -1000, max:1000, warp:"lin");
		knownSpecs[\pRatio] = (min:0.25, max:4, warp:"exp");
		knownSpecs[\pDisp] = (min:0, max:0.5, warp:"lin");
		knownSpecs[\sens] = (min:0, max:2, warp:"lin");
		knownSpecs[\hard] = (min:0, max:1, warp:"lin");
		knownSpecs[\vAtk] = (min:0.001, max:0.1, warp:"exp");
		knownSpecs[\vRel] = (min:0.01, max:1, warp:"exp");
		// §pad-drum subU/padU
		knownSpecs[\dtn] = (min:0, max:1, warp:"lin");
		knownSpecs[\wide] = (min:0, max:1, warp:"lin");
		knownSpecs[\subAmt] = (min:0, max:1, warp:"lin");
		knownSpecs[\move] = (min:0, max:1, warp:"lin");
		// §spec-suite harmU/specU/tranU
		knownSpecs[\nHarm] = (min:1, max:12, warp:"lin");
		knownSpecs[\slope] = (min:0, max:1, warp:"lin");
		knownSpecs[\odd] = (min:0, max:1, warp:"lin");
		knownSpecs[\shimmer] = (min:0, max:1, warp:"lin");
		knownSpecs[\smear] = (min:0, max:1, warp:"lin");
		knownSpecs[\bShift] = (min: -64, max:64, warp:"lin");
		knownSpecs[\freeze] = (min:0, max:1, warp:"lin");
		knownSpecs[\scomb] = (min:0, max:1, warp:"lin");
		knownSpecs[\trans] = (min:0, max:2, warp:"lin");
		knownSpecs[\body] = (min:0, max:2, warp:"lin");
		knownSpecs[\snap] = (min:0, max:1, warp:"lin");
		// §conv-suite convU/xspecU/scatU (onsetU was cut in units v49; bias/boost
		// went with amU — nothing left in the engine declares them)
		knownSpecs[\kSpan] = (min:0.1, max:1, warp:"lin");
		knownSpecs[\kGain] = (min:0.1, max:8, warp:"exp");
		knownSpecs[\preDly] = (min:0, max:0.2, warp:"lin");
		knownSpecs[\xmode] = (min:0, max:2, warp:"lin");
		knownSpecs[\nGrain] = (min:1, max:16, warp:"lin");
		knownSpecs[\scat] = (min:0.01, max:0.5, warp:"exp");
		knownSpecs[\gDur] = (min:0.01, max:0.5, warp:"exp");
		// §stut-look slides stutU's capture window back into the past (seconds)
		knownSpecs[\look] = (min:0, max:1.3, warp:"lin");
		// §tape grainU: 0 = grains, 1 = grPos-as-read-head
		knownSpecs[\mode] = (min:0, max:1, warp:"lin");
		// §flat-grain grainU: 0 = hann grains, 1 = flat COLA window (uniform
		// loudness at duty 1 — grSize = 1/grRate — the grain-slicer setting)
		knownSpecs[\grEnv] = (min:0, max:1, warp:"lin");
		// §chip chipU: tracker 8-bit oscillator (Jxy frame-rate arpeggio)
		knownSpecs[\wave] = (min:0, max:3, warp:"lin");
		knownSpecs[\duty] = (min:0.05, max:0.95, warp:"lin");
		knownSpecs[\arp1] = (min: -24, max:24, warp:"lin");
		knownSpecs[\arp2] = (min: -24, max:24, warp:"lin");
		knownSpecs[\arp3] = (min: -24, max:24, warp:"lin");
		knownSpecs[\arpN] = (min:0, max:3, warp:"lin");
		knownSpecs[\arpRate] = (min:1, max:200, warp:"exp");
		knownSpecs[\bits] = (min:1, max:16, warp:"lin");
		knownSpecs[\srate] = (min:0, max:22050, warp:"lin");
		knownSpecs[\cut] = (min:80, max:18000, warp:"exp");
		knownSpecs[\rq] = (min:0.05, max:1, warp:"lin");
		knownSpecs[\vib] = (min:0, max:1, warp:"lin");
		knownSpecs[\vibRate] = (min:0.5, max:16, warp:"exp");
		// §unit-eq the three-band EQ on the output of non-oscillator units
		knownSpecs[\eqLo] = (min:0, max:4, warp:"lin");
		knownSpecs[\eqMid] = (min:0, max:4, warp:"lin");
		knownSpecs[\eqHi] = (min:0, max:4, warp:"lin");
		knownSpecs[\eqLoF] = (min:30, max:2000, warp:"exp");
		knownSpecs[\eqHiF] = (min:500, max:16000, warp:"exp");
		knownSpecs[\modFreq] = (min:0.1, max:20, warp:"exp");
		knownSpecs[\threshold] = (min:0, max:1, warp:"lin");
		knownSpecs[\attack] = (min:0.001, max:0.5, warp:"exp");
		knownSpecs[\release] = (min:0.01, max:2, warp:"exp");
		knownSpecs[\amount] = (min:0, max:1, warp:"lin");
		knownSpecs[\colorID] = (min:0, max:10, warp:"lin");
		ctx[\specs] = knownSpecs;

		// 4. Synth params
		~defs.keysValuesDo { |k, v|
			v.keys.do { |paramKey|
				if (sysKeys.includes(paramKey).not) {
					ctx[\synthParams][paramKey] = true
				}
			}
		};
		ctx[\synthParams] = ctx[\synthParams].keys.asArray.sort;


		// Extended context exports
		ctx[\synthTypes] = ();
		~synthTypes.keysValuesDo { |id, info|
			ctx[\synthTypes][id] = (
				name: info[\name].asString,
				class: info[\class].asString,
				params: info[\params].collect(_.asString)
			);
		};
		ctx[\paramsBySynth] = ();
		~defs.keysValuesDo { |defName, defVal|
			var instr = defVal[\instrument].asString;
			if (ctx[\paramsBySynth][instr].isNil) {
				ctx[\paramsBySynth][instr] = (defs: [], params: ());
			};
			ctx[\paramsBySynth][instr][\defs] = ctx[\paramsBySynth][instr][\defs].add(defName.asString);
			defVal.keysValuesDo { |k, v|
				if (sysKeys.includes(k).not and: { v.isNumber }) {
					ctx[\paramsBySynth][instr][\params][k] = v;
				};
			};
		};
		ctx[\busNames] = ~rack.bus.keys.asArray.sort.collect(_.asString);

		File.use(~f2ContextPath ?? (thisProcess.nowExecutingPath.dirname +/+ "f2_context_full.json"), "w", { |f|
			f.write(toJSON.(ctx));
		});
		"[f2] context exported.".postln;
	};

	// ═══════════════════════════════════════════════════════════
	// G. GROW — Seed-based generative phrase engine
	// ═══════════════════════════════════════════════════════════
	//
	// Companion to grow-gui. Generates multi-cycle phrases from
	// painted seed grids with per-step locks and form transforms.
	//
	// Usage (generated by grow-gui):
	//
	//   var seed = [\K, (v:\S, d:2, p:(amp: 0.8)), \x, \H];
	//   ~play.(\gen, ~phrase.(
	//       seed,
	//       (K: \xk, S: \xs, H: \xh),
	//       (K: \xk_g, S: \xs_g, H: \xh_g),
	//       8, ~form[\arc], nil,
	//       (K: [~ramp[\amp, 0.30, 1.00, \exp]])
	//   ), 32);
	//
	// Depth semantics:
	//   0 = rest, 1 = hit, 2 = dup (×2), 3 = trip (×3), 4 = nest (×4 + ghost)
	// ═══════════════════════════════════════════════════════════

	// ─── G1. FORM DICTIONARY ────────────────────────────────
	~form = ();
	~form[\arc]     = [\id, \deepen, \deepen, \id, \id, \strip, \strip, \thin];
	~form[\loop]    = [\id, \rot, \id, \rotL];
	~form[\build]   = [\strip, \strip, \id, \deepen];
	~form[\fall]    = [\deepen, \id, \strip, \thin];
	~form[\dialog]  = [\id, \swap, \id, \swap];
	~form[\spiral]  = [\rot, \rot, \rot, \rot, \rot, \rot, \rot, \rot];
	~form[\breathe] = [\strip, \id, \deepen, \id, \strip, \thin, \thicken, \deepen];
	~form[\spot]    = [\accent, \accent, \accent, \accent, \accent, \accent, \accent, \accent];
	// New forms using extended transforms
	~form[\decay]   = [\id, \erode, \erode, \erode, \bloom, \id, \erode, \erode];
	~form[\grow]    = [\bloom, \id, \bloom, \deepen, \id, \erode, \id, \bloom];
	~form[\tide]    = [\cascade, \cascade, \mirror, \cascade, \cascade, \mirror, \erode, \bloom];
	~form[\cells]   = [\life, \life, \life, \life, \bloom, \life, \life, \life];
	~form[\fog]     = [\diffuse, \diffuse, \id, \diffuse, \diffuse, \deepen, \diffuse, \thin];
	~form[\canon]   = [\phase, \id, \phase, \id, \phase, \id, \phase, \id];
	~form[\mitosis] = [\id, \split, \id, \split, \fuse, \id, \split, \erode];
	~form[\echo]    = [\call_response, \id, \call_response, \deepen, \call_response, \strip, \call_response, \id];
	~form[\fracGen] = [\fractal, \id, \erode, \fractal, \id, \strip, \bloom, \id];
	~form[\gravity] = [\gravity, \id, \bloom, \gravity, \id, \cascade, \gravity, \thin];

	// ─── G2. SEED CELL NORMALIZER ───────────────────────────
	~normCell = { |cell|
		if (cell.isNil) { (v: \x, d: 0) }
		{
			if (cell.isKindOf(Symbol)) {
				if (cell == \x) { (v: \x, d: 0) }
				{ (v: cell, d: 1) }
			} {
				if (cell.isKindOf(Event) and: { cell[\v].notNil }) {
					if (cell[\d].isNil) { cell.put(\d, 1) };
					cell
				} {
					(v: \x, d: 0)
				}
			}
		}
	};

	// ─── G3. SEED TRANSFORMS ────────────────────────────────
	~seedTransform = { |seed, transform, gen|
		var result;
		gen = gen ? 0;

		result = case

		{ transform == \id } { seed }

		{ transform == \rot } {
			var a = seed.collect(_.copy);
			if (a.size > 1) { a.rotate(1) } { a }
		}

		{ transform == \rotL } {
			var a = seed.collect(_.copy);
			if (a.size > 1) { a.rotate(-1) } { a }
		}

		{ transform == \mir } {
			seed.collect(_.copy).reverse
		}

		{ transform == \strip } {
			seed.collect { |cell|
				var c = cell.copy;
				if (c[\d].notNil and: { c[\d] > 0 }) {
					if (c[\d] <= 1) {
						(v: \x, d: 0)
					} {
						c.put(\d, c[\d] - 1)
					}
				} { c }
			}
		}

		{ transform == \deepen } {
			seed.collect { |cell|
				var c = cell.copy;
				if (c[\v] != \x and: { c[\d].notNil and: { c[\d] > 0 } }) {
					c.put(\d, (c[\d] + 1).min(4))
				} { c }
			}
		}

		{ transform == \thin } {
			seed.collect { |cell, i|
				if (i % 2 == 0) { cell.copy } { (v: \x, d: 0) }
			}
		}

		{ transform == \thicken } {
			seed.collect { |cell, i|
				if (cell[\v] == \x or: { cell[\d] == 0 }) {
					var prev = seed.wrapAt(i - 1);
					if (prev[\v] != \x and: { prev[\d].notNil and: { prev[\d] > 0 } }) {
						(v: prev[\v], d: 1)
					} {
						(v: \x, d: 0)
					}
				} {
					cell.copy
				}
			}
		}

		{ transform == \accent } {
			seed.collect { |cell, i|
				if (i == (gen % seed.size) and: { cell[\v] != \x } and: { cell[\d].notNil and: { cell[\d] > 0 } }) {
					cell.copy.put(\d, 4)
				} {
					cell.copy
				}
			}
		}

		{ transform == \swap } {
			var roleKeys = seed.select { |c| c[\v] != \x and: { c[\d] > 0 } }
			                    .collect { |c| c[\v] }
			                    .asSet.asArray.sort;

			if (roleKeys.size < 2) { seed.collect(_.copy) }
			{
				var swapMap = Dictionary.new;
				roleKeys.do { |k, i|
					swapMap[k] = roleKeys.wrapAt(i + 1);
				};
				seed.collect { |cell|
					var c = cell.copy;
					if (c[\v] != \x and: { c[\d] > 0 }) {
						c.put(\v, swapMap[c[\v]] ?? c[\v])
					};
					c
				}
			}
		}

		// ─── WEIGHT-DRIVEN TRANSFORMS ───

		{ transform == \erode } {
			seed.collect { |cell|
				var c = cell.copy;
				if (c[\v] != \x and: { c[\d].notNil and: { c[\d] > 0 } }) {
					var newD = c[\d] - (if (c[\d] <= 1) { 1 } { 0 });
					if ((gen % 2 == 0) and: { c[\d] > 1 }) { newD = c[\d] - 1 };
					if (newD <= 0) { (v: \x, d: 0) } { c.put(\d, newD); c }
				} { c }
			}
		}

		{ transform == \bloom } {
			var out = seed.collect(_.copy);
			seed.do { |cell, i|
				if (cell[\v] != \x and: { cell[\d].notNil and: { cell[\d] >= 3 } }) {
					// Spawn into empty neighbors
					if (i > 0 and: { out[i-1][\v] == \x or: { out[i-1][\d] == 0 } }) {
						out[i-1] = (v: cell[\v], d: 1);
					};
					if (i < (seed.size - 1) and: { out[i+1][\v] == \x or: { out[i+1][\d] == 0 } }) {
						out[i+1] = (v: cell[\v], d: 1);
					};
				};
			};
			out
		}

		{ transform == \gravity } {
			var heavy = seed.detectIndex { |c| c[\v] != \x and: { c[\d].notNil and: { c[\d] >= 3 } } };
			if (heavy.isNil) { seed.collect(_.copy) } {
				seed.collect { |cell, i|
					var c = cell.copy;
					if (c[\v] != \x and: { c[\d].notNil and: { c[\d] > 0 and: { c[\d] < 3 } } }) {
						var dist = (i - heavy).abs;
						if (dist > 2) { (v: \x, d: 0) } { c }
					} { c }
				}
			}
		}

		{ transform == \cascade } {
			var out = seed.collect(_.copy);
			(seed.size - 1).do { |i|
				var idx = seed.size - 1 - i;
				var cur = out[idx];
				var prev = out[idx - 1];
				if (prev[\v] != \x and: { prev[\d].notNil and: { prev[\d] > 1 } }) {
					if (cur[\v] == \x or: { cur[\d] == 0 }) {
						out[idx] = (v: prev[\v], d: 1);
						out[idx - 1].put(\d, prev[\d] - 1);
					}
				}
			};
			out
		}

		// ─── STRUCTURE-AWARE TRANSFORMS ───

		{ transform == \phase } {
			var shift = (gen + 1) % seed.size;
			seed.collect(_.copy).rotate(shift.neg)
		}

		{ transform == \mirror } {
			seed.collect(_.copy).reverse
		}

		{ transform == \invert } {
			var voices = seed.select { |c| c[\v] != \x and: { c[\d] > 0 } }.collect { |c| c[\v] };
			var mainVoice = if (voices.size > 0) { voices.asArray.first } { \x };
			seed.collect { |cell|
				if (cell[\v] == \x or: { cell[\d] == 0 }) {
					(v: mainVoice, d: 1)
				} {
					(v: \x, d: 0)
				}
			}
		}

		{ transform == \stagger } {
			var shift = gen + 1;
			seed.collect(_.copy).rotate(shift)
		}

		// ─── CELLULAR AUTOMATA TRANSFORMS ───

		{ transform == \life } {
			seed.collect { |cell, i|
				var alive = cell[\v] != \x and: { cell[\d].notNil and: { cell[\d] > 0 } };
				var nL = if (i > 0) { seed[i-1][\v] != \x and: { seed[i-1][\d] > 0 } } { false };
				var nR = if (i < (seed.size-1)) { seed[i+1][\v] != \x and: { seed[i+1][\d] > 0 } } { false };
				var neighbors = nL.asInteger + nR.asInteger;
				if (alive) {
					// Survive with 1 neighbor, die with 0 or 2
					if (neighbors == 1) { cell.copy } { (v: \x, d: 0) }
				} {
					// Born with exactly 2 neighbors
					if (neighbors == 2) {
						var donor = if (nL) { seed[i-1] } { seed[i+1] };
						(v: donor[\v], d: 1)
					} { (v: \x, d: 0) }
				}
			}
		}

		{ transform == \diffuse } {
			seed.collect { |cell, i|
				var dSelf = if (cell[\d].notNil and: { cell[\d] > 0 }) { cell[\d] } { 0 };
				var dL = if (i > 0 and: { seed[i-1][\d].notNil }) { seed[i-1][\d] } { 0 };
				var dR = if (i < (seed.size-1) and: { seed[i+1][\d].notNil }) { seed[i+1][\d] } { 0 };
				var newD = ((dSelf * 2) + dL + dR / 4).round.asInteger.clip(0, 4);
				if (newD > 0) {
					var v = if (cell[\v] != \x) { cell[\v] } {
						if (dL > dR and: { i > 0 }) { seed[i-1][\v] }
						{ if (i < (seed.size-1)) { seed[i+1][\v] } { \x } }
					};
					if (v == \x) { (v: \x, d: 0) } { (v: v, d: newD) }
				} { (v: \x, d: 0) }
			}
		}

		{ transform == \fractal } {
			// Self-similar: active cells with d>2 split into 2 subcells
			var out = [];
			seed.do { |cell|
				if (cell[\v] != \x and: { cell[\d].notNil and: { cell[\d] > 2 } }) {
					out = out.add((v: cell[\v], d: (cell[\d] - 1).max(1)));
					out = out.add((v: cell[\v], d: 1));
				} {
					out = out.add(cell.copy);
				}
			};
			// Trim or pad to original size
			if (out.size > seed.size) { out = out.copyRange(0, seed.size - 1) };
			if (out.size < seed.size) { (seed.size - out.size).do { out = out.add((v: \x, d: 0)) } };
			out
		}

		// ─── MUSICAL TRANSFORMS ───

		{ transform == \call_response } {
			var half = (seed.size / 2).floor;
			var call = seed.copyRange(0, half - 1);
			var resp = call.collect { |cell|
				var c = cell.copy;
				if (c[\v] != \x and: { c[\d] > 0 }) {
					c.put(\d, (c[\d] + (gen % 2 == 0).if(1, -1)).clip(1, 4))
				};
				c
			}.rotate(1);
			(call ++ resp).copyRange(0, seed.size - 1).collect(_.copy)
		}

		{ transform == \split } {
			var out = seed.collect(_.copy);
			seed.do { |cell, i|
				if (cell[\v] != \x and: { cell[\d].notNil and: { cell[\d] > 2 } }) {
					// Find nearest empty slot
					var target = nil;
					(1..4).do { |offset|
						if (target.isNil) {
							if ((i + offset) < seed.size and: {
								out[i + offset][\v] == \x or: { out[i + offset][\d] == 0 }
							}) { target = i + offset };
							if (target.isNil and: { (i - offset) >= 0 and: {
								out[i - offset][\v] == \x or: { out[i - offset][\d] == 0 }
							} }) { target = i - offset };
						};
					};
					if (target.notNil) {
						out[target] = (v: cell[\v], d: 1);
						out[i].put(\d, cell[\d] - 1);
					};
				};
			};
			out
		}

		{ transform == \fuse } {
			var out = seed.collect(_.copy);
			var i = 0;
			while { i < (out.size - 1) } {
				var cur = out[i]; var nxt = out[i + 1];
				if (cur[\v] != \x and: { nxt[\v] == cur[\v] and: { cur[\d] > 0 and: { nxt[\d] > 0 } } }) {
					out[i].put(\d, (cur[\d] + nxt[\d]).clip(1, 4));
					out[i + 1] = (v: \x, d: 0);
					i = i + 2;
				} { i = i + 1 };
			};
			out
		}

		// Default fallback: identity
		{ true } { seed.collect(_.copy) };

		result
	};

	// ─── G4. SEED → DSL PATTERN ─────────────────────────────
	~seedToPat = { |seed, voices, ghosts, voiceMods|
		var steps = seed.collect { |cell|
			var roleKey = cell[\v];
			var depth   = cell[\d] ?? 1;
			var params  = cell[\p];
			var mods    = cell[\mods];

			if (roleKey == \x or: { depth == 0 }) {
				// Rest cell: params become bind-wrapped rest
				// (state-setting only — rest events are silent)
				if (params.notNil and: { params.isKindOf(Event) and: { params.size > 0 } }) {
					(dsl_type: \bind, head: \x, args: [params])
				} { \x }
			}
			{
				var voice = if (voices.notNil and: { voices[roleKey].notNil })
				            { voices[roleKey] } { roleKey };
				var ghost = if (ghosts.notNil) { ghosts[roleKey] };

				var base = case
					{ depth == 1 } { voice }
					{ depth == 2 } { (dsl_type: \rep, item: voice, times: 2) }
					{ depth == 3 } { (dsl_type: \rep, item: voice, times: 3) }
					{ depth >= 4 } {
						if (ghost.notNil and: { ghost != \nil } and: { ghost != \x }) {
							(dsl_type: \rep,
								item: (dsl_type: \rand, list: [voice, ghost, voice]),
								times: 4)
						} {
							(dsl_type: \rep, item: voice, times: 4)
						}
					}
					{ voice };

				var allMods = [];

				if (params.notNil and: { params.isKindOf(Event) and: { params.size > 0 } }) {
					allMods = allMods.add(params);
				};

				if (mods.notNil and: { mods.isKindOf(Array) }) {
					mods.select(_.notNil).do { |m|
						allMods = allMods.add(m);
					};
				};

				if (voiceMods.notNil and: { voiceMods.isKindOf(Event) and: { voiceMods[roleKey].notNil } }) {
					var rMods = voiceMods[roleKey];
					if (rMods.isKindOf(Array)) {
						rMods.select(_.notNil).do { |m|
							allMods = allMods.add(m);
						};
					} {
						if (rMods.notNil) { allMods = allMods.add(rMods) };
					};
				};

				if (allMods.size > 0) {
					(dsl_type: \bind, head: base, args: allMods)
				} { base }
			}
		};

		(dsl_type: \seq, list: steps)
	};

	// ─── G5. ~phrase — MAIN GENERATIVE FUNCTION ─────────────
	~phrase = { |seed, voices, ghosts, cycles, formSeq, globalMod, voiceMods|
		var normalizedSeed, currentSeed, cycleResults, result;

		cycles   = cycles   ?? 8;
		formSeq  = formSeq  ?? [\id];
		voices   = voices   ?? ();
		ghosts   = ghosts   ?? ();

		normalizedSeed = seed.collect { |cell| ~normCell.(cell) };
		currentSeed = normalizedSeed;

		cycleResults = Array.new(cycles);
		cycles.do { |cycleIdx|
			var transform = formSeq.wrapAt(cycleIdx);

			currentSeed = try {
				~seedTransform.(currentSeed, transform, cycleIdx)
			} { |err|
				"[grow warn] transform '%' at cycle %: % — identity"
					.format(transform, cycleIdx, err.errorString).postln;
				currentSeed
			};

			cycleResults = cycleResults.add(
				~seedToPat.(currentSeed, voices, ghosts, voiceMods)
			);
		};

		result = (dsl_type: \seq, list: cycleResults);

		if (globalMod.notNil) {
			if (globalMod.isKindOf(Function)) {
				try { globalMod.(result) } { |err|
					"[grow warn] globalMod: % — skipped".format(err.errorString).postln;
					result
				}
			} {
				(dsl_type: \bind, head: result, args: [globalMod])
			}
		} { result }
	};

	"> GROW phrase engine ready (% forms).".format(~form.size).postln;

	"> F2DSL v2 ready.".postln;
	// §provenance the engine's build stamp — an instant check that the right thing loaded
	"> F2DSL build: gate-v3 + loop-order-v3 + units-21 + cfg-sig + fx-base".postln;
};
