if (~play.isNil or: { ~toPat.isNil } or: { ~enrich.isNil }) {
    "✗ REMOTE EVAL ABORT: DSL not loaded. ~play/~toPat/~enrich nil.".postln;
} {
    if (~f2PatGroup.notNil and: { ~f2PatGroup.isPlaying }) { ~f2PatGroup.freeAll };
    ~f2PatGroup = Group.head(s.defaultGroup);
    "[f2re] ~f2PatGroup → node %".format(~f2PatGroup.nodeID).postln;

    // §layers/quant: НЕ переписываем ~play — DSL-версия уже делает всё (группа, cell-телеметрия,
    // merge мелодических слоёв через Prout). Переписывание здесь раньше ТЕРЯЛО 5-й аргумент
    // layers (melodySource молча умирал в remote-режиме). Сохраняем полную реализацию один раз
    // (guard от повторного eval этого файла) и добавляем только тег сцены для /f2_branch.
    ~f2PlayDSL = ~f2PlayDSL ? ~play;
    ~play = { |key, data, dur=4, quant=4, layers|
        // §16-B: текущая сцена = Pdef-ключ строки; rand/wrand в ~toPat подхватят его как
        // sceneId для /f2_branch (компилятор может также класть sceneId прямо на Event).
        topEnvironment[\f2Scene] = key;
        ~f2PlayDSL.value(key, data, dur, quant, layers);
    };

    if (~f2ContextPath.notNil) {
        "[f2re] context path: %".format(~f2ContextPath).postln;
        // Path already set, ~exportContext in f2dsl.scd uses ~f2ContextPath ?? default
    };

    ~f2Bridge = (busy: false, busyAt: 0);
    ~f2EvalQ = List.new;

    // §eval-drain v2 CmdPeriod (panic) чистит клоки и убивает drain-рутину БЕЗ
    // исключения — busy оставался true навсегда, и каждый следующий /f2/eval ядра
    // молча вставал в очередь без исполнителя: деплои не исполнялись, ядро сыпало
    // «no /f2_ack for epoch N» до полного перезапуска. Хук сбрасывает busy сам.
    CmdPeriod.add({ topEnvironment.use { ~f2Bridge.busy = false } });

    OSCdef(\f2_eval, { |msg|
        var code = msg[1].asString;
        "[f2] /eval (% chars)".format(code.size).postln;
        topEnvironment.use {
            var stale;
            // §queue плотные эвалы НЕ скипаются, а встают в очередь: скип молча терял
            // деплой, пришедший в окно длинного interpret (контент-бут проекта грузит
            // сотню synthdef'ов секундами) — ядро ждало /f2_ack впустую (§7.2 алерт).
            // Одна drain-рутина держит порядок прихода; ~f2Bridge.busy = drain жива.
            ~f2EvalQ.add(code);
            if (~f2EvalQ.size > 1) { "[f2] eval queued (depth %)".format(~f2EvalQ.size).postln };
            // §eval-drain v2 сторож на случай ЛЮБОЙ гибели рутины, не пойманной
            // хуком: busyAt штампуется на каждом элементе; тишина >10с при непустой
            // очереди = drain мёртв — поднимаем нового. Интерпретатор однопоточный,
            // поэтому гонок с живым drain нет: длинный interpret просто отодвигает
            // обработку этого сообщения до своего конца.
            stale = ~f2Bridge.busy and: { (Main.elapsedTime - (~f2Bridge.busyAt ? 0)) > 10 };
            if (stale) { "⚠ [f2] eval drain wedged — restarting it".postln; ~f2Bridge.busy = false };
            if (~f2Bridge.busy.not) {
                ~f2Bridge.busy = true;
                ~f2Bridge.busyAt = Main.elapsedTime;
                // §additive деплой ВСЕГДА привязан к конкретной сцене (Pdef-ключу строки):
                // прежний Pdef.all.stop + freeAll глушил ВСЕ параллельные строки при каждом
                // eval — при ≥2 играющих сценах запуск одной убивал остальные (несовместимо
                // с семантикой сцен и с аддитивным /f2_eval из bootstrap). Глушение целиком —
                // только явным /f2/hush. Группа паттернов создаётся лениво, если её ещё нет.
                Routine({
                    topEnvironment.use {
                        if (~f2PatGroup.isNil or: { ~f2PatGroup.isPlaying.not }) {
                            // §grp-gen ПРЕЖНЮЮ ГРУППУ ЗДЕСЬ НЕ ОСВОБОЖДАТЬ. Она и правда
                            // копится (ветка freeAll выше стоит под .isPlaying, а группа
                            // создаётся без .register(true), поэтому isPlaying у неё всегда
                            // ложь) — но `.free` группы убивает её детей МОЛЧА: /n_free по
                            // группе не шлёт /n_end на каждый узел, реестры голосов остаются
                            // с isPlaying = true на мёртвых нодах, и следующий деплой маппит
                            // их — флуд «/n_mapn Node not found» и тишина. Это ровно тот
                            // отказ, что описан в f2dsl.scd §reuse. Поколения stack-шин,
                            // которые от этого копились, подметает §bus-gen; узлы остаются
                            // как были.
                            ~f2PatGroup = Group.head(s.defaultGroup);
                            "[f2] patGroup recreated".postln;
                        };
                    };
                    0.05.wait;
                    while { topEnvironment.use { ~f2EvalQ.size > 0 } } {
                        var c;
                        topEnvironment.use {
                            c = ~f2EvalQ.removeAt(0);
                            ~f2Bridge.busyAt = Main.elapsedTime;   // §eval-drain v2 пульс сторожа
                        };
                        topEnvironment.use {
                            try { c.interpret; "✓ F2 eval ok".postln; }
                                { |err| ("✗ F2 eval: " ++ err.errorString).postln };
                            ~f2Bridge.busyAt = Main.elapsedTime;
                        };
                        0.02.wait;   // кооперативный зазор между эвалами очереди
                    };
                    topEnvironment.use { ~f2Bridge.busy = false };
                }).play(TempoClock.default);
            };
        };
    }, '/f2/eval').permanent_(true);

    OSCdef(\f2_hush, { |msg|
        "[f2] /hush".postln;
        { topEnvironment.use { Pdef.all.do(_.stop);
            if (~f2PatGroup.notNil and: { ~f2PatGroup.isPlaying }) { ~f2PatGroup.freeAll };
            // §loop-order freeAll убил ПОДГРУППЫ голосов при живом patGroup — словарь
            // подгрупп чистим, иначе следующий спавн вставлялся бы после мёртвой ноды.
            ~f2VGroups = nil; ~f2VGrp2 !? { |d| d.clear };   // §loop-order v2 (старый ключ — миграция)
            // §fix шины ~mb НЕ освобождаем: паттерны НЕпередеплоенных строк держат .asMap на
            // конкретные индексы шин — free+realloc после hush давал им чужие/мёртвые шины
            // (все live-параметры строки съезжали). Значения просто остаются; деплой их перепишет.
        } }.defer;
    }, '/f2/hush').permanent_(true);

    // ── ModEngine bridge (v2) ────────────────────────────────────────────────
    // v3: значения модуляции пишем в per-key CONTROL-ШИНЫ (~mb); событие маппит арг
    //     синта на шину через .asMap (см. компилятор) → синт читает control-rate
    //     НЕПРЕРЫВНО → модуляция двигает ДАЖЕ звучащую ноту (раньше Pdefn → лишь на онсете).
    ~mb   = ~mb ?? { IdentityDictionary.new };
    // ВНИМАНИЕ: dict.put / dict[k]=v в SC возвращает САМ СЛОВАРЬ, а не значение.
    // Поэтому шину возвращаем явно (иначе ~mbAt.(k) отдаёт ~mb → .set/.asMap падают).
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
    // §parity тело идентично v7-обработчику из boot.rs (bootstrap_code): оба пишут в шины ~mb,
    // порядок загрузки двух файлов больше НЕ меняет семантику /f2_setb. Варн — раз на ключ.
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
                // §nan-guard NaN в шину отравляет синт до следующей записи — скипаем
                if (v.notNil and: { v.asFloat.isNaN.not }) { ~mbAt.(k).set(v) };
                i = i + 2;
            };
        };
    }, '/f2_setb').permanent_(true);

    // §v2-sc SC-плеер вариантов: детерминированные выборы rand/wrand приходят ОТ ДВИЖКА
    // (/f2_choice sceneKey nodeId iter idx) и складываются в ~f2Choice по ключу
    // "<sceneKey>/<nodeId>/<iter>". ~toPat (rand/wrand с тегом v2Id) читает их на демэнде —
    // SC играет ровно тот вариант, что просчитал движок. Движок шлёт выбор ТЕКУЩЕЙ и
    // СЛЕДУЮЩЕЙ итерации на каждой границе (запас на demand-lookahead в целую петлю);
    // прошлые итерации узла прибираются лениво здесь же.
    ~f2Choice = ~f2Choice ?? { Dictionary.new };
    ~f2ChoiceLog = 12;   // §diag лог первых принятых выборов (дальше — тишина)
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
    // §16-B: адрес OSC-входа БЭКЕНДА (новая архитектура). Сюда шлём /f2_sync (часы) и
    // /f2_branch (выборы rand из ~toPat). Порт = hub.scInPort (по умолчанию 57121).
    ~f2BackendAddr = ~f2BackendAddr ?? { NetAddr("127.0.0.1", (topEnvironment[\f2BackendPort] ? 57121)) };

    // §core саморегистрация Go-ядра (f2core): оно шлёт /f2/core_hello <port> со своего
    // сокета — запоминаем адрес, зеркалим туда /f2_sync (Tdef ниже) и туда же уходят
    // /f2_ack деплоев ядра (ack-эпилог компилирует `~f2CoreAddr ? ~f2BackendAddr ? …`).
    // Порт ядра эфемерный — никакой статической конфигурации; повторный hello (рестарт
    // ядра) просто перезаписывает адрес.
    OSCdef(\f2_core_hello, { |msg, time, addr|
        topEnvironment.use {
            var port = (msg[1] ? addr.port).asInteger;
            ~f2CoreAddr = NetAddr(addr.ip, port);
            ~f2FrameSeq = -1;   // §9 рестарт ядра сбрасывает seq кадров — принимаем заново
            "[f2] core registered: %:%".format(addr.ip, port).postln;
        };
    }, '/f2/core_hello').permanent_(true);

    // §9 кадровый протокол ядра: /f2_frame proto seq beat flagsN [k,fl]… valsN [k,v]…
    // Применение атомарное в рамках датаграммы, флаги ПЕРЕД значениями (лаг сглаживателя
    // стоит верным к приходу значения). seq монотонный — стейл/дубли дропаются; рестарт
    // ядра детектится по /f2/core_hello (сброс ~f2FrameSeq). beat в будущем (лукахед
    // ядра, F2_SCHED_SEC) → применение schedAbs РОВНО на бите; иначе немедленно.
    // Переходный период: /f2_setb и /f2_setflags остаются (Node A/B), уйдут на cutover.
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
                            forBy(0, flags.size - 2, 2) { |j| ~f2FlagApply.(flags[j], flags[j + 1]) };
                        };
                        // значения — в СЫРУЮ шину при загруженном modsmooth (его сглаживатель
                        // сам ведёт гладкую), иначе в базовую ~mbAt (как /f2_setb).
                        // §nan-guard NaN не пишем (отравляет шину/сглаживатель).
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
            // §6: якорь часов для бэкенда — абсолютный бит + реальное время SC (сек).
            // Бэкенд экстраполирует фазу локально; serverTime нужен для оценки темпа.
            ~f2BackendAddr.sendMsg('/f2_sync', beatAbs.asFloat, Main.elapsedTime.asFloat);
            // §core зеркало якоря в Go-ядро (если зарегистрировалось /f2/core_hello)
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
