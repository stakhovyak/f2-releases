// §smp The analysis the Sampler contract depends on, offline: Onsets and Pitch
// over a sample, recorded into a three-channel buffer (onset trigger, detected
// pitch, pitch confidence) and written out as a float WAV so the result can be
// read back and checked. This is the same shape the engine uses at sample load
// time to fill the onset table and the pitch track.
//
//   python3 mksamples.py .              # writes beat.wav / line.wav / pad.wav
//   QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none ./analyze.scd
//
// Expect ~10 onsets on beat.wav, spaced about 0.125 s (120 bpm sixteenths);
// the default threshold deliberately misses the weakest hits — that is what the
// Onset Sensitivity control exists for.
(
var dir = "./";   // run mksamples.py into this directory first
var msgs = [], score, beatBuf = 0, ansBuf = 1, sr = 44100;
// Onsets -> a control-rate trigger stream recorded into a buffer we can read back.
// NRT: /b_allocRead the sample, /b_alloc the analysis target, run a def that writes
// the onset trigger and the detected pitch into it with RecordBuf.
SynthDef(\f2AnalyzeOnsets, { |buf = 0, out = 0, dst = 1, thresh = 0.5|
	var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf), doneAction: 2);
	var chain = FFT(LocalBuf(512), sig);
	var ons = Onsets.kr(chain, thresh, \rcomplex);
	var pitch = Pitch.kr(sig, ampThreshold: 0.02)[0];
	var hasP = Pitch.kr(sig, ampThreshold: 0.02)[1];
	RecordBuf.ar(K2A.ar([ons, pitch, hasP]), dst, loop: 0);
	Out.ar(out, sig ! 2);
}).add;
msgs = msgs.add([0.0, ['/d_recv', SynthDescLib.global.at(\f2AnalyzeOnsets).def.asBytes]]);
msgs = msgs.add([0.0, ['/b_allocRead', beatBuf, dir ++ "beat.wav"]]);
msgs = msgs.add([0.0, ['/b_alloc', ansBuf, sr * 2, 3]]);
msgs = msgs.add([0.05, ['/s_new', 'f2AnalyzeOnsets', 1000, 0, 0, 'buf', beatBuf, 'dst', ansBuf]]);
msgs = msgs.add([1.8, ['/b_write', ansBuf, "./beat-analysis.wav", "wav", "float"]]);
msgs = msgs.add([2.0, [0]]);
score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT("./analyze.osc", "./analyze.aiff", nil, sr, "AIFF", "int16",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== analysis rendered ===".postln; 0.exit });
)
