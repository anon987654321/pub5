// Controllers mounted only by brgen and amber's views — not bsdports.
// Split out of stimulus_boot.js so bsdports never imports these modules.
// See stimulus_boot.js for controllers every app registers.
import MediaExclusive from "pub5/media_exclusive"
import BrowserFingerprint from "pub5/browser_fingerprint"
import DirectUpload from "pub5/direct_upload"
import ScrollChrome from "pub5/scroll_chrome"
import Autosave from "pub5/autosave"
import DraftStore from "pub5/draft_store"
import MediaPicker from "pub5/media_picker"
import FeedCompose from "pub5/feed_compose"
import LinkPreview from "pub5/link_preview"
import VisualSurface from "pub5/visual_surface"
import OutboundClick from "pub5/outbound_click"
import ConversationLog from "pub5/conversation_log"
export function bootSocialStimulus(application) {
  application.register("media-exclusive", MediaExclusive)
  application.register("browser-fingerprint", BrowserFingerprint)
  application.register("direct-upload", DirectUpload)
  application.register("scroll-chrome", ScrollChrome)
  application.register("autosave", Autosave)
  application.register("draft-store", DraftStore)
  application.register("media-picker", MediaPicker)
  application.register("feed-compose", FeedCompose)
  application.register("link-preview", LinkPreview)
  application.register("visual-field", VisualSurface)
  application.register("outbound-click", OutboundClick)
  application.register("conversation-log", ConversationLog)

}
