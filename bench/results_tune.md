
## Tune: LinearScan vs ExpFromLeft crossover (n=4096, uniform)

| gap (≈n/m) | m | Linear | ExpFromLeft | winner | margin |
|---|---|---|---|---|---|
| 1 | 4096 | 66.1 μs | 70.8 μs | Linear | 7% |
| 2 | 2048 | 28.3 μs | 32.5 μs | Linear | 15% |
| 3 | 1365 | 21.0 μs | 22.2 μs | Linear | 6% |
| 4 | 1024 | 15.8 μs | 16.8 μs | Linear | 7% |
| 6 | 682 | 12.5 μs | 12.1 μs | ExpFromLeft | 3% |
| 8 | 512 | 10.7 μs | 9.6 μs | ExpFromLeft | 11% |
| 12 | 341 | 9.4 μs | 6.8 μs | ExpFromLeft | 37% |
| 16 | 256 | 8.5 μs | 5.2 μs | ExpFromLeft | 66% |
| 24 | 170 | 8.1 μs | 3.8 μs | ExpFromLeft | 112% |
| 32 | 128 | 8.2 μs | 3.0 μs | ExpFromLeft | 172% |
| 48 | 85 | 7.5 μs | 2.2 μs | ExpFromLeft | 246% |
| 64 | 64 | 7.3 μs | 1.8 μs | ExpFromLeft | 317% |
| 96 | 42 | 6.8 μs | 1.2 μs | ExpFromLeft | 452% |
| 128 | 32 | 6.5 μs | 970 ns | ExpFromLeft | 575% |
| 192 | 21 | 5.9 μs | 750 ns | ExpFromLeft | 691% |
| 256 | 16 | 5.8 μs | 580 ns | ExpFromLeft | 893% |

## Tune: ExpFromLeft vs InterpolationSearch crossover (n=65536, uniform)

| gap (≈n/m) | m | ExpFromLeft | InterpSearch | winner | margin |
|---|---|---|---|---|---|
| 8 | 8192 | 355.6 μs | 324.0 μs | InterpSearch | 10% |
| 16 | 4096 | 209.2 μs | 166.0 μs | InterpSearch | 26% |
| 24 | 2730 | 143.0 μs | 113.3 μs | InterpSearch | 26% |
| 32 | 2048 | 104.2 μs | 84.0 μs | InterpSearch | 24% |
| 48 | 1365 | 61.8 μs | 55.2 μs | InterpSearch | 12% |
| 64 | 1024 | 44.1 μs | 41.2 μs | InterpSearch | 7% |
| 96 | 682 | 27.4 μs | 26.4 μs | InterpSearch | 4% |
| 128 | 512 | 19.7 μs | 20.0 μs | ExpFromLeft | 2% |
| 256 | 256 | 10.2 μs | 9.5 μs | InterpSearch | 7% |
| 512 | 128 | 5.0 μs | 4.6 μs | InterpSearch | 9% |
| 1024 | 64 | 2.7 μs | 2.1 μs | InterpSearch | 29% |
| 4096 | 16 | 790 ns | 490 ns | InterpSearch | 61% |
| 16384 | 4 | 240 ns | 150 ns | InterpSearch | 60% |
| 65536 | 1 | 80 ns | 60 ns | InterpSearch | 33% |

## Tune: minimum n at which InterpolationSearch wins (uniform, m=16)

| n | gap | ExpFromLeft | InterpSearch | winner | margin |
|---|---|---|---|---|---|
| 32 | 2 | 250 ns | 470 ns | ExpFromLeft | 88% |
| 64 | 4 | 290 ns | 470 ns | ExpFromLeft | 62% |
| 128 | 8 | 310 ns | 490 ns | ExpFromLeft | 58% |
| 256 | 16 | 380 ns | 500 ns | ExpFromLeft | 32% |
| 512 | 32 | 420 ns | 470 ns | ExpFromLeft | 12% |
| 1024 | 64 | 460 ns | 500 ns | ExpFromLeft | 9% |
| 2048 | 128 | 520 ns | 480 ns | InterpSearch | 8% |
| 4096 | 256 | 560 ns | 470 ns | InterpSearch | 19% |
| 8192 | 512 | 600 ns | 480 ns | InterpSearch | 25% |
| 16384 | 1024 | 650 ns | 460 ns | InterpSearch | 41% |
| 65536 | 4096 | 740 ns | 480 ns | InterpSearch | 54% |
| 262144 | 16384 | 870 ns | 460 ns | InterpSearch | 89% |

