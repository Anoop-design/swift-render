# Preview, verification, and revision

## Use staged exports

1. Compile one source-backed hero frame to prove the chosen native route.
2. Render a contact sheet covering entrances, mid-transition states, dense content, reveal, and final copy. Check original asset fidelity and layout.
3. Render a short motion preview with the actual soundtrack. Inspect the encoded frames and listen when playback is available.
4. Export each requested composition at delivery dimensions and verify it. Keep versions instead of overwriting an accepted cut.

A contact sheet cannot verify acceleration or sound. A render process reporting success cannot prove the movie has all its frames. The final report should distinguish compilation, decoded media checks, visual inspection, audio audition, and subjective review.

## Verify the movie

Use AVFoundation on macOS, or installed `ffprobe`/`ffmpeg` if available. Do not install another media stack just for checks the native framework can perform. Confirm expected width/height, frame rate, duration, video track, expected audio track, finite timestamps, and the intended number of decoded frames. Fractional frame rates need a rational timebase; derive frame counts from that rather than rounded labels.

The bundled verifier uses AVFoundation and CryptoKit without external packages:

```sh
swiftc -parse-as-library <skill-directory>/scripts/verify_movie.swift -o <temporary-directory>/swiftrender-verify
<temporary-directory>/swiftrender-verify <movie.mp4> --width 1080 --height 1920 --fps 30 --frames 480 --audio required --report <film-directory>/verification.json
```

It decodes every video frame, checks timestamps, format, frame count, duration, and audio-track presence, then hashes compressed video data together with timing and track transform. Add `--compare-video <accepted-original.mp4>` after an audio-only remux. This check verifies track presence, not decoded audio quality or audible continuity. Use `--audio absent` for a deliberately silent preview, or `optional` when either is expected.

Sample the actual encoded video at cuts and effect peaks, not just intermediate PNGs. Check clipping, blurred residual text, banding, unreadable type, distorted native screen proportions, and final-frame readability. Measure peak audio levels and look for unwanted gaps around transitions; technical checks do not prove the track sounds good.

Keep the verification report beside the export with commands or script version, outcomes, renderer revision, input source hashes, geometry, FPS, edit timing, and output hashes. Record any unavailable check explicitly.

## Audio-only revisions

If the user accepts picture and asks only for sound, generate the replacement track against the unchanged edit clock. Mux it into a new movie using passthrough for video. On macOS, use `AVMutableComposition` plus `AVAssetExportSession`; if combining PCM WAV and MP4 passthrough fails, encode the audio to AAC/M4A first and then mux. Match duration and avoid a default audio fade that moves the perceived landing.

Verify compressed video sample bytes, sample counts, timing, and track transforms before and after, not the whole MP4 file hash (the audio/container necessarily changes). With ffmpeg, `-c:v copy` preserves encoded video while audio can be re-encoded; still verify the result. Full decode checks catch missing last frames or invalid timestamp handling. Never report byte preservation without checking it.

## Delivery format

Link playable local movies using absolute paths when the host supports them. Include a poster/contact sheet, the source location, and a concise account of what changed and how it was checked. Mention any source substitutions, untested platform adapters, or audio that was analyzed but not auditioned. Do not publish the movie or app code unless the user requested that external action.
