import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { bootPub4Stimulus } from "pub5/stimulus_boot"

bootPub4Stimulus(application)
eagerLoadControllersFrom("controllers", application)
