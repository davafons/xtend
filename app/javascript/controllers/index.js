// Controllers load the first time their data-controller appears, so a page downloads only what it uses.
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("controllers", application)
