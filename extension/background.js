// Reads the active tab URL properly (no clipboard hack) and hands it to a
// native host, which opens it in Safari or in lookahead-play.
const HOST = "com.ksha23.lookahead";

browser.browserAction.onClicked.addListener(async (tab) => {
  if (!tab || !tab.url || !/^https?:/.test(tab.url)) return;
  try {
    const reply = await browser.runtime.sendNativeMessage(HOST, {
      url: tab.url,
      mode: "safari"        // or "player" to use lookahead-play
    });
    console.log("[lookahead]", reply);
  } catch (e) {
    console.error("[lookahead] native host failed:", e);
  }
});
