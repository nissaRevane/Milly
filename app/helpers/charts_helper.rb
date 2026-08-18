# Les graphiques de Milly sont du SVG rendu par le serveur, sans une ligne de JavaScript.
#
# Ce n'est pas un choix par défaut : la CSP de l'application interdit les scripts inline
# (voir config/initializers/content_security_policy.rb), les données sont déjà chargées au
# moment du rendu, et une infobulle native <title> suffit à lire un point. Une bibliothèque
# de graphiques imposerait un CDN, un contrôleur Stimulus et un re-rendu à gérer sur chaque
# navigation Turbo, pour des courbes que le serveur sait dessiner lui-même.
#
# Les couleurs ne sont jamais écrites ici : chaque forme porte une classe (.chart-line-path,
# .chart-slice-3…) que application.css raccorde aux variables --chart-*. Un helper qui
# renverrait des codes hexadécimaux mettrait la palette hors de portée du CSS.
module ChartsHelper
  # Le repère de tous les graphiques cartésiens. Le SVG est tracé dans ces coordonnées puis
  # mis à l'échelle par le viewBox : la largeur réelle est celle que le CSS lui donne.
  CHART_WIDTH = 720
  CHART_HEIGHT = 240
  CHART_PADDING = { top: 14, right: 16, bottom: 26, left: 78 }.freeze

  # Le nombre de lignes horizontales, graduations comprises : 4 lignes, donc 3 intervalles.
  GRID_LINE_COUNT = 4

  DONUT_SIZE = 180
  DONUT_THICKNESS = 30

  # Le nombre de teintes de la palette (--chart-1 … --chart-6). Au-delà, les couleurs se
  # répètent : mieux vaut deux parts de la même teinte, que la légende distingue par son
  # libellé, qu'une septième couleur tirée au hasard hors du système.
  PALETTE_SIZE = 6

  # La courbe d'un montant dans le temps, un point par bilan. +series+ est une liste de
  # [date, montant] déjà triée par date croissante.
  #
  # L'échelle verticale suit les données et ne force pas le zéro : un patrimoine qui passe
  # de 300 000 à 320 000 € doit montrer ses 20 000 € de mouvement, pas une ligne plate
  # écrasée en haut d'un axe parti de zéro. Les graduations disent où l'on se trouve.
  def line_chart(series)
    return if series.empty?

    values = series.map { |(_, value)| value.to_f }
    low, high = chart_bounds(values)
    xs = series.each_index.map { |index| chart_x(index, series.size) }
    ys = values.map { |value| chart_y(value, low, high) }

    chart_svg(class: "chart chart-line") do
      safe_join([
        chart_grid(low, high),
        tag.path(class: "chart-area", d: area_path(xs, ys)),
        tag.path(class: "chart-line-path", d: line_path(xs, ys)),
        safe_join(series.each_with_index.map { |(date, value), index|
          chart_point(xs[index], ys[index], "#{l(date, format: :long)} — #{number_to_currency(value)}")
        }),
        chart_x_labels(series.map(&:first), xs)
      ])
    end
  end

  # Une aire empilée : une bande par catégorie, du bas vers le haut, dont la somme dessine
  # le total. +dates+ donne l'axe, +series+ est une liste de BalanceSheet::BreakdownSeries.
  #
  # L'ordre de +series+ est celui de l'empilement et vient du modèle, où il est figé : une
  # catégorie qui changerait de rang d'un bilan à l'autre ferait onduler la courbe pour une
  # raison qui n'est pas dans les chiffres. L'échelle part de zéro — contrairement à la
  # courbe du patrimoine net, une aire empilée n'a de sens que posée sur son socle.
  def stacked_area_chart(dates, series)
    return if dates.empty? || series.empty?

    high = dates.each_index.map { |index| series.sum { |serie| serie.values[index].to_f } }.max
    return if high <= 0

    # Un seul bilan ne dessine pas d'aire : sa valeur est reportée aux deux bords du cadre,
    # ce qui donne une bande à plat — la composition du jour, sans histoire à raconter.
    single = dates.size == 1
    xs = single ? [CHART_PADDING[:left], CHART_WIDTH - CHART_PADDING[:right]] : dates.each_index.map { |index| chart_x(index, dates.size) }
    lower = Array.new(xs.size, 0.0)

    areas = series.map do |serie|
      values = single ? Array.new(2, serie.values.first.to_f) : serie.values.map(&:to_f)
      upper = values.each_with_index.map { |value, index| lower[index] + value }
      band = tag.path(class: "chart-series-area #{series_tone(serie.key)}",
                      d: band_path(xs, lower, upper, high)) { tag.title(serie.label) }
      lower = upper
      band
    end

    chart_svg(class: "chart chart-area-stack") do
      safe_join([
        chart_grid(0, high),
        safe_join(areas),
        chart_x_labels(dates, single ? [CHART_PADDING[:left] + plot_width / 2.0] : xs)
      ])
    end
  end

  # La légende d'une aire empilée. Les montants sont ceux du DERNIER bilan : la légende dit
  # où l'on en est, la courbe raconte comment on y est arrivé. Une catégorie retombée à zéro
  # y reste listée — sa bande est encore visible à gauche du graphique, et sa couleur doit
  # pouvoir se lire quelque part.
  def stacked_area_legend(series)
    total = series.sum { |serie| serie.values.last.to_f }
    return if total <= 0

    chart_legend(series.map { |serie|
      { label: serie.label, amount: serie.values.last, tone: series_tone(serie.key) }
    }, total)
  end

  # Un anneau et sa légende. +slices+ est une liste de { label:, amount: } déjà ordonnée ;
  # les parts nulles ou négatives sont écartées — un anneau ne sait pas les dessiner, et la
  # légende ne gagne rien à lister des catégories absentes du bilan.
  #
  # L'anneau est fait de cercles en pointillés (stroke-dasharray) plutôt que d'arcs calculés
  # à la trigonométrie : une part vaut une longueur de trait, son décalage la somme des
  # précédentes, et il n'y a aucun cas limite à traiter au passage des 180°.
  def donut_chart(slices)
    slices = slices.reject { |slice| slice[:amount].to_f <= 0 }
    return if slices.empty?

    total = slices.sum { |slice| slice[:amount].to_f }
    radius = (DONUT_SIZE - DONUT_THICKNESS) / 2.0
    circumference = 2 * Math::PI * radius
    center = DONUT_SIZE / 2.0
    offset = 0.0

    ring = slices.each_with_index.map do |slice, index|
      length = slice[:amount].to_f / total * circumference
      # Les noms d'attributs à trait d'union passent en clés String : le tag builder de Rails
      # ne convertit PAS les underscores en tirets hors des data-* et aria-*, et un
      # stroke_dasharray="…" est un attribut inconnu que le navigateur ignore en silence —
      # l'anneau se dessinerait alors en un seul trait continu.
      arc = tag.circle(class: "chart-slice #{palette_class(index)}",
                       cx: center, cy: center, r: coord(radius),
                       fill: "none",
                       "stroke-width" => DONUT_THICKNESS,
                       "stroke-dasharray" => "#{coord(length)} #{coord(circumference - length)}",
                       "stroke-dashoffset" => coord(-offset)) do
        tag.title("#{slice[:label]} — #{number_to_currency(slice[:amount])}")
      end
      offset += length
      arc
    end

    tag.div(class: "chart-donut") do
      safe_join([
        tag.svg(class: "chart-donut-ring", "viewBox" => "0 0 #{DONUT_SIZE} #{DONUT_SIZE}", role: "img") do
          # La rotation d'un quart de tour fait partir la première part de midi plutôt que
          # de 3 h, où stroke-dashoffset la placerait.
          tag.g(transform: "rotate(-90 #{center} #{center})") { safe_join(ring) }
        end,
        chart_legend(slices.each_with_index.map { |slice, index|
          slice.merge(tone: palette_class(index))
        }, total)
      ])
    end
  end

  # Des barres horizontales en HTML, pour les répartitions courtes (risque, biens) où un
  # anneau serait moins lisible qu'une liste ordonnée. Chaque ligne est proportionnelle au
  # plus grand montant, pas au total : on compare les postes entre eux, pas au patrimoine.
  #
  # Chaque ligne est un { label:, amount:, tone: } ; +tone+ nomme la classe de remplissage
  # (chart-fill-risk-low…) et vaut nil pour la teinte neutre.
  # Seules les lignes à zéro disparaissent — une catégorie absente du bilan n'a rien à dire.
  # Un montant négatif reste affiché, en rouge : un bien dont la dette dépasse la valeur a une
  # valeur nette négative, et c'est précisément ce qu'il faut voir. L'échelle se prend donc sur
  # la plus grande valeur ABSOLUE, sinon une série entièrement négative n'aurait aucune barre.
  def bar_breakdown(rows)
    rows = rows.reject { |row| row[:amount].to_f.zero? }
    return if rows.empty?

    high = rows.map { |row| row[:amount].to_f.abs }.max

    tag.ul(class: "bar-breakdown") do
      safe_join(rows.map { |row|
        amount = row[:amount].to_f
        fill_class = amount.negative? ? "bar-breakdown-fill-negative" : row[:tone]

        tag.li(class: "bar-breakdown-row") do
          safe_join([
            tag.span(row[:label], class: "bar-breakdown-label"),
            tag.span(class: "bar-breakdown-track") do
              tag.span(class: "bar-breakdown-fill #{fill_class}".strip,
                       style: "width: #{coord(amount.abs / high * 100)}%")
            end,
            tag.span(number_to_currency(row[:amount]), class: "bar-breakdown-amount")
          ])
        end
      })
    end
  end

  private

  def chart_svg(options, &block)
    tag.svg(**options, "viewBox" => "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}", role: "img", &block)
  end

  def plot_width
    CHART_WIDTH - CHART_PADDING[:left] - CHART_PADDING[:right]
  end

  def plot_height
    CHART_HEIGHT - CHART_PADDING[:top] - CHART_PADDING[:bottom]
  end

  # Les bornes verticales : les données, élargies de 8 % pour que la courbe ne touche pas
  # les bords. Une série constante n'a pas d'amplitude à élargir et se verrait attribuer une
  # hauteur nulle — d'où la marge de repli, qui la place au milieu du cadre.
  def chart_bounds(values)
    low, high = values.minmax
    return [low - 1, high + 1] if low == high

    margin = (high - low) * 0.08
    [low - margin, high + margin]
  end

  def chart_x(index, count)
    return CHART_PADDING[:left] + plot_width / 2.0 if count == 1

    CHART_PADDING[:left] + index * plot_width / (count - 1).to_f
  end

  def chart_y(value, low, high)
    span = (high - low).to_f
    return CHART_HEIGHT - CHART_PADDING[:bottom] if span.zero?

    CHART_HEIGHT - CHART_PADDING[:bottom] - (value - low) / span * plot_height
  end

  def chart_grid(low, high)
    lines = (0...GRID_LINE_COUNT).map do |index|
      value = low + (high - low) * index / (GRID_LINE_COUNT - 1).to_f
      y = chart_y(value, low, high)

      safe_join([
        tag.line(class: "chart-grid-line",
                 x1: CHART_PADDING[:left], y1: coord(y),
                 x2: CHART_WIDTH - CHART_PADDING[:right], y2: coord(y)),
        tag.text(number_to_currency(value, precision: 0),
                 class: "chart-axis-label",
                 x: CHART_PADDING[:left] - 8, y: coord(y + 4),
                 "text-anchor" => "end")
      ])
    end

    safe_join(lines)
  end

  # Trois dates suffisent à situer l'axe : la première, la dernière et celle du milieu. Une
  # étiquette par bilan se chevaucherait dès la dixième clôture.
  def chart_x_labels(dates, xs)
    indexes = [0, dates.size / 2, dates.size - 1].uniq

    safe_join(indexes.map { |index|
      tag.text(l(dates[index], format: :chart_axis),
               class: "chart-axis-label",
               x: coord(xs[index]), y: CHART_HEIGHT - 8,
               "text-anchor" => anchor_for(index, dates.size))
    })
  end

  # Les étiquettes des extrémités sont ancrées vers l'intérieur, sans quoi la première
  # déborde à gauche du cadre et la dernière à droite.
  def anchor_for(index, count)
    return "start" if index.zero?
    return "end" if index == count - 1

    "middle"
  end

  def line_path(xs, ys)
    xs.each_with_index.map { |x, index| "#{index.zero? ? 'M' : 'L'} #{coord(x)} #{coord(ys[index])}" }.join(" ")
  end

  def area_path(xs, ys)
    baseline = CHART_HEIGHT - CHART_PADDING[:bottom]

    "#{line_path(xs, ys)} L #{coord(xs.last)} #{baseline} L #{coord(xs.first)} #{baseline} Z"
  end

  def chart_point(x, y, title)
    tag.circle(class: "chart-point", cx: coord(x), cy: coord(y), r: 3.5) { tag.title(title) }
  end

  # La légende partagée par l'anneau et l'aire empilée : une pastille, un libellé, un
  # montant, la part qu'il représente. +total+ est passé plutôt que redérivé, les deux
  # graphiques ne le lisant pas sur le même ensemble de montants.
  def chart_legend(items, total)
    tag.ul(class: "chart-legend") do
      safe_join(items.map { |item|
        tag.li(class: "chart-legend-item") do
          safe_join([
            tag.span(class: "chart-legend-swatch #{item[:tone]}"),
            tag.span(item[:label], class: "chart-legend-label"),
            tag.span(number_to_currency(item[:amount]), class: "chart-legend-amount"),
            tag.span(number_to_percentage(item[:amount].to_f / total * 100, precision: 1),
                     class: "chart-legend-share")
          ])
        end
      })
    end
  end

  # Le contour d'une bande : le bord haut de gauche à droite, puis le bord bas en sens
  # inverse pour refermer le polygone.
  def band_path(xs, lower, upper, high)
    top = xs.each_with_index.map { |x, index|
      "#{index.zero? ? 'M' : 'L'} #{coord(x)} #{coord(chart_y(upper[index], 0, high))}"
    }
    bottom = xs.each_with_index.reverse_each.map { |x, index|
      "L #{coord(x)} #{coord(chart_y(lower[index], 0, high))}"
    }

    (top + bottom + ["Z"]).join(" ")
  end

  # La classe qui porte la couleur d'une catégorie. Elle se déduit de la clé et non d'un
  # index : une catégorie garde ainsi sa teinte quand une autre disparaît du bilan, et
  # application.css dit noir sur blanc quelle couleur va à quel poste.
  def series_tone(key)
    "chart-series-#{key.tr('_:', '--')}"
  end

  def palette_class(index)
    "chart-palette-#{index % PALETTE_SIZE + 1}"
  end

  # Les coordonnées SVG s'écrivent avec un point décimal quelle que soit la locale : elles
  # passent par to_s et jamais par les helpers de formatage de nombres.
  def coord(value)
    value.to_f.round(2)
  end
end
