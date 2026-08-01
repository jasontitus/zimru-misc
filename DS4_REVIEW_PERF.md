# DS4 sweep review (perf focus) — zimru-misc

Exhaustive per-file pass: 3 code files across 1 batches.

## Findings

# batch-1 performance findings

- [medium] bench/zimrecreate_libzim.cpp:101 — per-entry heap allocation churn in the recreate hot loop: `creator.addItem(std::shared_ptr<zim::writer::Item>(new CopyItem(entry.getItem())))` does two allocations per entry (object + shared_ptr control block) plus by-value copies of the `zim::Item` handle (the `entry.getItem()` temporary, the `CopyItem` member at line 40, and the `ItemProvider` member at line 26). — For a multi-million-entry ZIM this is millions of paired allocations and handle copies on the loop that drives the whole benchmark's recreate time, inflating the libzim baseline vs zimru. — Use `std::make_shared<CopyItem>(entry.getItem())` (one allocation instead of two) and move the handle into the members (`item(std::move(item))` in the CopyItem and ItemProvider constructors) instead of copying it.

- [low] bench/bench.sh:67 — the "matched zstd level 19" claim is not honored for the libzim runs: only the zimru invocations (lines 69, 73) get `env ZSTD_CLEVEL=19`, while the libzim harness runs (lines 67, 72) get no compression-level setting, so libzim uses its default compression level. — The two tools are compressed at different levels, so output size and per-cluster compression time differ and the apples-to-apples recreate-time/size comparison is not valid. — Export `ZSTD_CLEVEL=19` (or set the libzim Creator compression level) for the libzim runs so both tools compress at zstd level 19.

## Coverage
bench/bench.sh — findings: 1
bench/build-baseline.sh — clean
bench/zimrecreate_libzim.cpp — findings: 1

## Run stats

Engine throughput (weighted across batches): prefill 9854 tok @ 1408 t/s, generated 4426 tok @ 27.7 t/s (1 batches)
