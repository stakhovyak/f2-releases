// ═══════════════════════════════════════════════════════════════════
// synthPrimitives.scd — drop into Synths/ folder, auto-loads with f2dsl
//
// Provides:  \fmX  \amX  \padX  (gate-based ADSR, pitchLag, telemetry)
//
// Auto-registers ~defs presets:
//   FM:   \fmBass  \fmKeys  \fmLead  \fmPerc  \fmStab
//   AM:   \amTrem  \amRing  \amPluck \amBell
//   PAD:  \padChoir \padStrings \padBell \padWarm \padOrgan \padSaw
//
// PADsynth buffers generate asynchronously on boot (~3-8 sec).
// PAD presets become playable after "[synthPrim] PAD buffers ready" message.
// FM/AM presets are available immediately.
// ═══════════════════════════════════════════════════════════════════


// ┌────────────────────────────────────┐
// │  1.  \fmX — two-operator FM synth  │
// └────────────────────────────────────┘
// Gate-based ADSR.  pitchLag for portamento.
// Works in patterns (SC manages gate), Pmono (for glides), or live .set.

SynthDef(\fmX, {
	|out=0, tel_bus=0, gate=1,
	freq=200, pitchLag=0, amp=0.5, pan=0,
	atk=0.01, dec=0.3, sus=0.7, rel=0.5, curve= -4,
	ratio=2, index=5, indexDecay=1.0,
	ratio2=3, index2=0, index2Decay=1.0,
	fbAmt=0,
	drift=0, vibRate=5, vibDepth=0,
	tone=16000, drive=1.0,
	colorID=1|

	var env, sig, smoothFreq, vibrato;
	var mod1, mod2, carrier, fb;
	var idxEnv1, idxEnv2, driven;

	// ── PITCH: lag + drift + vibrato ──
	smoothFreq = Lag.kr(freq, pitchLag);
	vibrato = SinOsc.kr(vibRate) * vibDepth * smoothFreq * 0.01;
	smoothFreq = smoothFreq
	+ vibrato
	+ (LFNoise1.kr(drift.linlin(0, 1, 0.1, 5)) * drift * smoothFreq * 0.004);

	// ── ENVELOPE ──
	env = EnvGen.kr(
		Env.adsr(atk, dec, sus, rel, 1, curve),
		gate, doneAction: 2);

	// ── FM indexes ──
	idxEnv1 = EnvGen.kr(
		Env.adsr(atk, dec * indexDecay, sus * 0.4, rel, index, curve), gate);
	idxEnv2 = EnvGen.kr(
		Env.adsr(atk, dec * index2Decay, sus * 0.3, rel, index2, curve), gate);

	// ── OPERATORS ──
	fb = LocalIn.ar(1);
	mod2 = SinOsc.ar(smoothFreq * ratio2) * smoothFreq * idxEnv2;
	mod1 = SinOsc.ar(smoothFreq * ratio + mod2
		+ (fb * fbAmt * smoothFreq * ratio));
	carrier = SinOsc.ar(smoothFreq + (mod1 * smoothFreq * idxEnv1));
	LocalOut.ar(carrier);

	sig = carrier * env * amp;

	// ── DRIVE ──
	driven = (sig * drive).tanh * drive.reciprocal.sqrt;
	sig = XFade2.ar(sig, driven, drive.linlin(1, 2, -1, 1).clip(-1, 1));

	// ── TONE ──
	sig = LPF.ar(sig, tone.clip(100, 20000));
	sig = LeakDC.ar(sig);

	// ── TELEMETRY ──
	~mkTel.(10, colorID, env, amp, pan,
		pan.linlin(-1, 1, 0, 1), freq.explin(20, 20000, 0, 1),
		index / 20, fbAmt, ratio / 16, drive / 10, tel_bus);

	Out.ar(out, Pan2.ar(sig, pan));
}).add;