## Tune: minimum m at which InterpolationSearch wins (uniform, n=65536)

| m | gap | ExpFromLeft | InterpSearch | winner | margin |
|---|---|---|---|---|---|
| 1 | 65536 | 80 ns | 70 ns | InterpSearch | 14% |
| 2 | 32768 | 150 ns | 90 ns | InterpSearch | 67% |
| 3 | 21845 | 180 ns | 120 ns | InterpSearch | 50% |
| 4 | 16384 | 210 ns | 140 ns | InterpSearch | 50% |
| 6 | 10922 | 310 ns | 200 ns | InterpSearch | 55% |
| 8 | 8192 | 430 ns | 240 ns | InterpSearch | 79% |
| 12 | 5461 | 600 ns | 360 ns | InterpSearch | 67% |
| 16 | 4096 | 760 ns | 470 ns | InterpSearch | 62% |
| 24 | 2730 | 1.1 μs | 680 ns | InterpSearch | 59% |
| 32 | 2048 | 1.4 μs | 1.0 μs | InterpSearch | 38% |
| 64 | 1024 | 2.6 μs | 2.0 μs | InterpSearch | 29% |
| 128 | 512 | 4.9 μs | 4.3 μs | InterpSearch | 12% |
| 256 | 256 | 9.4 μs | 9.5 μs | ExpFromLeft | 1% |
| 1024 | 64 | 43.2 μs | 40.9 μs | InterpSearch | 6% |
| 4096 | 16 | 200.7 μs | 165.0 μs | InterpSearch | 22% |

## Tune: InterpolationSearch downside on non-linear data (m=256)

| spacing | n | ExpFromLeft | InterpSearch | InterpSearch slowdown |
|---|---|---|---|---|
| log | 1024 | 3.2 μs | 21.4 μs | 6.78x |
| log | 16384 | 6.1 μs | 29.5 μs | 4.81x |
| log | 262144 | 10.3 μs | 44.8 μs | 4.33x |
| random | 1024 | 3.8 μs | 9.7 μs | 2.55x |
| random | 16384 | 7.2 μs | 12.4 μs | 1.71x |
| random | 262144 | 13.1 μs | 19.3 μs | 1.48x |
| two_scale | 1024 | 3.3 μs | 23.3 μs | 7.09x |
| two_scale | 16384 | 6.3 μs | 31.0 μs | 4.94x |
| two_scale | 262144 | 10.9 μs | 46.9 μs | 4.29x |
| power2 | 1024 | 3.6 μs | 22.5 μs | 6.18x |
| power2 | 16384 | 7.0 μs | 31.5 μs | 4.48x |
| power2 | 262144 | 12.4 μs | 48.1 μs | 3.88x |
| sqrt | 1024 | 3.7 μs | 21.1 μs | 5.77x |
| sqrt | 16384 | 7.2 μs | 29.2 μs | 4.06x |
| sqrt | 262144 | 13.2 μs | 46.4 μs | 3.52x |
| plateau | 1024 | 2.7 μs | 22.8 μs | 8.32x |
| plateau | 16384 | 2.8 μs | 29.6 μs | 10.74x |
| plateau | 262144 | 2.8 μs | 39.3 μs | 14.11x |
| bimodal | 1024 | 3.3 μs | 23.6 μs | 7.19x |
| bimodal | 16384 | 4.3 μs | 30.4 μs | 7.10x |
| bimodal | 262144 | 4.6 μs | 42.1 μs | 9.19x |
