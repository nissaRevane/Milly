import { Controller } from "@hotwired/stimulus"

// Masque une catégorie du graphique miroir au clic sur sa pastille de légende, et redéploie
// l'échelle sur ce qui reste.
//
// Une aire empilée ne se cache pas en retirant une bande : les bandes au-dessus d'elle sont
// tracées à partir de son sommet, et les laisser en place ouvrirait un trou de la hauteur de
// la catégorie masquée. Il faut refaire l'empilement sans elle — et, l'échelle suivant les
// montants affichés, la grille et l'axe avec. C'est la seule raison pour laquelle ces
// graphiques ont du JavaScript (voir ChartsHelper).
//
// Ce que ce contrôleur ne recalcule PAS : les montants et les parts de la légende. Ils disent
// le dernier bilan, qui ne dépend pas de ce qu'on choisit de regarder. Seule la ligne de
// partage de ses deux colonnes suit l'axe, pour rester en face des bandes.
//
// Aucune constante du repère n'est écrite ici : le cadre, le pas de graduation et le format
// des montants viennent du serveur (ChartsHelper#chart_series_data), qui reste seul à les
// connaître.
export default class extends Controller {
  static targets = ["band", "item", "grid", "axis", "legend"]
  static values = { xs: Array, frame: Object, scale: Object, currency: Object }

  // Le serveur a déjà écrit une graduation dans la forme voulue : on garde une ligne et une
  // étiquette comme gabarits et on les clone, plutôt que de redire ici leurs classes, leurs
  // abscisses et leur ancrage.
  connect() {
    this.ruleTemplate = this.gridTarget.querySelector("line").cloneNode()
    this.labelTemplate = this.gridTarget.querySelector("text").cloneNode()
    // Turbo peut restituer depuis son cache un graphique dont des catégories étaient
    // masquées : les boutons reviennent alors relâchés, et c'est d'eux que l'état se relit.
    // Rien à faire quand tout est visible — le serveur a déjà tracé ce graphique-là.
    if (this.hiddenKeys.size > 0) this.draw()
  }

  toggle(event) {
    const button = event.currentTarget
    button.setAttribute("aria-pressed", button.getAttribute("aria-pressed") === "true" ? "false" : "true")
    this.draw()
  }

  draw() {
    const hidden = this.hiddenKeys
    const shown = (sign) => this.bandsFor(sign).filter((band) => !hidden.has(band.dataset.series))
    const scale = this.scaleFor(shown("1"), shown("-1"))

    this.drawGrid(scale)
    this.drawAxis(scale)
    this.stack("1", hidden, scale)
    this.stack("-1", hidden, scale)

    for (const item of this.itemTargets) {
      item.classList.toggle("chart-legend-item-off", hidden.has(item.dataset.series))
    }
  }

  // Une pile, de l'axe vers l'extérieur, dans l'ordre du DOM — celui que le serveur a figé.
  stack(sign, hidden, scale) {
    let near = this.xsValue.map(() => 0)

    for (const band of this.bandsFor(sign)) {
      // Un `d` vide n'efface pas seulement la bande : il la retire aussi des cibles du
      // pointeur, donc son infobulle avec elle. Et l'empilement continue sans elle : les
      // suivantes repartent du bord où celle-ci s'arrêtait.
      if (hidden.has(band.dataset.series)) {
        band.setAttribute("d", "")
        continue
      }

      const values = this.valuesOf(band)
      const far = near.map((edge, index) => edge + Number(sign) * values[index])
      band.setAttribute("d", this.bandPath(near, far, scale))
      near = far
    }
  }

  // Les bornes du miroir, arrondies au multiple de graduation qui les englobe
  // (ChartsHelper#mirrored_scale). Zéro reste un multiple du pas : l'axe tombe donc sur une
  // ligne de la grille, ce qui est tout l'intérêt du miroir.
  //
  // Tout masqué : il n'y a plus aucun montant d'où déduire un zoom, et le cadre revient à
  // l'échelle du rendu plutôt que de se refermer sur rien.
  scaleFor(up, down) {
    const peak = this.peakOf(up)
    const depth = this.peakOf(down)
    if (peak <= 0 && depth <= 0) return this.scaleValue

    const step = this.gridStep(peak + depth)

    return { low: Math.floor(-depth / step) * step, high: Math.ceil(peak / step) * step, step }
  }

