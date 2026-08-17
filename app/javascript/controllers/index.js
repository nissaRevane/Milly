import { application } from "controllers/application"

import AlertController from "controllers/alert_controller"
application.register("alert", AlertController)

import AutoSubmitController from "controllers/auto_submit_controller"
application.register("auto-submit", AutoSubmitController)

import SuggestedValueController from "controllers/suggested_value_controller"
application.register("suggested-value", SuggestedValueController)
