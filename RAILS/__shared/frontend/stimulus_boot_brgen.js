// Controllers only brgen's own views and engines mount. Split out of
// stimulus_boot.js so amber and bsdports never import these modules.
// See stimulus_boot.js for controllers every app registers, and
// stimulus_boot_social.js for the ones brgen shares with amber.
import BrgenShell from "pub5/brgen_shell"
import Dismiss from "pub5/dismiss"
import SearchPalette from "pub5/search_palette"
import OptimisticSend from "pub5/optimistic_send"
import Presence from "pub5/presence"
import PostProgressive from "pub5/post_progressive"
export function bootBrgenStimulus(application) {
  application.register("brgen-shell", BrgenShell)
  application.register("dismiss", Dismiss)
  application.register("search-palette", SearchPalette)
  application.register("optimistic-send", OptimisticSend)
  application.register("presence", Presence)
  application.register("post-progressive", PostProgressive)

}