// ┌────────────────────────────────────────┐
// │  2.  \amX — AM / ring mod synth        │
// └────────────────────────────────────────┘
// wave: 0=sine 1=tri 2=saw 3=pulse
// modDepth=1 → full ring mod, 0 → clean carrier

SynthDef(\amX, {
	|out=0, tel_bus=0, gate=1,
	freq=200, pitchLag=0, amp=0.5, pan=0,
	atk=0.01, dec=0.3, sus=0.7, rel=0.5, curve= -4,
	modRatio=1, modDepth=0.5, modWave=0,
	wave=0, pulseWidth=0.5,
	drift=0, vibRate=5, vibDepth=0,
	tone=16000, subOsc=0,
	colorID=2|

	var env, sig, smoothFreq, vibrato;
	var carrier, modulator, modSig, sub;

	// ── PITCH ──
	smoothFreq = Lag.kr(freq, pitchLag);
	vibrato = SinOsc.kr(vibRate) * vibDepth * smoothFreq * 0.01;
	smoothFreq = smoothFreq + vibrato
	+ (LFNoise1.kr(drift.linlin(0, 1, 0.1, 5)) * drift * smoothFreq * 0.004);

	// ── ENVELOPE ──
	env = EnvGen.kr(
		Env.adsr(atk, dec, sus, rel, 1, curve),
		gate, doneAction: 2);

	// ── CARRIER ──
	carrier = SelectX.ar(wave, [
		SinOsc.ar(smoothFreq),
		LFTri.ar(smoothFreq),
		LFSaw.ar(smoothFreq).softclip,
		Pulse.ar(smoothFreq, pulseWidth)
	]);

	// ── MODULATOR ──
	modulator = SelectX.ar(modWave, [
		SinOsc.ar(smoothFreq * modRatio),
		LFTri.ar(smoothFreq * modRatio),
		LFSaw.ar(smoothFreq * modRatio),
		Pulse.ar(smoothFreq * modRatio, 0.5)
	]);

	modSig = 1.0 - modDepth + (modDepth * modulator);
	sig = carrier * modSig;

	// ── SUB ──
	sub = SinOsc.ar(smoothFreq * 0.5) * subOsc;
	sig = sig + sub;
	sig = sig * env * amp;

	// ── TONE ──
	sig = LPF.ar(sig, tone.clip(100, 20000));
	sig = LeakDC.ar(sig);

	// ── TELEMETRY ──
	~mkTel.(11, colorID, env, amp, pan,
		pan.linlin(-1, 1, 0, 1), freq.explin(20, 20000, 0, 1),
		modDepth, modRatio / 16, wave / 3, subOsc, tel_bus);

	Out.ar(out, Pan2.ar(sig, pan));
}).add;


// ┌────────────────────────────────────────────┐
// │  3.  \padX — PADsynth wavetable player     │
// └────────────────────────────────────────────┘
// Reads a PADsynth wavetable buffer.
// L/R offset for stereo, detuned double for thickness.
// bufnum + bufBasePitch auto-filled by ~defs presets.

