# Story, motion, and music

## Find the product's visual argument

Choose one promise grounded in the app. Select a few moments that demonstrate it, then end with the actual brand and accurate availability copy. A teaser for an app in review should not claim it is already downloadable. Use supplied official store artwork without redrawing or distorting it. Do not carry another app's colors, device frame, particle effect, or campaign copy into this one.

Begin with a designed still: app-native type, strong hierarchy, intentional negative space, a restrained palette, and one focal element. A phone outline is often sufficient for mobile UI; use the original logical viewport ratio and uniform scaling. A macOS product can use its actual window proportions. Wider compositions can put supporting copy beside the product; vertical layouts usually need shorter copy and stacked hierarchy. Preserve safe margins through motion as well as at rest.

## Author motion in screen space

Decide the viewer's attention order before adding animation. Tie a timeline's line drawing to the arrival of its corresponding moments. Reveal cards through a coordinated progression of position, opacity, subtle blur, and content stagger; avoid identical pop-ins for every element. Let the product's native shader or object motion supply character.

For an accelerating scroll, measure displacement and velocity rather than naming an easing function. A useful starting curve with immediate but slow movement is:

```text
u = clamp((t - start) / travelDuration, 0, 1)
progress = 0.04*u + 0.96*u*u*u
offset = travelDistance * progress
```

This has a nonzero opening velocity and visibly greater travel near the end. It is a starting point, not a required style. Review first-second travel, final-second travel, moment reading time, and the velocity through the exit. A long introductory hold can defeat the intended acceleration even with the correct curve. Match line reveal, camera movement, copy changes, and card entrance timing to the same travel model. Do not add long holds merely to make everything readable if the intended effect is a quick accumulation of moments.

Camera movement should reveal detail or change emphasis. Use timed position/target/lens tracks with continuous interpolation; avoid random drift and sudden lens changes. Keep hero content comfortably inside the viewport throughout the move. Stateful spring integration should be cached or replaced by seekable analytic sampling so frame previews agree with export.

## Compose one musical arc

Choose the soundtrack's mood from the brief, preferably using a licensed track or the app's authorized sound assets when they fit. Procedural synthesis is available, but instrument count and waveform complexity do not establish musical quality. Retain licensing/source information for any supplied audio. Do not require an external generation service for a local film.

Anchor the score to the edit: BPM, beat origin, phrase boundaries, buildup start, anticipation dip, visual reveal, final chord/tail. Continue a recognizable harmonic bed, motif, or pulse through scene changes. A brand reveal should feel like the same cue arriving somewhere. Avoid cutting to near silence and introducing an unrelated sound at the icon unless that is the requested direction.

For an anticipated drop, progressively simplify/filter the existing phrase, briefly pull back immediately before the mark resolves, and land the existing musical material with a deeper bass/chord or softened downbeat. Align the audible landing to the icon's perceptual formation, not merely the scene boundary. A short dip can make the reveal breathe; an extended gap can sound like two separate tracks. Let the release support staggered brand text and the final CTA without outlasting the film.

Audition the whole transition with picture. Check small speakers as well as headphones if available: a sub-bass-only payoff may disappear on a phone. Inspect clipping, unexpected silence, abrupt sample discontinuities, and mono compatibility, but report these as engineering checks. Offer a playable short comparison when musical preference remains uncertain.
