import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { bootPub5Stimulus } from "pub5/stimulus_boot"

bootPub5Stimulus(application)
eagerLoadControllersFrom("controllers", application)