SynthDef(\padX, {
	|out=0, tel_bus=0, gate=1,
	freq=261.6, pitchLag=0, amp=0.5, pan=0,
	bufnum=0, bufBasePitch=261.6,
	atk=0.8, dec=1.0, sus=0.9, rel=2.0, curve= -2,
	drift=0, vibRate=4, vibDepth=0.1,
	spread=0.5, detune=0.003,
	lpFreq=16000, lpRes=0.5, hpFreq=20,
	colorID=6|

	var env, sig, smoothFreq, vibrato;
	var rate, bufFrames, phase, phaseR;
	var sigL, sigR, sigD;

	// ── PITCH ──
	smoothFreq = Lag.kr(freq, pitchLag);
	vibrato = SinOsc.kr(vibRate) * vibDepth * smoothFreq * 0.01;
	smoothFreq = smoothFreq + vibrato
	+ (LFNoise1.kr(drift.linlin(0, 1, 0.05, 3)) * drift * smoothFreq * 0.003);

	// ── ENVELOPE ──
	env = EnvGen.kr(
		Env.adsr(atk, dec, sus, rel, 1, curve),
		gate, doneAction: 2);

	// ── PLAYBACK ──
	bufFrames = BufFrames.kr(bufnum);
	rate = smoothFreq / bufBasePitch;

	// L/R read from offset positions (PADsynth doc tip)
	phase  = Phasor.ar(0,
		rate * BufRateScale.kr(bufnum),
		0, bufFrames,
		Rand(0, bufFrames));
	phaseR = (phase + (bufFrames * spread * 0.5)).wrap(0, bufFrames);

	sigL = BufRd.ar(1, bufnum, phase, 1, 4);
	sigR = BufRd.ar(1, bufnum, phaseR, 1, 4);

	// Detuned double for thickness
	sigD = BufRd.ar(1, bufnum,
		Phasor.ar(0,
			rate * (1 + detune) * BufRateScale.kr(bufnum),
			0, bufFrames,
			Rand(0, bufFrames)),
		1, 4) * 0.35;

	sig = [sigL + (sigD * 0.5), sigR + (sigD * -0.5)];
	sig = sig * env * amp;

	// ── FILTERS ──
	sig = HPF.ar(sig, hpFreq.clip(20, 5000));
	sig = RLPF.ar(sig, lpFreq.clip(100, 20000),
		lpRes.linlin(0, 1, 1.0, 0.05));
	sig = LeakDC.ar(sig);

	// ── TELEMETRY ──
	~mkTel.(12, colorID, env, amp, pan,
		pan.linlin(-1, 1, 0, 1), freq.explin(20, 20000, 0, 1),
		spread, detune * 100, vibDepth,
		lpFreq.explin(100, 20000, 0, 1), tel_bus);

	Out.ar(out, Balance2.ar(sig[0], sig[1], pan));
}).add;


// ═══════════════════════════════════════════════════════════════════
// 4.  AUTO-SETUP: buffers, presets, synthTypes
//     Runs in a fork so it doesn't block boot.
// ═══════════════════════════════════════════════════════════════════

