// lookahead-play - play a URL or local file through AVPlayer so that AirPlay uses
// the BUFFERED engine (~120 ms) instead of the realtime system-audio engine
// (audioLatencyMs, 350-2000 ms).
//
// Why this works: buffered AirPlay pre-fetches ahead of the playhead, so the
// receiver's buffer depth costs nothing. That requires known-ahead media with a
// timeline, which is exactly what AVPlayer hands to AirPlay. Live system audio
// can never do this.
//
// Web page URLs are resolved to a direct media stream with yt-dlp.

import AppKit
import AVKit
import AVFoundation

let mediaExts: Set<String> = ["mp4","m4v","mov","m3u8","mp3","m4a","aac","wav","flac","aif","aiff","mkv","webm"]

func die(_ m: String) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    exit(1)
}

func run(_ launch: String, _ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launch)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return (-1, "") }
    let d = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
}

func which(_ tool: String) -> String? {
    for d in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
        let p = "\(d)/\(tool)"
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

/// Resolve a page URL to one or two direct media URLs via yt-dlp.
func resolve(_ page: String) -> [URL] {
    guard let ytdlp = which("yt-dlp") else {
        die("""
            yt-dlp not found. Install it:
                brew install yt-dlp
            (Only needed for web page URLs. Direct media files and local paths work without it.)
            """)
    }
    FileHandle.standardError.write("resolving with yt-dlp...\n".data(using: .utf8)!)
    // Prefer a single muxed stream: one URL, no compositing, most reliable.
    for fmt in ["b[vcodec!=none][acodec!=none][protocol^=http]", "bv*+ba/b"] {
        let (rc, out) = run(ytdlp, ["-f", fmt, "-g", "--no-warnings", page])
        let urls = out.split(separator: "\n").compactMap { URL(string: String($0)) }
        if rc == 0 && !urls.isEmpty { return urls }
    }
    die("yt-dlp could not resolve a media stream from: \(page)")
}

/// Build a playable item. Two URLs (DASH video + audio) are muxed into a composition.
func makeItem(_ urls: [URL], _ done: @escaping (AVPlayerItem) -> Void) {
    if urls.count == 1 { done(AVPlayerItem(url: urls[0])); return }
    let vAsset = AVURLAsset(url: urls[0]), aAsset = AVURLAsset(url: urls[1])
    let comp = AVMutableComposition()
    Task {
        do {
            let vTracks = try await vAsset.loadTracks(withMediaType: .video)
            let aTracks = try await aAsset.loadTracks(withMediaType: .audio)
            let vDur = try await vAsset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: vDur)
            if let v = vTracks.first,
               let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try t.insertTimeRange(range, of: v, at: .zero)
            }
            if let a = aTracks.first,
               let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try t.insertTimeRange(range, of: a, at: .zero)
            }
            await MainActor.run { done(AVPlayerItem(asset: comp)) }
        } catch {
            await MainActor.run { done(AVPlayerItem(url: urls[0])) }
        }
    }
}

// ---------- argument ----------
let argv = Array(CommandLine.arguments.dropFirst())
guard let arg = argv.first, !arg.isEmpty else {
    die("""
        usage: lookahead-play <url | file>

        Plays through AVPlayer so AirPlay uses the buffered engine (~120 ms).
        Pick your HomePods with the AirPlay button in the player controls.
        """)
}

var mediaURLs: [URL] = []
if arg.hasPrefix("http://") || arg.hasPrefix("https://") {
    let ext = (URL(string: arg)?.pathExtension ?? "").lowercased()
    mediaURLs = mediaExts.contains(ext) ? [URL(string: arg)!] : resolve(arg)
} else {
    let path = (arg as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: path) else { die("no such file: \(path)") }
    mediaURLs = [URL(fileURLWithPath: path)]
}

// ---------- app ----------
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var player: AVPlayer!
    let urls: [URL]
    init(urls: [URL]) { self.urls = urls }

    func applicationDidFinishLaunching(_ n: Notification) {
        player = AVPlayer()
        // THE important line: let AirPlay take the media stream, not raw PCM.
        player.allowsExternalPlayback = true

        let view = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 960, height: 560))
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true

        window = NSWindow(contentRect: view.frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "lookahead-play"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Explicit route picker, in case the player chrome hides it.
        let picker = AVRoutePickerView(frame: NSRect(x: 12, y: 12, width: 40, height: 26))
        picker.player = player
        view.addSubview(picker)

        makeItem(urls) { [weak self] item in
            guard let self else { return }
            self.player.replaceCurrentItem(with: item)
            self.player.play()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = Delegate(urls: mediaURLs)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
