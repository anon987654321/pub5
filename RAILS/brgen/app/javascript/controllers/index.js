import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { bootPub4Stimulus } from "pub5/stimulus_boot"
import { bootSocialStimulus } from "pub5/stimulus_boot_social"
import { bootBrgenStimulus } from "pub5/stimulus_boot_brgen"

bootPub4Stimulus(application)
bootSocialStimulus(application)
bootBrgenStimulus(application)
eagerLoadControllersFrom("controllers", application)