{
	// Capture environment (fork runs on SystemClock, may lose env)
	var env = currentEnvironment;

	// ─── Register synthTypes immediately (no server needed) ───
	env[\synthTypes] = env[\synthTypes] ?? Dictionary.new;
	env[\synthTypes][10] = (name: \fmX,  class: \tonal, params: #[index, fbAmt, ratio, drive]);
	env[\synthTypes][11] = (name: \amX,  class: \tonal, params: #[modDepth, modRatio, wave, subOsc]);
	env[\synthTypes][12] = (name: \padX, class: \tonal, params: #[spread, detune, vibDepth, lpFreq]);

	// ─── Register FM/AM presets immediately ───
	env[\defs] = env[\defs] ?? Dictionary.new;

	// FM presets
	env[\defs][\fmBass] = (
		instrument: \fmX,
		ratio: 1, index: 10, indexDecay: 0.6, fbAmt: 0.15,
		atk: 0.001, dec: 0.25, sus: 0.3, rel: 0.4, tone: 2500,
		drive: 1.3, colorID: 1
	);
	env[\defs][\fmKeys] = (
		instrument: \fmX,
		ratio: 3.5, index: 4, indexDecay: 0.8,
		atk: 0.001, dec: 0.6, sus: 0.05, rel: 0.8, tone: 10000,
		colorID: 1
	);
	env[\defs][\fmLead] = (
		instrument: \fmX,
		ratio: 2, index: 6, indexDecay: 1.2,
		atk: 0.05, dec: 0.3, sus: 0.7, rel: 0.6,
		vibRate: 5, vibDepth: 0.08, pitchLag: 0.08,
		tone: 12000, colorID: 1
	);
	env[\defs][\fmPerc] = (
		instrument: \fmX,
		ratio: 1.5, index: 14, indexDecay: 0.3, fbAmt: 0.1,
		atk: 0.0005, dec: 0.15, sus: 0, rel: 0.2,
		tone: 8000, drive: 1.5, colorID: 1
	);
	env[\defs][\fmStab] = (
		instrument: \fmX,
		ratio: 3, ratio2: 5, index: 3, index2: 2,
		atk: 0.001, dec: 0.08, sus: 0.5, rel: 0.15,
		tone: 6000, colorID: 1
	);

	// AM presets
	env[\defs][\amTrem] = (
		instrument: \amX,
		modRatio: 0.25, modDepth: 0.6, wave: 0,
		atk: 0.05, dec: 0.3, sus: 0.8, rel: 0.5,
		tone: 10000, colorID: 2
	);
	env[\defs][\amRing] = (
		instrument: \amX,
		modRatio: 2.01, modDepth: 1.0, wave: 0,
		atk: 0.001, dec: 0.4, sus: 0.3, rel: 0.5,
		tone: 12000, colorID: 2
	);
	env[\defs][\amPluck] = (
		instrument: \amX,
		modRatio: 5, modDepth: 0.8, wave: 2,
		atk: 0.001, dec: 0.2, sus: 0, rel: 0.3,
		tone: 6000, colorID: 2
	);
	env[\defs][\amBell] = (
		instrument: \amX,
		modRatio: 3.5, modDepth: 0.9, wave: 0,
		atk: 0.001, dec: 1.5, sus: 0.0, rel: 2.0,
		tone: 16000, colorID: 2
	);

	// ─── PADsynth wavetable generator (Nasca O.P. algorithm) ───
	// Spectrum → random phases → IFFT → Buffer.  Self-contained.

	{
		var padGen = { |fundamental=261.6, bw=50, bwScale=1.0,
			numH=24, amps, size=65536|

			var sr = s.sampleRate ? 48000;
			var halfN = size div: 2;
			var freqAmp = FloatArray.newClear(halfN);
			var real, imag, cosTable, result, samples, peak;

			amps = amps ?? { (1..numH).collect { |n| 1.0 / n.sqrt } };
			numH = numH.min(amps.size);

			// Step 1-2: accumulate Gaussian harmonic profiles
			numH.do { |idx|
				var nh = idx + 1;
				var bwHz = (2.pow(bw / 1200.0) - 1.0) * fundamental * nh.pow(bwScale);
				var bwi = bwHz / (2.0 * sr);
				var fi  = fundamental * nh / sr;
				var jLo, jHi;

				if (bwi > 0) {
					// Only iterate ±6σ around center (Gaussian negligible beyond)
					jLo = ((fi - (bwi * 6)) * size).asInteger.max(0);
					jHi = ((fi + (bwi * 6)) * size).asInteger.min(halfN - 1);
					(jLo..jHi).do { |i|
						var x = ((i.asFloat / size) - fi) / bwi;
						freqAmp[i] = freqAmp[i] + (exp(x.neg * x) / bwi * amps[idx]);
					};
				};
			};

			// Step 3: random phases → complex spectrum
			real = Signal.newClear(size);
			imag = Signal.newClear(size);
			halfN.do { |i|
				var phase = 2pi.rand;
				real[i] = freqAmp[i] * cos(phase);
				imag[i] = freqAmp[i] * sin(phase);
			};
			// Conjugate symmetry for real output
			(1 .. halfN - 1).do { |i|
				real[size - i] = real[i];
				imag[size - i] = imag[i].neg;
			};

			// Step 4: single IFFT
			cosTable = Signal.fftCosTable(size);
			result = real.ifft(imag, cosTable);
			samples = result.real;

			// Normalize to ±0.95
			peak = samples.abs.maxItem;
			if (peak > 0) { samples = samples * (0.95 / peak) };

			samples.as(FloatArray);
		};

		// ─── Generate all PAD buffers in a fork ───

		fork {
			var profiles, basePitch = 261.6;

			s.sync;

			profiles = [
				// [name, bw, bwScale, numH, ampsFunc, colorID, extraDefs]
				[\choir,   60,  1.0, 32,
					{ |n| (1..n).collect { |i| if(i.odd, { 1.0/i }, { 0.25/i }) } }, 6,
					(atk: 1.0, dec: 1.0, sus: 0.9, rel: 2.5,
						spread: 0.6, vibDepth: 0.15, lpFreq: 10000)],

				[\strings, 40,  1.0, 32,
					{ |n| (1..n).collect { |i| 1.0 / i.pow(0.7) } }, 6,
					(atk: 0.6, dec: 0.8, sus: 0.85, rel: 1.5,
						spread: 0.5, detune: 0.004, lpFreq: 12000)],

				[\bell,    120, 1.4, 24,
					{ |n| (1..n).collect { |i| exp(i.neg * 0.12) } }, 3,
					(atk: 0.001, dec: 2.0, sus: 0.1, rel: 3.0,
						spread: 0.4, vibDepth: 0.02, lpFreq: 16000)],

				[\warm,    50,  1.0, 32,
					{ |n| (1..n).collect { |i| 1.0 / i.pow(1.5) } }, 6,
					(atk: 0.8, dec: 1.5, sus: 0.9, rel: 2.0,
						spread: 0.5, lpFreq: 5000, hpFreq: 60)],

				[\organ,   25,  1.0, 32,
					{ |n| (1..n).collect { |i|
						var db = #[0, -3, -6, -9, -12, -15, -18].wrapAt(i-1);
						db.dbamp / i.sqrt
					}}, 4,
					(atk: 0.1, dec: 0.5, sus: 0.95, rel: 0.3,
						spread: 0.3, vibDepth: 0.05, lpFreq: 8000)],

				[\saw,     35,  1.0, 48,
					{ |n| (1..n).collect { |i| 1.0 / i } }, 1,
					(atk: 0.05, dec: 0.4, sus: 0.7, rel: 0.6,
						spread: 0.4, lpFreq: 6000)],
			];

			env[\padBufs] = env[\padBufs] ?? ();

			profiles.do { |spec|
				var name     = spec[0];
				var bw       = spec[1];
				var bwScale  = spec[2];
				var numH     = spec[3];
				var ampsFunc = spec[4];
				var colID    = spec[5];
				var extra    = spec[6];
				var amps     = ampsFunc.(numH);
				var samples, buf, defName;

				"[synthPrim] generating PAD: % ...".format(name).postln;

				samples = padGen.(basePitch, bw, bwScale, numH, amps, 65536);

				buf = Buffer.alloc(s, 65536, 1);
				s.sync;
				buf.loadCollection(samples);
				s.sync;

				env[\padBufs][name] = buf;

				// Register preset: \padChoir, \padStrings, \padBell, etc.
				defName = ("pad" ++ name.asString[0].toUpper
					++ name.asString[1..]).asSymbol;

				env[\defs][defName] = (
					instrument: \padX,
					bufnum: buf.bufnum,
					bufBasePitch: basePitch,
					colorID: colID,
				).putAll(extra);

				"[synthPrim]   \\% ready (buf %)".format(
					defName, buf.bufnum).postln;
			};

			"[synthPrim] all PAD buffers and presets ready.".postln;
		};
	}.value;

	"[synthPrim] SynthDefs: \\fmX \\amX \\padX".postln;
	"[synthPrim] FM:  \\fmBass \\fmKeys \\fmLead \\fmPerc \\fmStab".postln;
	"[synthPrim] AM:  \\amTrem \\amRing \\amPluck \\amBell".postln;
	"[synthPrim] PAD: \\padChoir \\padStrings \\padBell \\padWarm \\padOrgan \\padSaw (generating...)".postln;

}.value;
