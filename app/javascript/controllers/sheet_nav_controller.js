import { Controller } from "@hotwired/stimulus"

// Les flèches du clavier suivent les flèches de la page : ← vers le bilan précédent,
// → vers le suivant. On écoute la fenêtre parce que la barre n'a pas le focus ;
// une saisie en cours garde ses flèches pour elle.
export default class extends Controller {
  static targets = ["previous", "following"]

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKeydown)
  }

  handleKeydown(event) {
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
    if (this.isTyping(event.target)) return

    let link
    if (event.key === "ArrowLeft") {
      link = this.hasPreviousTarget ? this.previousTarget : null
    } else if (event.key === "ArrowRight") {
      link = this.hasFollowingTarget ? this.followingTarget : null
    } else {
      return
    }

    if (!link) return

    event.preventDefault()
    link.click()
  }

  isTyping(element) {
    if (!element) return false
    if (element.isContentEditable) return true

    return ["INPUT", "TEXTAREA", "SELECT"].includes(element.tagName)
  }
}