  // Le sommet d'une pile : le plus grand total sur l'ensemble des bilans, et non la plus
  // grande bande — c'est la somme empilée qui doit tenir dans le cadre.
  peakOf(bands) {
    if (bands.length === 0) return 0

    return Math.max(...this.xsValue.map((_, index) =>
      bands.reduce((total, band) => total + this.valuesOf(band)[index], 0)))
  }

  // Un pas « rond » — 1, 2, 2,5 ou 5 fois une puissance de dix — assez grand pour que la
  // grille ne dépasse pas le nombre d'intervalles visé (ChartsHelper#grid_step).
  gridStep(span) {
    const raw = span / this.scaleValue.intervals
    if (raw <= 0) return 1

    const magnitude = 10 ** Math.floor(Math.log10(raw))

    return [1, 2, 2.5, 5, 10].map((factor) => factor * magnitude).find((step) => step >= raw)
  }

  drawGrid({ low, high, step }) {
    const graduations = []

    for (let multiple = Math.round(low / step); multiple <= Math.round(high / step); multiple++) {
      const y = this.y(multiple * step, { low, high })
      const rule = this.ruleTemplate.cloneNode()
      rule.setAttribute("y1", this.round(y))
      rule.setAttribute("y2", this.round(y))
      const label = this.labelTemplate.cloneNode()
      label.setAttribute("y", this.round(y + this.frameValue.labelOffset))
      label.textContent = this.currency(multiple * step)
      graduations.push(rule, label)
    }

    this.gridTarget.replaceChildren(...graduations)
  }

  // L'axe, et la ligne de partage de la légende qui doit tomber avec lui : chaque colonne
  // reste ainsi en face des bandes qu'elle nomme.
  drawAxis(scale) {
    const y = this.y(0, scale)
    this.axisTarget.setAttribute("y1", this.round(y))
    this.axisTarget.setAttribute("y2", this.round(y))

    if (this.hasLegendTarget) {
      this.legendTarget.style.setProperty("--axis-share", `${this.round(y / this.frameValue.height * 100)}%`)
    }
  }

  // Le contour d'une bande : le bord extérieur de gauche à droite, puis le bord intérieur en
  // sens inverse pour refermer le polygone (ChartsHelper#band_path).
  bandPath(near, far, scale) {
    const outer = this.xsValue.map((x, index) => `${index === 0 ? "M" : "L"} ${x} ${this.round(this.y(far[index], scale))}`)
    const inner = this.xsValue.map((x, index) => `L ${x} ${this.round(this.y(near[index], scale))}`).reverse()

    return [...outer, ...inner, "Z"].join(" ")
  }

  y(value, { low, high }) {
    const span = high - low
    if (span === 0) return this.frameValue.bottom

    const { top, bottom } = this.frameValue

    return bottom - (value - low) / span * (bottom - top)
  }

  // Le montant d'une graduation, écrit comme number_to_currency l'écrit : le format, le
  // séparateur de milliers et le symbole viennent d'I18n, par le serveur. Un Intl.NumberFormat
  // rendrait un autre espace et un autre arrondi, et la grille changerait d'aspect au premier
  // clic.
  currency(value) {
    const { format, delimiter, unit } = this.currencyValue
    const digits = String(Math.round(Math.abs(value))).replace(/\B(?=(\d{3})+$)/g, delimiter)

    return format.replace("%n", (value < 0 ? "-" : "") + digits).replace("%u", unit)
  }

  bandsFor(sign) {
    return this.bandTargets.filter((band) => band.dataset.sign === sign)
  }

  valuesOf(band) {
    return JSON.parse(band.dataset.values)
  }

  get hiddenKeys() {
    return new Set(
      this.itemTargets
        .filter((item) => item.querySelector('[aria-pressed="false"]'))
        .map((item) => item.dataset.series)
    )
  }

  // Les coordonnées SVG sont arrondies au centième, comme ChartsHelper#coord.
  round(value) {
    return Math.round(value * 100) / 100
  }
}
