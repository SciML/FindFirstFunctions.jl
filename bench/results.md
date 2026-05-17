# `bench/strategies.jl` results — fast sweep

Captured 2026-05-17 on Julia 1.10.11, run via
`julia --project=bench bench/strategies.jl`. 240 cells, 20 samples each,
`BenchmarkTools.minimum`.

The companion artifacts are:

- `bench/results_focused.md` — spacing/pattern/ratio/extreme sub-sweeps
- `bench/results_validate.md` — large 3920-cell validation sweep
- `bench/results_tune.md` — empirical crossover measurements that drive
  the `Auto` thresholds (LinearScan↔ExpFromLeft, ExpFromLeft↔InterpSearch,
  min-n / min-m for InterpSearch, and the InterpSearch downside on
  non-linear data)

`Auto` verdict on this sweep: **221 / 240 (92 %) within 20 % of best**.
Aggregate verdict across all sweeps (4 692 cells total):
**3 988 (85 %) within 20 % of best**; **only 1 cell exceeds 2 ×** (and that
one cell is a 180 ns absolute difference at `m = 4`).

## Fast sweep

| spacing | query pattern | n | m | Linear | Gallop | ExpFromLeft | InterpSearch | Binary | Auto | base | best | best/auto |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| uniform | sorted_uniform | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 50 ns | Linear (50 ns) | 1.20x |
| uniform | sorted_uniform | 64 | 10 | 180 ns | 220 ns | 190 ns | 310 ns | 200 ns | 190 ns | 180 ns | Linear (180 ns) | 1.06x |
| uniform | sorted_uniform | 64 | 256 | 2.1 μs | 4.2 μs | 3.0 μs | 9.0 μs | 4.2 μs | 2.2 μs | 4.8 μs | Linear (2.1 μs) | 1.01x |
| uniform | sorted_uniform | 64 | 4096 | 32.2 μs | 56.4 μs | 43.5 μs | 113.3 μs | 68.8 μs | 32.2 μs | 60.3 μs | Linear (32.2 μs) | 1.00x |
| uniform | sorted_uniform | 1024 | 1 | 60 ns | 60 ns | 60 ns | 60 ns | 60 ns | 60 ns | 60 ns | InterpSearch (60 ns) | 1.00x |
| uniform | sorted_uniform | 1024 | 10 | 1.7 μs | 410 ns | 330 ns | 320 ns | 290 ns | 370 ns | 270 ns | Binary (290 ns) | 1.28x |
| uniform | sorted_uniform | 1024 | 256 | 3.6 μs | 5.2 μs | 3.8 μs | 9.2 μs | 7.1 μs | 3.8 μs | 7.3 μs | Linear (3.6 μs) | 1.06x |
| uniform | sorted_uniform | 1024 | 4096 | 49.0 μs | 72.7 μs | 57.5 μs | 151.6 μs | 227.8 μs | 48.7 μs | 183.2 μs | Linear (49.0 μs) | 0.99x |
| uniform | sorted_uniform | 65536 | 1 | 80 ns | 80 ns | 80 ns | 60 ns | 80 ns | 80 ns | 70 ns | InterpSearch (60 ns) | 1.33x |
| uniform | sorted_uniform | 65536 | 10 | 81.6 μs | 750 ns | 500 ns | 310 ns | 430 ns | 379 ns | 410 ns | InterpSearch (310 ns) | 1.22x |
| uniform | sorted_uniform | 65536 | 256 | 100.9 μs | 12.7 μs | 9.1 μs | 9.3 μs | 14.2 μs | 9.7 μs | 17.2 μs | ExpFromLeft (9.1 μs) | 1.07x |
| uniform | sorted_uniform | 65536 | 4096 | 200.1 μs | 251.4 μs | 205.7 μs | 166.2 μs | 489.8 μs | 173.2 μs | 493.1 μs | InterpSearch (166.2 μs) | 1.04x |
| uniform | sorted_dense_burst | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 60 ns | 50 ns | 50 ns | Linear (50 ns) | 1.00x |
| uniform | sorted_dense_burst | 64 | 10 | 130 ns | 180 ns | 150 ns | 310 ns | 200 ns | 140 ns | 170 ns | Linear (130 ns) | 1.08x |
| uniform | sorted_dense_burst | 64 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 6.9 μs | 4.3 μs | 2.0 μs | 3.6 μs | Linear (2.0 μs) | 1.01x |
| uniform | sorted_dense_burst | 64 | 4096 | 30.8 μs | 55.5 μs | 42.3 μs | 109.8 μs | 67.9 μs | 30.8 μs | 56.7 μs | Linear (30.8 μs) | 1.00x |
| uniform | sorted_dense_burst | 1024 | 1 | 60 ns | 60 ns | 70 ns | 70 ns | 60 ns | 60 ns | 60 ns | Binary (60 ns) | 1.00x |
| uniform | sorted_dense_burst | 1024 | 10 | 130 ns | 190 ns | 160 ns | 310 ns | 310 ns | 150 ns | 270 ns | Linear (130 ns) | 1.15x |
| uniform | sorted_dense_burst | 1024 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 6.9 μs | 6.7 μs | 2.0 μs | 6.0 μs | Linear (2.0 μs) | 1.01x |
| uniform | sorted_dense_burst | 1024 | 4096 | 30.8 μs | 55.5 μs | 42.3 μs | 109.7 μs | 106.9 μs | 30.8 μs | 95.7 μs | Linear (30.8 μs) | 1.00x |
| uniform | sorted_dense_burst | 65536 | 1 | 80 ns | 80 ns | 80 ns | 70 ns | 80 ns | 80 ns | 70 ns | InterpSearch (70 ns) | 1.14x |
| uniform | sorted_dense_burst | 65536 | 10 | 150 ns | 200 ns | 170 ns | 310 ns | 450 ns | 170 ns | 410 ns | Linear (150 ns) | 1.13x |
| uniform | sorted_dense_burst | 65536 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 6.9 μs | 10.3 μs | 2.1 μs | 9.6 μs | Linear (2.0 μs) | 1.02x |
| uniform | sorted_dense_burst | 65536 | 4096 | 30.9 μs | 55.5 μs | 42.3 μs | 109.6 μs | 164.5 μs | 30.8 μs | 152.4 μs | Linear (30.9 μs) | 1.00x |
| uniform | sorted_near_start | 64 | 1 | 50 ns | 50 ns | 60 ns | 70 ns | 50 ns | 60 ns | 50 ns | Binary (50 ns) | 1.20x |
| uniform | sorted_near_start | 64 | 10 | 190 ns | 200 ns | 170 ns | 330 ns | 200 ns | 190 ns | 180 ns | ExpFromLeft (170 ns) | 1.12x |
| uniform | sorted_near_start | 64 | 256 | 2.1 μs | 3.7 μs | 2.8 μs | 7.0 μs | 4.3 μs | 2.2 μs | 3.8 μs | Linear (2.1 μs) | 1.06x |
| uniform | sorted_near_start | 64 | 4096 | 31.7 μs | 56.6 μs | 43.4 μs | 111.6 μs | 67.4 μs | 31.8 μs | 60.6 μs | Linear (31.7 μs) | 1.00x |
| uniform | sorted_near_start | 1024 | 1 | 70 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| uniform | sorted_near_start | 1024 | 10 | 1.4 μs | 300 ns | 230 ns | 310 ns | 290 ns | 260 ns | 270 ns | ExpFromLeft (230 ns) | 1.13x |
| uniform | sorted_near_start | 1024 | 256 | 3.8 μs | 4.7 μs | 3.5 μs | 8.7 μs | 6.8 μs | 3.7 μs | 7.0 μs | ExpFromLeft (3.5 μs) | 1.05x |
| uniform | sorted_near_start | 1024 | 4096 | 33.6 μs | 58.6 μs | 44.6 μs | 117.5 μs | 111.6 μs | 33.8 μs | 106.3 μs | Linear (33.6 μs) | 1.00x |
| uniform | sorted_near_start | 65536 | 1 | 80 ns | 80 ns | 80 ns | 70 ns | 80 ns | 70 ns | 70 ns | InterpSearch (70 ns) | 1.00x |
| uniform | sorted_near_start | 65536 | 10 | 36.5 μs | 520 ns | 400 ns | 300 ns | 430 ns | 440 ns | 430 ns | InterpSearch (300 ns) | 1.47x |
| uniform | sorted_near_start | 65536 | 256 | 95.9 μs | 8.0 μs | 5.7 μs | 9.0 μs | 11.9 μs | 5.9 μs | 19.9 μs | ExpFromLeft (5.7 μs) | 1.03x |
| uniform | sorted_near_start | 65536 | 4096 | 157.0 μs | 120.9 μs | 98.0 μs | 162.6 μs | 379.6 μs | 96.9 μs | 301.5 μs | ExpFromLeft (98.0 μs) | 0.99x |
| uniform | unsorted | 64 | 1 | 50 ns | 50 ns | 50 ns | 70 ns | 50 ns | 50 ns | 50 ns | ExpFromLeft (50 ns) | 1.00x |
| uniform | unsorted | 64 | 10 | 190 ns | 180 ns | 180 ns | 180 ns | 190 ns | 200 ns | 180 ns | InterpSearch (180 ns) | 1.11x |
| uniform | unsorted | 64 | 256 | 6.1 μs | 6.0 μs | 6.0 μs | 5.9 μs | 6.0 μs | 6.0 μs | 5.8 μs | InterpSearch (5.9 μs) | 1.01x |
| uniform | unsorted | 64 | 4096 | 230.8 μs | 230.3 μs | 229.0 μs | 229.3 μs | 227.0 μs | 226.9 μs | 224.7 μs | Binary (227.0 μs) | 1.00x |
| uniform | unsorted | 1024 | 1 | 60 ns | 70 ns | 70 ns | 60 ns | 60 ns | 60 ns | 60 ns | InterpSearch (60 ns) | 1.00x |
| uniform | unsorted | 1024 | 10 | 270 ns | 280 ns | 280 ns | 280 ns | 290 ns | 290 ns | 270 ns | Linear (270 ns) | 1.07x |
| uniform | unsorted | 1024 | 256 | 8.5 μs | 8.1 μs | 8.1 μs | 8.1 μs | 8.0 μs | 8.1 μs | 8.0 μs | Binary (8.0 μs) | 1.00x |
| uniform | unsorted | 1024 | 4096 | 412.4 μs | 410.2 μs | 411.5 μs | 408.8 μs | 410.6 μs | 411.7 μs | 412.4 μs | InterpSearch (408.8 μs) | 1.01x |
| uniform | unsorted | 65536 | 1 | 80 ns | 80 ns | 80 ns | 70 ns | 80 ns | 80 ns | 70 ns | InterpSearch (70 ns) | 1.14x |
| uniform | unsorted | 65536 | 10 | 420 ns | 430 ns | 430 ns | 420 ns | 430 ns | 440 ns | 410 ns | InterpSearch (420 ns) | 1.05x |
| uniform | unsorted | 65536 | 256 | 15.1 μs | 14.6 μs | 14.5 μs | 14.3 μs | 14.5 μs | 14.4 μs | 17.1 μs | InterpSearch (14.3 μs) | 1.00x |
| uniform | unsorted | 65536 | 4096 | 854.7 μs | 851.6 μs | 849.7 μs | 853.0 μs | 852.6 μs | 852.9 μs | 857.9 μs | ExpFromLeft (849.7 μs) | 1.00x |
| log | sorted_uniform | 64 | 1 | 60 ns | 60 ns | 60 ns | 70 ns | 50 ns | 60 ns | 50 ns | Binary (50 ns) | 1.20x |
| log | sorted_uniform | 64 | 10 | 170 ns | 220 ns | 190 ns | 440 ns | 200 ns | 220 ns | 180 ns | Linear (170 ns) | 1.29x |
| log | sorted_uniform | 64 | 256 | 2.3 μs | 3.8 μs | 3.0 μs | 11.3 μs | 4.5 μs | 2.4 μs | 4.2 μs | Linear (2.3 μs) | 1.01x |
| log | sorted_uniform | 64 | 4096 | 31.7 μs | 55.6 μs | 43.2 μs | 170.7 μs | 69.1 μs | 31.7 μs | 60.6 μs | Linear (31.7 μs) | 1.00x |
| log | sorted_uniform | 1024 | 1 | 60 ns | 70 ns | 60 ns | 100 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| log | sorted_uniform | 1024 | 10 | 470 ns | 330 ns | 260 ns | 670 ns | 290 ns | 300 ns | 270 ns | ExpFromLeft (260 ns) | 1.15x |
| log | sorted_uniform | 1024 | 256 | 3.2 μs | 4.6 μs | 3.2 μs | 16.3 μs | 7.1 μs | 3.3 μs | 8.1 μs | ExpFromLeft (3.2 μs) | 1.03x |
| log | sorted_uniform | 1024 | 4096 | 38.5 μs | 62.7 μs | 48.7 μs | 286.3 μs | 170.3 μs | 38.7 μs | 124.9 μs | Linear (38.5 μs) | 1.00x |
| log | sorted_uniform | 65536 | 1 | 80 ns | 80 ns | 80 ns | 130 ns | 80 ns | 80 ns | 80 ns | ExpFromLeft (80 ns) | 1.00x |
| log | sorted_uniform | 65536 | 10 | 19.6 μs | 580 ns | 440 ns | 910 ns | 440 ns | 470 ns | 410 ns | ExpFromLeft (440 ns) | 1.07x |
| log | sorted_uniform | 65536 | 256 | 89.7 μs | 10.3 μs | 7.7 μs | 25.5 μs | 13.5 μs | 7.7 μs | 17.6 μs | ExpFromLeft (7.7 μs) | 1.01x |
| log | sorted_uniform | 65536 | 4096 | 183.7 μs | 198.8 μs | 154.0 μs | 657.0 μs | 438.3 μs | 153.8 μs | 418.9 μs | ExpFromLeft (154.0 μs) | 1.00x |
| log | sorted_dense_burst | 64 | 1 | 50 ns | 50 ns | 60 ns | 80 ns | 60 ns | 50 ns | 50 ns | Gallop (50 ns) | 1.00x |
| log | sorted_dense_burst | 64 | 10 | 130 ns | 180 ns | 150 ns | 490 ns | 200 ns | 140 ns | 170 ns | Linear (130 ns) | 1.08x |
| log | sorted_dense_burst | 64 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 11.2 μs | 4.3 μs | 2.0 μs | 3.6 μs | Linear (2.0 μs) | 1.01x |
| log | sorted_dense_burst | 64 | 4096 | 30.8 μs | 55.4 μs | 42.3 μs | 176.7 μs | 68.0 μs | 32.9 μs | 60.7 μs | Linear (30.8 μs) | 1.07x |
| log | sorted_dense_burst | 1024 | 1 | 60 ns | 70 ns | 70 ns | 100 ns | 60 ns | 60 ns | 60 ns | Binary (60 ns) | 1.00x |
| log | sorted_dense_burst | 1024 | 10 | 130 ns | 190 ns | 160 ns | 680 ns | 310 ns | 149 ns | 270 ns | Linear (130 ns) | 1.15x |
| log | sorted_dense_burst | 1024 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 16.2 μs | 6.7 μs | 2.0 μs | 6.0 μs | Linear (2.0 μs) | 1.00x |
| log | sorted_dense_burst | 1024 | 4096 | 30.8 μs | 55.6 μs | 42.3 μs | 259.1 μs | 106.8 μs | 30.8 μs | 95.7 μs | Linear (30.8 μs) | 1.00x |
| log | sorted_dense_burst | 65536 | 1 | 80 ns | 80 ns | 80 ns | 130 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| log | sorted_dense_burst | 65536 | 10 | 150 ns | 200 ns | 170 ns | 989 ns | 450 ns | 170 ns | 420 ns | Linear (150 ns) | 1.13x |
| log | sorted_dense_burst | 65536 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 24.1 μs | 10.3 μs | 2.0 μs | 9.6 μs | Linear (2.0 μs) | 1.00x |
| log | sorted_dense_burst | 65536 | 4096 | 30.8 μs | 55.5 μs | 42.4 μs | 384.3 μs | 164.5 μs | 30.8 μs | 152.5 μs | Linear (30.8 μs) | 1.00x |
| log | sorted_near_start | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 50 ns | Linear (50 ns) | 1.20x |
| log | sorted_near_start | 64 | 10 | 190 ns | 200 ns | 160 ns | 330 ns | 200 ns | 199 ns | 170 ns | ExpFromLeft (160 ns) | 1.24x |
| log | sorted_near_start | 64 | 256 | 2.1 μs | 3.6 μs | 2.8 μs | 7.3 μs | 4.3 μs | 2.1 μs | 3.9 μs | Linear (2.1 μs) | 1.01x |
| log | sorted_near_start | 64 | 4096 | 31.2 μs | 55.8 μs | 42.8 μs | 116.7 μs | 67.6 μs | 33.2 μs | 59.9 μs | Linear (31.2 μs) | 1.06x |
| log | sorted_near_start | 1024 | 1 | 60 ns | 60 ns | 60 ns | 80 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| log | sorted_near_start | 1024 | 10 | 1.2 μs | 300 ns | 230 ns | 480 ns | 300 ns | 280 ns | 270 ns | ExpFromLeft (230 ns) | 1.22x |
| log | sorted_near_start | 1024 | 256 | 3.8 μs | 4.5 μs | 3.4 μs | 12.2 μs | 6.8 μs | 3.8 μs | 7.0 μs | ExpFromLeft (3.4 μs) | 1.13x |
| log | sorted_near_start | 1024 | 4096 | 33.5 μs | 58.0 μs | 44.0 μs | 191.1 μs | 110.4 μs | 33.6 μs | 102.9 μs | Linear (33.5 μs) | 1.00x |
| log | sorted_near_start | 65536 | 1 | 80 ns | 80 ns | 80 ns | 120 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| log | sorted_near_start | 65536 | 10 | 61.2 μs | 550 ns | 420 ns | 800 ns | 440 ns | 450 ns | 410 ns | ExpFromLeft (420 ns) | 1.07x |
| log | sorted_near_start | 65536 | 256 | 93.7 μs | 7.7 μs | 5.6 μs | 20.7 μs | 12.2 μs | 6.0 μs | 19.5 μs | ExpFromLeft (5.6 μs) | 1.05x |
| log | sorted_near_start | 65536 | 4096 | 159.8 μs | 112.2 μs | 88.8 μs | 497.8 μs | 369.6 μs | 89.5 μs | 293.0 μs | ExpFromLeft (88.8 μs) | 1.01x |
| log | unsorted | 64 | 1 | 60 ns | 50 ns | 60 ns | 90 ns | 60 ns | 50 ns | 50 ns | Gallop (50 ns) | 1.00x |
| log | unsorted | 64 | 10 | 190 ns | 190 ns | 190 ns | 180 ns | 190 ns | 200 ns | 180 ns | InterpSearch (180 ns) | 1.11x |
| log | unsorted | 64 | 256 | 4.9 μs | 5.1 μs | 5.0 μs | 4.9 μs | 4.9 μs | 5.0 μs | 5.1 μs | Linear (4.9 μs) | 1.03x |
| log | unsorted | 64 | 4096 | 169.8 μs | 169.8 μs | 174.5 μs | 167.8 μs | 167.1 μs | 167.6 μs | 172.2 μs | Binary (167.1 μs) | 1.00x |
| log | unsorted | 1024 | 1 | 60 ns | 70 ns | 60 ns | 90 ns | 70 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| log | unsorted | 1024 | 10 | 280 ns | 280 ns | 270 ns | 270 ns | 290 ns | 290 ns | 260 ns | InterpSearch (270 ns) | 1.07x |
| log | unsorted | 1024 | 256 | 9.9 μs | 9.8 μs | 9.8 μs | 9.7 μs | 9.7 μs | 9.5 μs | 9.6 μs | InterpSearch (9.7 μs) | 0.98x |
| log | unsorted | 1024 | 4096 | 350.5 μs | 349.2 μs | 347.7 μs | 344.9 μs | 342.0 μs | 343.8 μs | 344.6 μs | Binary (342.0 μs) | 1.01x |
| log | unsorted | 65536 | 1 | 80 ns | 80 ns | 80 ns | 130 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| log | unsorted | 65536 | 10 | 420 ns | 420 ns | 420 ns | 420 ns | 420 ns | 430 ns | 410 ns | InterpSearch (420 ns) | 1.02x |
| log | unsorted | 65536 | 256 | 17.8 μs | 17.6 μs | 17.3 μs | 17.4 μs | 17.4 μs | 17.5 μs | 19.2 μs | ExpFromLeft (17.3 μs) | 1.02x |
| log | unsorted | 65536 | 4096 | 705.9 μs | 703.7 μs | 703.3 μs | 704.5 μs | 705.5 μs | 705.9 μs | 707.2 μs | ExpFromLeft (703.3 μs) | 1.00x |
| jittered | sorted_uniform | 64 | 1 | 50 ns | 50 ns | 60 ns | 60 ns | 50 ns | 50 ns | 50 ns | Binary (50 ns) | 1.00x |
| jittered | sorted_uniform | 64 | 10 | 180 ns | 230 ns | 180 ns | 310 ns | 210 ns | 210 ns | 180 ns | ExpFromLeft (180 ns) | 1.17x |
| jittered | sorted_uniform | 64 | 256 | 2.2 μs | 4.2 μs | 3.2 μs | 9.1 μs | 4.3 μs | 2.2 μs | 5.0 μs | Linear (2.2 μs) | 1.02x |
| jittered | sorted_uniform | 64 | 4096 | 32.2 μs | 56.2 μs | 43.5 μs | 113.6 μs | 68.7 μs | 32.2 μs | 60.2 μs | Linear (32.2 μs) | 1.00x |
| jittered | sorted_uniform | 1024 | 1 | 60 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| jittered | sorted_uniform | 1024 | 10 | 1.5 μs | 380 ns | 290 ns | 340 ns | 300 ns | 400 ns | 270 ns | ExpFromLeft (290 ns) | 1.38x |
| jittered | sorted_uniform | 1024 | 256 | 3.6 μs | 5.5 μs | 3.8 μs | 9.1 μs | 7.4 μs | 3.7 μs | 7.6 μs | Linear (3.6 μs) | 1.02x |
| jittered | sorted_uniform | 1024 | 4096 | 48.5 μs | 72.8 μs | 57.9 μs | 152.2 μs | 233.2 μs | 48.2 μs | 181.6 μs | Linear (48.5 μs) | 0.99x |
| jittered | sorted_uniform | 65536 | 1 | 80 ns | 80 ns | 80 ns | 70 ns | 80 ns | 80 ns | 70 ns | InterpSearch (70 ns) | 1.14x |
| jittered | sorted_uniform | 65536 | 10 | 58.7 μs | 670 ns | 480 ns | 310 ns | 440 ns | 370 ns | 410 ns | InterpSearch (310 ns) | 1.19x |
| jittered | sorted_uniform | 65536 | 256 | 99.7 μs | 12.7 μs | 9.6 μs | 9.7 μs | 13.2 μs | 10.2 μs | 16.6 μs | ExpFromLeft (9.6 μs) | 1.07x |
| jittered | sorted_uniform | 65536 | 4096 | 201.7 μs | 253.6 μs | 206.0 μs | 164.3 μs | 490.9 μs | 171.4 μs | 497.2 μs | InterpSearch (164.3 μs) | 1.04x |
| jittered | sorted_dense_burst | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 50 ns | 60 ns | 50 ns | Binary (50 ns) | 1.20x |
| jittered | sorted_dense_burst | 64 | 10 | 120 ns | 180 ns | 150 ns | 320 ns | 200 ns | 140 ns | 170 ns | Linear (120 ns) | 1.17x |
| jittered | sorted_dense_burst | 64 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 7.0 μs | 4.3 μs | 2.0 μs | 3.6 μs | Linear (2.0 μs) | 1.00x |
| jittered | sorted_dense_burst | 64 | 4096 | 30.8 μs | 55.4 μs | 42.3 μs | 110.0 μs | 67.9 μs | 30.8 μs | 56.7 μs | Linear (30.8 μs) | 1.00x |
| jittered | sorted_dense_burst | 1024 | 1 | 70 ns | 60 ns | 70 ns | 70 ns | 60 ns | 60 ns | 60 ns | Binary (60 ns) | 1.00x |
| jittered | sorted_dense_burst | 1024 | 10 | 130 ns | 190 ns | 160 ns | 310 ns | 310 ns | 150 ns | 270 ns | Linear (130 ns) | 1.15x |
| jittered | sorted_dense_burst | 1024 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 7.0 μs | 6.7 μs | 2.0 μs | 6.0 μs | Linear (2.0 μs) | 1.00x |
| jittered | sorted_dense_burst | 1024 | 4096 | 31.3 μs | 55.7 μs | 42.3 μs | 109.8 μs | 106.7 μs | 30.8 μs | 95.8 μs | Linear (31.3 μs) | 0.98x |
| jittered | sorted_dense_burst | 65536 | 1 | 80 ns | 80 ns | 80 ns | 70 ns | 80 ns | 80 ns | 70 ns | InterpSearch (70 ns) | 1.14x |
| jittered | sorted_dense_burst | 65536 | 10 | 150 ns | 200 ns | 170 ns | 310 ns | 450 ns | 160 ns | 420 ns | Linear (150 ns) | 1.07x |
| jittered | sorted_dense_burst | 65536 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 6.9 μs | 10.3 μs | 2.0 μs | 9.6 μs | Linear (2.0 μs) | 1.01x |
| jittered | sorted_dense_burst | 65536 | 4096 | 30.8 μs | 55.5 μs | 42.3 μs | 109.6 μs | 164.5 μs | 30.8 μs | 152.5 μs | Linear (30.8 μs) | 1.00x |
| jittered | sorted_near_start | 64 | 1 | 50 ns | 60 ns | 60 ns | 60 ns | 60 ns | 60 ns | 50 ns | Linear (50 ns) | 1.20x |
| jittered | sorted_near_start | 64 | 10 | 200 ns | 200 ns | 160 ns | 330 ns | 200 ns | 190 ns | 170 ns | ExpFromLeft (160 ns) | 1.19x |
| jittered | sorted_near_start | 64 | 256 | 2.1 μs | 3.7 μs | 2.8 μs | 7.0 μs | 4.3 μs | 2.1 μs | 3.9 μs | Linear (2.1 μs) | 1.01x |
| jittered | sorted_near_start | 64 | 4096 | 31.8 μs | 56.6 μs | 43.4 μs | 111.1 μs | 68.8 μs | 31.8 μs | 60.4 μs | Linear (31.8 μs) | 1.00x |
| jittered | sorted_near_start | 1024 | 1 | 60 ns | 70 ns | 70 ns | 70 ns | 60 ns | 60 ns | 60 ns | Binary (60 ns) | 1.00x |
| jittered | sorted_near_start | 1024 | 10 | 720 ns | 290 ns | 240 ns | 310 ns | 290 ns | 270 ns | 260 ns | ExpFromLeft (240 ns) | 1.12x |
| jittered | sorted_near_start | 1024 | 256 | 3.8 μs | 4.6 μs | 3.6 μs | 9.1 μs | 6.7 μs | 3.8 μs | 7.1 μs | ExpFromLeft (3.6 μs) | 1.04x |
| jittered | sorted_near_start | 1024 | 4096 | 33.7 μs | 58.4 μs | 44.5 μs | 116.9 μs | 111.0 μs | 34.2 μs | 104.4 μs | Linear (33.7 μs) | 1.01x |
| jittered | sorted_near_start | 65536 | 1 | 80 ns | 80 ns | 80 ns | 70 ns | 80 ns | 80 ns | 70 ns | InterpSearch (70 ns) | 1.14x |
| jittered | sorted_near_start | 65536 | 10 | 80.0 μs | 540 ns | 410 ns | 300 ns | 430 ns | 440 ns | 440 ns | InterpSearch (300 ns) | 1.47x |
| jittered | sorted_near_start | 65536 | 256 | 93.3 μs | 7.9 μs | 5.9 μs | 9.0 μs | 11.9 μs | 5.9 μs | 19.8 μs | ExpFromLeft (5.9 μs) | 0.99x |
| jittered | sorted_near_start | 65536 | 4096 | 157.2 μs | 120.1 μs | 95.8 μs | 159.2 μs | 375.8 μs | 94.3 μs | 301.1 μs | ExpFromLeft (95.8 μs) | 0.98x |
| jittered | unsorted | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 60 ns | 50 ns | 50 ns | Linear (50 ns) | 1.00x |
| jittered | unsorted | 64 | 10 | 190 ns | 180 ns | 190 ns | 180 ns | 200 ns | 200 ns | 180 ns | InterpSearch (180 ns) | 1.11x |
| jittered | unsorted | 64 | 256 | 5.3 μs | 5.2 μs | 5.2 μs | 5.2 μs | 5.1 μs | 5.1 μs | 5.3 μs | Binary (5.1 μs) | 1.00x |
| jittered | unsorted | 64 | 4096 | 231.3 μs | 228.1 μs | 228.5 μs | 228.5 μs | 228.2 μs | 228.1 μs | 226.8 μs | Gallop (228.1 μs) | 1.00x |
| jittered | unsorted | 1024 | 1 | 60 ns | 60 ns | 70 ns | 70 ns | 60 ns | 60 ns | 60 ns | Binary (60 ns) | 1.00x |
| jittered | unsorted | 1024 | 10 | 280 ns | 280 ns | 280 ns | 280 ns | 300 ns | 300 ns | 270 ns | InterpSearch (280 ns) | 1.07x |
| jittered | unsorted | 1024 | 256 | 8.5 μs | 8.3 μs | 8.2 μs | 8.3 μs | 8.1 μs | 8.1 μs | 8.0 μs | Binary (8.1 μs) | 1.00x |
| jittered | unsorted | 1024 | 4096 | 414.1 μs | 411.7 μs | 413.0 μs | 411.2 μs | 412.2 μs | 412.8 μs | 408.3 μs | InterpSearch (411.2 μs) | 1.00x |
| jittered | unsorted | 65536 | 1 | 80 ns | 80 ns | 80 ns | 70 ns | 70 ns | 80 ns | 70 ns | InterpSearch (70 ns) | 1.14x |
| jittered | unsorted | 65536 | 10 | 420 ns | 420 ns | 420 ns | 420 ns | 430 ns | 430 ns | 410 ns | InterpSearch (420 ns) | 1.02x |
| jittered | unsorted | 65536 | 256 | 14.8 μs | 14.5 μs | 14.4 μs | 14.3 μs | 14.3 μs | 14.2 μs | 17.5 μs | Binary (14.3 μs) | 1.00x |
| jittered | unsorted | 65536 | 4096 | 850.3 μs | 847.7 μs | 848.3 μs | 849.4 μs | 848.5 μs | 848.4 μs | 859.1 μs | Gallop (847.7 μs) | 1.00x |
| random | sorted_uniform | 64 | 1 | 50 ns | 50 ns | 60 ns | 60 ns | 50 ns | 60 ns | 50 ns | Binary (50 ns) | 1.20x |
| random | sorted_uniform | 64 | 10 | 190 ns | 230 ns | 190 ns | 380 ns | 200 ns | 240 ns | 180 ns | ExpFromLeft (190 ns) | 1.26x |
| random | sorted_uniform | 64 | 256 | 2.2 μs | 4.0 μs | 3.1 μs | 8.7 μs | 4.3 μs | 2.2 μs | 4.5 μs | Linear (2.2 μs) | 1.02x |
| random | sorted_uniform | 64 | 4096 | 32.2 μs | 56.5 μs | 43.5 μs | 127.6 μs | 68.3 μs | 32.2 μs | 60.0 μs | Linear (32.2 μs) | 1.00x |
| random | sorted_uniform | 1024 | 1 | 70 ns | 60 ns | 70 ns | 90 ns | 60 ns | 60 ns | 60 ns | Binary (60 ns) | 1.00x |
| random | sorted_uniform | 1024 | 10 | 1.7 μs | 410 ns | 320 ns | 410 ns | 290 ns | 360 ns | 270 ns | Binary (290 ns) | 1.24x |
| random | sorted_uniform | 1024 | 256 | 3.6 μs | 5.3 μs | 3.8 μs | 10.3 μs | 7.1 μs | 3.7 μs | 7.8 μs | Linear (3.6 μs) | 1.02x |
| random | sorted_uniform | 1024 | 4096 | 45.3 μs | 70.2 μs | 55.7 μs | 188.4 μs | 206.8 μs | 44.5 μs | 159.7 μs | Linear (45.3 μs) | 0.98x |
| random | sorted_uniform | 65536 | 1 | 80 ns | 79 ns | 80 ns | 90 ns | 80 ns | 80 ns | 70 ns | Gallop (79 ns) | 1.01x |
| random | sorted_uniform | 65536 | 10 | 55.6 μs | 660 ns | 490 ns | 560 ns | 440 ns | 510 ns | 420 ns | Binary (440 ns) | 1.16x |
| random | sorted_uniform | 65536 | 256 | 100.7 μs | 12.5 μs | 9.8 μs | 15.3 μs | 13.9 μs | 10.0 μs | 16.0 μs | ExpFromLeft (9.8 μs) | 1.02x |
| random | sorted_uniform | 65536 | 4096 | 195.2 μs | 251.3 μs | 202.9 μs | 365.8 μs | 491.4 μs | 204.3 μs | 489.8 μs | Linear (195.2 μs) | 1.05x |
| random | sorted_dense_burst | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 50 ns | 50 ns | 50 ns | Binary (50 ns) | 1.00x |
| random | sorted_dense_burst | 64 | 10 | 120 ns | 180 ns | 150 ns | 360 ns | 200 ns | 140 ns | 170 ns | Linear (120 ns) | 1.17x |
| random | sorted_dense_burst | 64 | 256 | 2.1 μs | 3.5 μs | 2.7 μs | 7.9 μs | 4.3 μs | 2.0 μs | 3.6 μs | Linear (2.1 μs) | 0.94x |
| random | sorted_dense_burst | 64 | 4096 | 30.8 μs | 55.4 μs | 42.3 μs | 125.3 μs | 68.0 μs | 30.8 μs | 56.8 μs | Linear (30.8 μs) | 1.00x |
| random | sorted_dense_burst | 1024 | 1 | 60 ns | 60 ns | 60 ns | 80 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| random | sorted_dense_burst | 1024 | 10 | 140 ns | 190 ns | 160 ns | 480 ns | 310 ns | 170 ns | 270 ns | Linear (140 ns) | 1.21x |
| random | sorted_dense_burst | 1024 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 11.1 μs | 6.8 μs | 2.0 μs | 6.0 μs | Linear (2.0 μs) | 1.01x |
| random | sorted_dense_burst | 1024 | 4096 | 30.8 μs | 55.5 μs | 42.3 μs | 175.6 μs | 106.8 μs | 30.8 μs | 95.8 μs | Linear (30.8 μs) | 1.00x |
| random | sorted_dense_burst | 65536 | 1 | 80 ns | 80 ns | 80 ns | 90 ns | 80 ns | 70 ns | 70 ns | ExpFromLeft (80 ns) | 0.88x |
| random | sorted_dense_burst | 65536 | 10 | 140 ns | 200 ns | 170 ns | 670 ns | 450 ns | 160 ns | 420 ns | Linear (140 ns) | 1.14x |
| random | sorted_dense_burst | 65536 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 15.3 μs | 10.3 μs | 2.0 μs | 9.6 μs | Linear (2.0 μs) | 1.01x |
| random | sorted_dense_burst | 65536 | 4096 | 30.8 μs | 55.5 μs | 42.4 μs | 241.5 μs | 164.5 μs | 30.9 μs | 152.5 μs | Linear (30.8 μs) | 1.00x |
| random | sorted_near_start | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 50 ns | Linear (50 ns) | 1.20x |
| random | sorted_near_start | 64 | 10 | 200 ns | 200 ns | 170 ns | 330 ns | 200 ns | 200 ns | 180 ns | ExpFromLeft (170 ns) | 1.18x |
| random | sorted_near_start | 64 | 256 | 2.1 μs | 3.7 μs | 2.8 μs | 7.8 μs | 4.2 μs | 2.1 μs | 3.9 μs | Linear (2.1 μs) | 1.01x |
| random | sorted_near_start | 64 | 4096 | 31.5 μs | 56.2 μs | 42.9 μs | 122.8 μs | 67.5 μs | 31.4 μs | 60.8 μs | Linear (31.5 μs) | 1.00x |
| random | sorted_near_start | 1024 | 1 | 70 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| random | sorted_near_start | 1024 | 10 | 730 ns | 280 ns | 210 ns | 410 ns | 290 ns | 240 ns | 310 ns | ExpFromLeft (210 ns) | 1.14x |
| random | sorted_near_start | 1024 | 256 | 4.0 μs | 4.5 μs | 3.4 μs | 10.2 μs | 6.9 μs | 3.9 μs | 6.9 μs | ExpFromLeft (3.4 μs) | 1.13x |
| random | sorted_near_start | 1024 | 4096 | 33.5 μs | 58.4 μs | 44.6 μs | 150.8 μs | 112.3 μs | 33.9 μs | 103.2 μs | Linear (33.5 μs) | 1.01x |
| random | sorted_near_start | 65536 | 1 | 80 ns | 80 ns | 80 ns | 90 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| random | sorted_near_start | 65536 | 10 | 42.4 μs | 510 ns | 400 ns | 500 ns | 440 ns | 420 ns | 440 ns | ExpFromLeft (400 ns) | 1.05x |
| random | sorted_near_start | 65536 | 256 | 96.4 μs | 7.7 μs | 6.0 μs | 11.5 μs | 11.6 μs | 5.9 μs | 19.8 μs | ExpFromLeft (6.0 μs) | 0.99x |
| random | sorted_near_start | 65536 | 4096 | 160.3 μs | 129.1 μs | 107.3 μs | 254.2 μs | 362.5 μs | 107.7 μs | 288.0 μs | ExpFromLeft (107.3 μs) | 1.00x |
| random | unsorted | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 50 ns | Linear (50 ns) | 1.20x |
| random | unsorted | 64 | 10 | 180 ns | 190 ns | 190 ns | 190 ns | 189 ns | 200 ns | 180 ns | Linear (180 ns) | 1.11x |
| random | unsorted | 64 | 256 | 7.3 μs | 7.2 μs | 7.2 μs | 7.1 μs | 7.1 μs | 7.1 μs | 6.7 μs | Binary (7.1 μs) | 1.00x |
| random | unsorted | 64 | 4096 | 210.3 μs | 208.5 μs | 207.1 μs | 209.0 μs | 207.2 μs | 207.9 μs | 206.5 μs | ExpFromLeft (207.1 μs) | 1.00x |
| random | unsorted | 1024 | 1 | 60 ns | 60 ns | 60 ns | 70 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| random | unsorted | 1024 | 10 | 280 ns | 280 ns | 280 ns | 279 ns | 280 ns | 290 ns | 270 ns | InterpSearch (279 ns) | 1.04x |
| random | unsorted | 1024 | 256 | 8.7 μs | 8.4 μs | 8.4 μs | 8.3 μs | 8.1 μs | 8.3 μs | 8.1 μs | Binary (8.1 μs) | 1.03x |
| random | unsorted | 1024 | 4096 | 385.2 μs | 378.6 μs | 378.0 μs | 377.1 μs | 377.1 μs | 378.6 μs | 377.0 μs | Binary (377.1 μs) | 1.00x |
| random | unsorted | 65536 | 1 | 80 ns | 80 ns | 80 ns | 90 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| random | unsorted | 65536 | 10 | 430 ns | 430 ns | 420 ns | 450 ns | 440 ns | 450 ns | 430 ns | ExpFromLeft (420 ns) | 1.07x |
| random | unsorted | 65536 | 256 | 15.4 μs | 14.5 μs | 14.3 μs | 14.3 μs | 14.3 μs | 14.3 μs | 18.3 μs | ExpFromLeft (14.3 μs) | 1.00x |
| random | unsorted | 65536 | 4096 | 856.5 μs | 856.0 μs | 857.6 μs | 856.5 μs | 855.9 μs | 856.1 μs | 859.9 μs | Binary (855.9 μs) | 1.00x |
| two_scale | sorted_uniform | 64 | 1 | 50 ns | 50 ns | 60 ns | 80 ns | 60 ns | 60 ns | 50 ns | Gallop (50 ns) | 1.20x |
| two_scale | sorted_uniform | 64 | 10 | 170 ns | 220 ns | 170 ns | 410 ns | 210 ns | 200 ns | 180 ns | ExpFromLeft (170 ns) | 1.18x |
| two_scale | sorted_uniform | 64 | 256 | 2.4 μs | 3.9 μs | 3.1 μs | 11.4 μs | 4.5 μs | 2.4 μs | 4.0 μs | Linear (2.4 μs) | 1.01x |
| two_scale | sorted_uniform | 64 | 4096 | 31.5 μs | 55.7 μs | 43.0 μs | 167.0 μs | 68.9 μs | 31.5 μs | 59.3 μs | Linear (31.5 μs) | 1.00x |
| two_scale | sorted_uniform | 1024 | 1 | 70 ns | 70 ns | 60 ns | 100 ns | 60 ns | 60 ns | 60 ns | ExpFromLeft (60 ns) | 1.00x |
| two_scale | sorted_uniform | 1024 | 10 | 570 ns | 360 ns | 290 ns | 620 ns | 300 ns | 330 ns | 270 ns | ExpFromLeft (290 ns) | 1.14x |
| two_scale | sorted_uniform | 1024 | 256 | 2.9 μs | 4.6 μs | 3.2 μs | 15.9 μs | 7.2 μs | 2.9 μs | 8.0 μs | Linear (2.9 μs) | 1.00x |
| two_scale | sorted_uniform | 1024 | 4096 | 40.0 μs | 63.7 μs | 50.5 μs | 290.0 μs | 159.9 μs | 40.1 μs | 110.2 μs | Linear (40.0 μs) | 1.00x |
| two_scale | sorted_uniform | 65536 | 1 | 80 ns | 80 ns | 80 ns | 130 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| two_scale | sorted_uniform | 65536 | 10 | 45.8 μs | 630 ns | 470 ns | 910 ns | 430 ns | 500 ns | 410 ns | Binary (430 ns) | 1.16x |
| two_scale | sorted_uniform | 65536 | 256 | 60.2 μs | 11.5 μs | 8.4 μs | 27.5 μs | 14.1 μs | 8.5 μs | 16.6 μs | ExpFromLeft (8.4 μs) | 1.01x |
| two_scale | sorted_uniform | 65536 | 4096 | 191.1 μs | 203.3 μs | 161.6 μs | 684.5 μs | 442.5 μs | 162.1 μs | 420.6 μs | ExpFromLeft (161.6 μs) | 1.00x |
| two_scale | sorted_dense_burst | 64 | 1 | 50 ns | 50 ns | 60 ns | 80 ns | 60 ns | 60 ns | 50 ns | Gallop (50 ns) | 1.20x |
| two_scale | sorted_dense_burst | 64 | 10 | 130 ns | 180 ns | 150 ns | 480 ns | 200 ns | 160 ns | 160 ns | Linear (130 ns) | 1.23x |
| two_scale | sorted_dense_burst | 64 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 11.5 μs | 4.3 μs | 2.0 μs | 3.6 μs | Linear (2.0 μs) | 1.00x |
| two_scale | sorted_dense_burst | 64 | 4096 | 30.8 μs | 55.6 μs | 42.3 μs | 180.3 μs | 67.9 μs | 30.8 μs | 56.8 μs | Linear (30.8 μs) | 1.00x |
| two_scale | sorted_dense_burst | 1024 | 1 | 70 ns | 70 ns | 80 ns | 100 ns | 70 ns | 60 ns | 60 ns | Binary (70 ns) | 0.86x |
| two_scale | sorted_dense_burst | 1024 | 10 | 140 ns | 220 ns | 180 ns | 720 ns | 310 ns | 150 ns | 280 ns | Linear (140 ns) | 1.07x |
| two_scale | sorted_dense_burst | 1024 | 256 | 2.2 μs | 4.3 μs | 3.1 μs | 17.2 μs | 6.7 μs | 2.0 μs | 5.9 μs | Linear (2.2 μs) | 0.92x |
| two_scale | sorted_dense_burst | 1024 | 4096 | 33.8 μs | 67.8 μs | 49.2 μs | 274.8 μs | 107.4 μs | 30.9 μs | 95.7 μs | Linear (33.8 μs) | 0.91x |
| two_scale | sorted_dense_burst | 65536 | 1 | 80 ns | 80 ns | 80 ns | 130 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| two_scale | sorted_dense_burst | 65536 | 10 | 170 ns | 240 ns | 199 ns | 1.0 μs | 450 ns | 220 ns | 420 ns | Linear (170 ns) | 1.29x |
| two_scale | sorted_dense_burst | 65536 | 256 | 2.0 μs | 3.5 μs | 2.7 μs | 24.3 μs | 10.3 μs | 2.0 μs | 9.6 μs | Linear (2.0 μs) | 1.00x |
| two_scale | sorted_dense_burst | 65536 | 4096 | 30.8 μs | 55.5 μs | 42.3 μs | 391.1 μs | 164.5 μs | 30.8 μs | 152.5 μs | Linear (30.8 μs) | 1.00x |
| two_scale | sorted_near_start | 64 | 1 | 50 ns | 60 ns | 60 ns | 70 ns | 50 ns | 60 ns | 50 ns | Binary (50 ns) | 1.20x |
| two_scale | sorted_near_start | 64 | 10 | 190 ns | 200 ns | 170 ns | 330 ns | 200 ns | 200 ns | 180 ns | ExpFromLeft (170 ns) | 1.18x |
| two_scale | sorted_near_start | 64 | 256 | 2.2 μs | 3.6 μs | 2.8 μs | 7.1 μs | 4.3 μs | 2.1 μs | 3.9 μs | Linear (2.2 μs) | 0.96x |
| two_scale | sorted_near_start | 64 | 4096 | 31.5 μs | 56.1 μs | 42.9 μs | 113.5 μs | 67.6 μs | 31.5 μs | 60.1 μs | Linear (31.5 μs) | 1.00x |
| two_scale | sorted_near_start | 1024 | 1 | 60 ns | 60 ns | 70 ns | 89 ns | 60 ns | 70 ns | 60 ns | Binary (60 ns) | 1.17x |
| two_scale | sorted_near_start | 1024 | 10 | 1.3 μs | 280 ns | 240 ns | 460 ns | 290 ns | 270 ns | 280 ns | ExpFromLeft (240 ns) | 1.12x |
| two_scale | sorted_near_start | 1024 | 256 | 3.7 μs | 4.4 μs | 3.2 μs | 11.5 μs | 6.8 μs | 3.7 μs | 6.8 μs | ExpFromLeft (3.2 μs) | 1.15x |
| two_scale | sorted_near_start | 1024 | 4096 | 34.1 μs | 57.8 μs | 44.0 μs | 179.8 μs | 110.1 μs | 33.7 μs | 102.6 μs | Linear (34.1 μs) | 0.99x |
| two_scale | sorted_near_start | 65536 | 1 | 80 ns | 80 ns | 80 ns | 120 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (80 ns) | 1.00x |
| two_scale | sorted_near_start | 65536 | 10 | 61.9 μs | 540 ns | 410 ns | 790 ns | 440 ns | 440 ns | 450 ns | ExpFromLeft (410 ns) | 1.07x |
| two_scale | sorted_near_start | 65536 | 256 | 96.1 μs | 7.8 μs | 6.0 μs | 20.6 μs | 11.9 μs | 5.8 μs | 19.0 μs | ExpFromLeft (6.0 μs) | 0.96x |
| two_scale | sorted_near_start | 65536 | 4096 | 162.5 μs | 121.7 μs | 98.1 μs | 479.2 μs | 359.9 μs | 102.8 μs | 286.0 μs | ExpFromLeft (98.1 μs) | 1.05x |
| two_scale | unsorted | 64 | 1 | 50 ns | 60 ns | 60 ns | 80 ns | 50 ns | 60 ns | 50 ns | Binary (50 ns) | 1.20x |
| two_scale | unsorted | 64 | 10 | 180 ns | 190 ns | 180 ns | 190 ns | 200 ns | 210 ns | 190 ns | ExpFromLeft (180 ns) | 1.17x |
| two_scale | unsorted | 64 | 256 | 6.3 μs | 6.2 μs | 6.3 μs | 6.2 μs | 6.2 μs | 6.3 μs | 6.0 μs | Gallop (6.2 μs) | 1.03x |
| two_scale | unsorted | 64 | 4096 | 181.2 μs | 181.8 μs | 182.2 μs | 179.6 μs | 178.3 μs | 177.1 μs | 173.5 μs | Binary (178.3 μs) | 0.99x |
| two_scale | unsorted | 1024 | 1 | 60 ns | 60 ns | 70 ns | 90 ns | 60 ns | 60 ns | 60 ns | Binary (60 ns) | 1.00x |
| two_scale | unsorted | 1024 | 10 | 280 ns | 280 ns | 280 ns | 270 ns | 290 ns | 290 ns | 270 ns | InterpSearch (270 ns) | 1.07x |
| two_scale | unsorted | 1024 | 256 | 10.1 μs | 10.0 μs | 9.9 μs | 9.9 μs | 9.6 μs | 9.7 μs | 9.4 μs | Binary (9.6 μs) | 1.02x |
| two_scale | unsorted | 1024 | 4096 | 345.9 μs | 344.6 μs | 343.2 μs | 339.2 μs | 337.2 μs | 339.0 μs | 340.1 μs | Binary (337.2 μs) | 1.01x |
| two_scale | unsorted | 65536 | 1 | 80 ns | 80 ns | 70 ns | 120 ns | 80 ns | 80 ns | 70 ns | ExpFromLeft (70 ns) | 1.14x |
| two_scale | unsorted | 65536 | 10 | 420 ns | 420 ns | 430 ns | 420 ns | 440 ns | 430 ns | 410 ns | InterpSearch (420 ns) | 1.02x |
| two_scale | unsorted | 65536 | 256 | 16.0 μs | 15.8 μs | 15.8 μs | 15.7 μs | 15.6 μs | 15.7 μs | 18.8 μs | Binary (15.6 μs) | 1.00x |
| two_scale | unsorted | 65536 | 4096 | 751.6 μs | 752.4 μs | 752.7 μs | 750.5 μs | 751.6 μs | 752.3 μs | 756.8 μs | InterpSearch (750.5 μs) | 1.00x |

**Auto verdict over 240 cells**: 221 within 20% of best, 14 worse than 20% slowdown, 5 effectively-faster-than-best.
