import { Controller } from "@hotwired/stimulus"

// Bascule l'affichage d'un montant vers son champ de saisie : Entrée soumet,
// Échap annule, quitter le champ soumet seulement si la valeur a changé.
export default class extends Controller {
  static targets = ["display", "form", "input"]

  edit() {
    this.displayTarget.hidden = true
    this.formTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  // Entrée déclenche la soumission implicite du formulaire, puis le champ perd le
  // focus avant que la redirection ne s'affiche : sans ce verrou, blur() soumettrait
  // une seconde fois et deux PATCH partiraient en course.
  markSubmitting() {
    this.submitting = true
  }

  cancel() {
    // La valeur est restaurée AVANT de masquer le champ : le masquage lui retire le
    // focus et déclenche blur(), qui ne reste une annulation que parce que la valeur
    // est déjà redevenue celle d'origine. Inverser ces lignes soumettrait sur Échap.
    this.inputTarget.value = this.inputTarget.defaultValue
    this.formTarget.hidden = true
    this.displayTarget.hidden = false
  }

  blur() {
    if (this.submitting) return

    if (this.unchanged) {
      this.cancel()
    } else {
      this.formTarget.requestSubmit()
    }
  }

  // Comparaison numérique : « 1000.0 » et « 1000 » sont le même montant, inutile de
  // recharger pour ça. Une saisie vide ou invalide compte comme un changement, pour
  // que requestSubmit déclenche la validation required du champ.
  get unchanged() {
    const current = parseFloat(this.inputTarget.value)

    return !Number.isNaN(current) && current === parseFloat(this.inputTarget.defaultValue)
  }
}
