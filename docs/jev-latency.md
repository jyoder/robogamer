# Jev latency notes

Measured 2026-10-15 from a home connection in the US Pacific time zone, against `jev-preview` (responses reported `jev-1.14.0`).

## What was measured

Requests had the shape the game will send. The state held 1 to 3 frames of a drawn World 1-1-style scene, the current controller state, recent controller history and a few short facts about the game. The questions were a 9-option direction-pad Choice, yes/no questions for A, B, Start and Select, and 5 extra yes/no questions kept for logging. Frames were nearest-neighbor scaled-up, palette-based PNGs (1 to 8 KB per request, encoded in about 1 to 2 ms each). Each request was a separate `curl` process, so each one opened a new HTTPS connection.

## Results

Median and 95th-percentile total request time, 8 requests per row:

| Request | Median | 95th pct | Input tokens |
| --- | --- | --- | --- |
| Text only, no images | 280-305 ms | 340-420 ms | 1,066 |
| 512x480, 1 frame | 305-333 ms | 328-342 ms | 1,775 |
| 512x480, 2 frames | 306-325 ms | 323-358 ms | 2,490 |
| 512x480, 3 frames | 337 ms | 400 ms | 3,205 |
| 320x300, 1 to 3 frames | 288-371 ms | 308-418 ms | 1,355-1,945 |
| Burst: 15 per second, 512x480, 2 frames | 300-333 ms | 328-383 ms | 2,490 |

Where the time goes in a typical request (median of 120 burst requests):

| Phase | Time |
| --- | --- |
| DNS lookup | 3 ms |
| TCP connect (one network round trip) | 57 ms |
| HTTPS setup | 75 ms |
| Upload, Jev processing and response (includes another round trip) | 188 ms |

## Findings

- A new HTTPS connection per request costs about 130 ms, around 40% of the total. Reusing one connection fixes this. Measured with `typesafe.lua` (libcurl through LuaJIT's FFI, one handle reused), a small request had a median of 152 ms on a reused connection, compared with 330 ms on a new connection each time. That's about 9 frames at 60 frames per second.
- Jev itself takes roughly 130 ms. Images add only about 5 to 25 ms over a text-only request.
- Image tokens depend on image size, not content. Each 512x480 image is about 715 tokens, and each 320x300 image about 295.
- Smaller images (320x300) were not meaningfully faster than 512x480.
- Grayscale and black-and-white images had the same token counts and times as color at the same size. Black and white also merged Mario, enemies, pipes and the ground into one black shape. Keep color.
- No rate limiting at 15 requests per second, and no slowdown under that load. All requests succeeded.
- Occasional slow requests (one at 1.3 s) looked like random network spikes, not a pattern. The real-time loop's freshness check needs to discard late answers.

## Cost

Pricing is $0.042 per million input tokens. At 15 requests per second with 2 frames (2,490 tokens each), that's about 134 million tokens and about $5.65 per hour. Dropping the logging-only yes/no questions or using fewer history frames reduces both cost and time.

## Recommendations

- Send 512x480 color frames.
- Use long-running workers that each keep one HTTPS connection open, instead of starting a `curl` process per request.
- Start with 2 frames of history, and test whether 1 is enough.
- Expect answers to be roughly 9 to 11 frames old when they arrive. Most of that is network round trips, so a closer network region would help more than changing images.
