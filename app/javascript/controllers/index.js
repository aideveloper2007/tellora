import { application } from "controllers/application"
import TabsController from "./tabs_controller"

// Register the tabs controller manually
application.register("tabs", TabsController)

// Eager load all controllers defined in the import map under controllers/**/*_controller
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)