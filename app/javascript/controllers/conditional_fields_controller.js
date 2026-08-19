import { Controller } from "@hotwired/stimulus"

// Montre chaque bloc cible seulement quand le select porte une des valeurs que ce bloc
// déclare (data-conditional-fields-show-when, séparées par des espaces). Masqué, ses
// champs sont désactivés pour ne rien soumettre.
export default class extends Controller {
  static targets = ["select", "fields"]

  connect() {
    this.toggle()
  }

  toggle() {
    this.fieldsTargets.forEach((fields) => {
      const shown = this.shownValues(fields).includes(this.selectTarget.value)

      fields.hidden = !shown
      fields.querySelectorAll("input, select, textarea").forEach((field) => {
        field.disabled = !shown
      })
    })
  }

  shownValues(fields) {
    return (fields.dataset.conditionalFieldsShowWhen || "").split(" ").filter(Boolean)
  }
}
