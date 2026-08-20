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

  // Un select se valide au choix d'une option : il n'y a pas de frappe à terminer, et
  // attendre le blur laisserait la nouvelle valeur affichée sans être enregistrée — sur
  // macOS, choisir une option rend le focus au select, qui ne le perd jamais.
  submit() {
    if (this.unchanged) {
      this.cancel()
      return
    }

    this.markSubmitting()
    this.formTarget.requestSubmit()
  }

  cancel() {
    // La valeur est restaurée AVANT de masquer le champ : le masquage lui retire le
    // focus et déclenche blur(), qui ne reste une annulation que parce que la valeur
    // est déjà redevenue celle d'origine. Inverser ces lignes soumettrait sur Échap.
    this.inputTarget.value = this.defaultValue
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
  //
  // Les autres champs — une date, un nom, une liste — se comparent en texte : parseFloat
  // lirait « 2026-08-18 » comme 2026 et confondrait deux dates de la même année.
  get unchanged() {
    if (this.inputTarget.type !== "number") {
      return this.inputTarget.value === this.defaultValue
    }

    const current = parseFloat(this.inputTarget.value)

    return !Number.isNaN(current) && current === parseFloat(this.defaultValue)
  }

  // La valeur d'origine du champ, celle que le serveur a rendue. Un <select> n'a pas de
  // defaultValue : c'est l'option qu'il a marquée selected qui la porte, et sans elle Échap
  // remettrait « undefined » dans la liste et le blur soumettrait toujours.
  get defaultValue() {
    const input = this.inputTarget
    if (input.tagName !== "SELECT") return input.defaultValue

    const original = Array.from(input.options).find((option) => option.defaultSelected)

    return original ? original.value : ""
  }
}
