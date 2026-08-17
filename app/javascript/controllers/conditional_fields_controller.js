import { Controller } from "@hotwired/stimulus"

// Montre le bloc cible seulement quand le select porte la valeur attendue
// (data-conditional-fields-show-when-value). Masqué, ses champs sont
// désactivés pour ne rien soumettre.
export default class extends Controller {
  static targets = ["select", "fields"]
  static values = { showWhen: String }

  connect() {
    this.toggle()
  }

  toggle() {
    const shown = this.selectTarget.value === this.showWhenValue

    this.fieldsTarget.hidden = !shown
    this.fieldsTarget.querySelectorAll("input, select, textarea").forEach((field) => {
      field.disabled = !shown
    })
  }
}
