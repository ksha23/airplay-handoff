# lookahead

Route video to AirPlay speakers through the **buffered** AirPlay engine (~120 ms)
instead of macOS system audio output (350-2000 ms).

Companion to [preroll](https://github.com/ksha23/preroll),
which tunes the system-audio path. This repo routes *around* it where possible.

## The idea

macOS AirPlay has two audio engines. AirPlaySender exports both:

    _APAudioEngineBufferedCreate        _APEndpointStreamBufferedAudioCreate
    _APAudioHoseManagerBufferedCreate   _APAudioEngineBufferedAdapterCreate

versus the realtime one, which the logs label `RTAE ['HLA']`. **HLA is High
Latency Audio.** Apple named it that.

**Which engine you get is decided by the content, not by a setting.**

- **System audio output** is *live*. The samples do not exist until the moment
  they are produced, so nothing can be sent ahead. The receiver's buffer depth
  **is** the latency, one for one. This is the realtime engine.
- **A media player** hands AirPlay a stream plus a timeline. The receiver
  pre-fetches ahead of the playhead because the content already exists, so
  buffer depth costs nothing. Latency is just control overhead. The system-audio
  route logs this value even while unused:

      Setting media presentation latency to 120 ms and media presentation mode to inactive

Play/pause/seek differ too. Realtime means flush the buffer then refill it.
Buffered means re-anchor a timeline. That is why the buffered path feels instant
rather than merely fast.

**Corollary: live audio can never use the buffered path.** Discord, Zoom, games,
and system sounds are not fixable this way. That is causality, not a macOS
limitation.

## What gets the buffered path

| | buffered (~120 ms) |
|---|---|
| Safari native player | yes |
| QuickTime Player | yes |
| Music, TV | yes |
| Firefox, Chrome | **no** |
| Discord, Zoom, games, system sounds | never possible |

Firefox does link AVFoundation, but for hardware video decode, not playback
routing. It decodes in-process and pushes PCM at CoreAudio through cubeb, so it
never hands a media object to AirPlay.

## Tools

### `lookahead.sh` - send the current tab to Safari

    ./lookahead.sh              # detects the frontmost browser

Chrome, Brave and Edge expose the active tab URL over AppleScript. Firefox does
not, so it falls back to focusing the window and copying the address bar, then
restores your clipboard.

Bind it to a hotkey with Shortcuts.app ("Run Shell Script"), Raycast, or
Automator (Quick Action, then System Settings > Keyboard > Shortcuts).

### `lookahead-play` - play anything through AVPlayer

    ./lookahead-play ~/Movies/thing.mkv
    ./lookahead-play https://www.youtube.com/watch?v=...

Opens an `AVPlayerView` with `allowsExternalPlayback = true`, which is the line
that matters. Pick your speakers with the AirPlay button in the controls.

Web page URLs are resolved to a direct stream with `yt-dlp` (`brew install yt-dlp`).
Direct media URLs and local files need no dependency. If yt-dlp returns separate
DASH video and audio URLs, they are muxed into an `AVMutableComposition`.

**Prototype limitation:** it prefers a single muxed stream for reliability, which
on YouTube caps quality around 720p. The composition fallback handles higher
quality but is less reliable on remote assets.

### `extension/` + `native/` - Firefox extension prototype

A WebExtension **cannot** trigger AirPlay. There is no API for it, and there will
not be one. What it *can* do is fix the handoff UX: read the active tab URL
properly instead of the clipboard hack.

    ./native/install-host.sh
    # then: about:debugging > This Firefox > Load Temporary Add-on > extension/manifest.json

Toolbar button sends the tab URL to a native messaging host, which opens it in
Safari (`mode: "safari"`) or in `lookahead-play` (`mode: "player"`).

## Should this be a Firefox PR instead?

Two separate things, and only one is worth patching.

**Already fixed upstream, do not bother.** I assumed Firefox ignored the
stream-scope latency where AirPlay reports its delay. That is wrong.
`audiounit_get_device_presentation_latency` in `cubeb_audiounit.cpp` sums both:

    adr.mSelector = kAudioDevicePropertyLatency;      // dev
    adr.mSelector = kAudioDevicePropertyStreams;      // sid[0]
    adr.mSelector = kAudioStreamPropertyLatency;      // stream
    return dev + stream;

**Worth a PR.** That value is sampled exactly once, in `audiounit_setup_stream`:

    stm->current_latency_frames = audiounit_get_device_presentation_latency(...)   // line ~2766

and never re-queried. There is no listener on `kAudioDevicePropertyLatency` or
`kAudioStreamPropertyLatency`. cubeb installs listeners only for
`kAudioDevicePropertyDeviceIsAlive` and `kAudioDevicePropertyDataSource`.

That matters for AirPlay specifically, because AirPlay latency is explicitly
dynamic and macOS notifies on change. The HAL driver contains:

    stream_AudioEngineOutputLatencyChanged
    AudioEngineDynamicLatencyOffsetChangedCallback
    kAPEndpointStreamAudioEngineNotification_OutputLatencyChanged
    "latency changed from %1.3f to %1.3f"
    "received LatencyChanged notification from AudioEngine, reconfiguring..."

A stale `current_latency_frames` feeds straight into
`audiounit_stream_get_position`, which subtracts it from `frames_played`. Wrong
position means wrong A/V sync.

**Proposed patch:** add property listeners for `kAudioDevicePropertyLatency`
(output scope) and `kAudioStreamPropertyLatency` on the output stream, and
recompute `current_latency_frames` when either fires. Small, self-contained,
and testable by changing `audioLatencyMs` mid-stream.

Getting Firefox onto the *buffered* engine is a far larger job. It would mean
adopting AVPlayer-based external playback for media elements on macOS, which is
an architectural change to Firefox's media stack, not a patch.

## License and trademarks

MIT. See `LICENSE`.

An independent project, **not affiliated with, authorised, sponsored, or endorsed
by Apple Inc.** AirPlay, HomePod, Safari, QuickTime and macOS are trademarks of
Apple Inc., used here only to describe what this software interoperates with.
Mozilla and Firefox are trademarks of the Mozilla Foundation.

## Caveats

- Prototypes. The handoff clipboard fallback is inherently racy; the extension
  path exists precisely to avoid it.
- `lookahead-play` has no playlist, no subtitle support, no quality picker.
- Verified on macOS 26.5.1, Apple Silicon.
