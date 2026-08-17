import { Controller } from "@hotwired/stimulus"

// Reprend dans le champ montant la suggestion portée par l'option sélectionnée
// (data-suggested-value) : pour l'actif d'un bien, son prix d'achat.
//
// La suggestion ne remplace qu'un champ vide ou une suggestion précédente, jamais un
// chiffre saisi à la main — le bilan reste ce que l'utilisateur y écrit.
export default class extends Controller {
  static targets = ["source", "value"]

  connect() {
    this.suggestion = ""
  }

  apply() {
    const next = this.sourceTarget.selectedOptions[0]?.dataset.suggestedValue || ""

    if (this.replaceable) {
      this.valueTarget.value = next
    }

    this.suggestion = next
  }

  // Remplaçable tant que le champ ne porte aucun montant voulu : vide, zéro (le défaut de
  // colonne), ou la suggestion précédente. Un chiffre saisi à la main ne l'est jamais.
  get replaceable() {
    const current = this.valueTarget.value

    return current === "" || Number(current) === 0 || current === this.suggestion
  }
}
