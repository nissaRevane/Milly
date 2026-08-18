# Les graphiques de Milly sont du SVG rendu par le serveur.
#
# Ce n'est pas un choix par défaut : la CSP de l'application interdit les scripts inline
# (voir config/initializers/content_security_policy.rb), les données sont déjà chargées au
# moment du rendu, et une infobulle native <title> suffit à lire un point. Une bibliothèque
# de graphiques imposerait un CDN et un re-rendu à gérer sur chaque navigation Turbo, pour
# des courbes que le serveur sait dessiner lui-même.
#
# Une seule chose échappe au serveur : masquer une catégorie du miroir à la demande. Le
# contrôleur Stimulus chart_series refait alors la pile sans elle et redéploie l'échelle sur
# ce qui reste — grille, axe et bandes (voir #chart_series_data). C'est le seul JavaScript
# de tous ces graphiques, et il ne connaît aucune constante du repère : elles lui arrivent
# du serveur, qui reste seul à les tenir.
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

  # Le miroir est plus haut que les autres : il empile deux piles de part et d'autre de son
  # axe, et c'est la hauteur — pas la largeur — qui laisse lire une variation de quelques
  # milliers d'euros sur une pile qui en pèse un million. Le SVG gardant le rapport de son
  # viewBox, une hauteur ne s'obtient pas en CSS : elle se prend ici, dans le repère.
  MIRROR_HEIGHT = 500

  # Le nombre de lignes horizontales, graduations comprises : 4 lignes, donc 3 intervalles.
  GRID_LINE_COUNT = 4

  # De combien l'étiquette d'une graduation descend sous son trait, pour tomber à hauteur
  # de regard plutôt que sur la ligne.
  GRID_LABEL_OFFSET = 4

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

  # Le miroir du tableau de bord : les actifs empilés au-dessus de l'axe des abscisses, la
  # dette empilée en dessous, tête en bas. +dates+ donne l'axe, +up_series+ et +down_series+
  # sont des listes de BalanceSheet::BreakdownSeries.
  #
  # Deux graphiques côte à côte laissaient le rapprochement à l'œil du lecteur, chacun avec
  # sa propre échelle. Ici les deux côtés partagent une seule échelle — sans quoi une bande
  # deux fois plus haute ne vaudrait pas deux fois plus d'argent — et l'écart entre les deux
  # fronts se lit directement : c'est le patrimoine net.
  #
  # L'ordre de chaque liste est celui de l'empilement en partant de l'axe, et vient du modèle
  # où il est figé : une catégorie qui changerait de rang d'un bilan à l'autre ferait onduler
  # la courbe pour une raison qui n'est pas dans les chiffres.
  #
  # +legend+ est rendu À CÔTÉ du graphique, dans le même bloc, parce que sa mise en page
  # dépend d'un chiffre que seul ce helper connaît : la hauteur à laquelle tombe l'axe. Elle
  # sort en --axis-share, et le CSS s'en sert pour poser la légende des actifs au-dessus de
  # l'axe et celle de la dette en dessous, chacune en face de ses bandes.
  #
  # Ce même bloc porte le contrôleur Stimulus qui masque une catégorie au clic sur sa
  # pastille : la légende commande les bandes, les deux doivent donc tenir sous une racine
  # commune. Sans légende, il n'y a rien à cliquer et le graphique sort nu.
  def mirrored_area_chart(dates, up_series, down_series, legend: nil)
    return if dates.empty?

    peak = stack_peak(dates, up_series)
    depth = stack_peak(dates, down_series)
    return if peak <= 0 && depth <= 0

    low, high, step = mirrored_scale(-depth, peak)
    height = MIRROR_HEIGHT
    # Un seul bilan ne dessine pas d'aire : sa valeur est reportée aux deux bords du cadre,
    # ce qui donne une bande à plat — la composition du jour, sans histoire à raconter.
    single = dates.size == 1
    xs = single ? [CHART_PADDING[:left], CHART_WIDTH - CHART_PADDING[:right]] : dates.each_index.map { |index| chart_x(index, dates.size) }

    chart = chart_svg(class: "chart chart-area-mirror", height: height) do
      safe_join([
        # La grille tient dans un groupe : masquer une catégorie redéploie l'échelle sur ce
        # qui reste, donc change le NOMBRE de graduations, et le contrôleur remplace le
        # contenu de ce groupe en bloc plutôt que d'y retoucher des lignes une à une.
        tag.g(chart_grid_at(grid_values(low, high, step), low, high, height),
              data: { chart_series_target: "grid" }),
        safe_join(stacked_bands(up_series, xs, low, high, height: height, single: single, sign: 1)),
        safe_join(stacked_bands(down_series, xs, low, high, height: height, single: single, sign: -1)),
        # L'axe passe APRÈS les bandes : tracé avec la grille, il disparaîtrait sous la
        # première d'entre elles, et c'est précisément la ligne que l'œil doit trouver.
        chart_axis_rule(low, high, height),
        chart_x_labels(dates, single ? [CHART_PADDING[:left] + plot_width / 2.0] : xs, height)
      ])
    end
    return chart if legend.nil?

    tag.div(class: "chart-with-legend", data: chart_series_data(xs, low, high, step, height)) do
      safe_join([
        tag.div(chart, class: "chart-with-legend-plot"),
        tag.div(legend, class: "chart-legend-columns",
                        data: { chart_series_target: "legend" },
                        style: "--axis-share: #{coord(chart_y(0, low, high, height) / height * 100)}%")
      ])
    end
  end

  # La légende d'une aire empilée. Les montants sont ceux du DERNIER bilan : la légende dit
  # où l'on en est, la courbe raconte comment on y est arrivé. Une catégorie retombée à zéro
  # y reste listée — sa bande est encore visible à gauche du graphique, et sa couleur doit
  # pouvoir se lire quelque part.
  #
  # +series+ arrive dans l'ordre d'empilement, en partant de l'axe ; la légende, elle, se lit
  # de haut en bas. Les deux coïncident sous l'axe et s'inversent au-dessus — d'où +reverse+,
  # que la pile des actifs active pour que chaque ligne tombe en face de sa bande.
  def stacked_area_legend(series, reverse: false)
    total = series.sum { |serie| serie.values.last.to_f }
    return if total <= 0

    ordered = reverse ? series.reverse : series
    chart_legend(ordered.map { |serie|
      { key: serie.key, label: serie.label, sublabel: serie.sublabel, full_label: serie.full_label,
        amount: serie.values.last, tone: series_tone(serie.key) }
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

  # +height+ est un mot-clé nommé parmi les autres attributs, d'où le **options : un
  # chart_svg(class: "…") sans accolades doit continuer à passer par là intact.
  def chart_svg(height: CHART_HEIGHT, **options, &block)
    tag.svg(**options, "viewBox" => "0 0 #{CHART_WIDTH} #{height}", role: "img", &block)
  end

  def plot_width
    CHART_WIDTH - CHART_PADDING[:left] - CHART_PADDING[:right]
  end

  def plot_height(height = CHART_HEIGHT)
    height - CHART_PADDING[:top] - CHART_PADDING[:bottom]
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

  def chart_y(value, low, high, height = CHART_HEIGHT)
    span = (high - low).to_f
    return height - CHART_PADDING[:bottom] if span.zero?

    height - CHART_PADDING[:bottom] - (value - low) / span * plot_height(height)
  end

  def chart_grid(low, high)
    values = (0...GRID_LINE_COUNT).map { |index| low + (high - low) * index / (GRID_LINE_COUNT - 1).to_f }

    chart_grid_at(values, low, high)
  end

  # La grille tracée à des montants choisis plutôt qu'à intervalles réguliers entre les
  # bornes.
  def chart_grid_at(values, low, high, height = CHART_HEIGHT)
    safe_join(values.map { |value|
      y = chart_y(value, low, high, height)

      safe_join([
        tag.line(class: "chart-grid-line",
                 x1: CHART_PADDING[:left], y1: coord(y),
                 x2: CHART_WIDTH - CHART_PADDING[:right], y2: coord(y)),
        tag.text(number_to_currency(value, precision: 0),
                 class: "chart-axis-label",
                 x: CHART_PADDING[:left] - 8, y: coord(y + GRID_LABEL_OFFSET),
                 "text-anchor" => "end")
      ])
    })
  end

  # La ligne de flottaison du miroir : ce qu'on possède au-dessus, ce qu'on doit en dessous.
  # Elle n'est pas une graduation parmi d'autres, et se dessine donc à part de la grille.
  def chart_axis_rule(low, high, height)
    y = coord(chart_y(0, low, high, height))

    tag.line(class: "chart-axis-rule",
             x1: CHART_PADDING[:left], y1: y,
             x2: CHART_WIDTH - CHART_PADDING[:right], y2: y,
             data: { chart_series_target: "axis" })
  end

  # Le sommet d'une pile : le plus grand total sur l'ensemble des bilans, et non la plus
  # grande bande — c'est la somme empilée qui doit tenir dans le cadre.
  def stack_peak(dates, series)
    return 0.0 if series.empty?

    dates.each_index.map { |index| series.sum { |serie| serie.values[index].to_f } }.max
  end

  # Les bandes d'une pile, de l'axe vers l'extérieur. +sign+ vaut 1 pour l'actif et -1 pour
  # la dette, qui s'empile donc vers le bas : c'est la seule différence entre les deux côtés.
  # Chaque bande emporte ses montants et son côté : masquer une catégorie ne fait pas
  # disparaître un trou dans la pile, il faut rapprocher de l'axe toutes celles qui étaient
  # au-dessus d'elle — donc refaire ici, dans le navigateur, l'empilement de cette boucle.
  # Les montants sont ceux du TRACÉ, déjà recopiés aux deux bords dans le cas +single+ : le
  # contrôleur ignore ainsi tout du cas particulier.
  def stacked_bands(series, xs, low, high, height:, single:, sign:)
    edge = Array.new(xs.size, 0.0)

    series.map do |serie|
      values = single ? Array.new(xs.size, serie.values.first.to_f) : serie.values.map(&:to_f)
      far = values.each_with_index.map { |value, index| edge[index] + sign * value }
      band = tag.path(class: "chart-series-area #{series_tone(serie.key)}",
                      d: band_path(xs, edge, far, low, high, height),
                      data: { chart_series_target: "band", series: serie.key,
                              sign: sign, values: values.to_json }) { tag.title(serie.full_label) }
      edge = far
      band
    end
  end

  # Ce qu'il faut au contrôleur pour refaire le graphique sans une de ses catégories.
  #
  # Masquer une bande REDÉPLOIE l'échelle sur ce qui reste : sans quoi retirer l'immobilier
  # d'un patrimoine qu'il porte aux trois quarts laisserait les liquidités écrasées sur
  # l'axe, et le geste n'apprendrait rien. Les graduations suivent donc, en nombre comme en
  # montant — c'est tout l'intérêt du zoom.
  #
  # La légende, elle, ne bouge pas d'un chiffre : ses montants et ses parts sont ceux du
  # dernier bilan, et ils ne dépendent pas de ce qu'on regarde. Seul son axe se recale, la
  # ligne de partage de ses deux colonnes suivant celle du graphique.
  #
  # Aucune constante du repère ne part d'ici en dur : le cadre sort en ordonnées déjà
  # calculées (+top+, +bottom+), la graduation en nombre d'intervalles, et le format des
  # montants tel qu'I18n le donne au serveur. Le JavaScript n'a ainsi aucune valeur jumelle
  # à tenir à jour, et écrit ses étiquettes comme number_to_currency les écrit.
  def chart_series_data(xs, low, high, step, height)
    {
      controller: "chart-series",
      chart_series_xs_value: xs.map { |x| coord(x) }.to_json,
      chart_series_frame_value: {
        top: CHART_PADDING[:top],
        bottom: height - CHART_PADDING[:bottom],
        height: height,
        labelOffset: GRID_LABEL_OFFSET
      }.to_json,
      # L'échelle du rendu, à laquelle le cadre revient quand plus rien n'est affiché : il
      # n'y a alors aucune donnée d'où déduire un zoom, et un cadre vide vaut mieux qu'un
      # cadre faux.
      chart_series_scale_value: { low: low, high: high, step: step, intervals: GRID_LINE_COUNT - 1 }.to_json,
      chart_series_currency_value: t("number.currency.format").slice(:unit, :delimiter, :format).to_json
    }
  end

  # Les bornes du miroir, arrondies au multiple de graduation qui les englobe, et le pas
  # retenu. Zéro est forcément un multiple du pas : l'axe des abscisses tombe donc exactement
  # sur une ligne de la grille, et non entre deux — ce qui est tout l'intérêt du miroir.
  def mirrored_scale(low, high)
    step = grid_step(high - low)

    [(low / step).floor * step, (high / step).ceil * step, step]
  end

  # Un pas « rond » — 1, 2, 2,5 ou 5 fois une puissance de dix — assez grand pour que la
  # grille ne dépasse pas les GRID_LINE_COUNT intervalles visés.
  def grid_step(span)
    raw = span / (GRID_LINE_COUNT - 1).to_f
    return 1.0 if raw <= 0

    magnitude = 10**Math.log10(raw).floor
    [1, 2, 2.5, 5, 10].map { |factor| factor * magnitude }.find { |step| step >= raw }
  end

  def grid_values(low, high, step)
    ((low / step).round..(high / step).round).map { |multiple| multiple * step }
  end

  # Trois dates suffisent à situer l'axe : la première, la dernière et celle du milieu. Une
  # étiquette par bilan se chevaucherait dès la dixième clôture.
  def chart_x_labels(dates, xs, height = CHART_HEIGHT)
    indexes = [0, dates.size / 2, dates.size - 1].uniq

    safe_join(indexes.map { |index|
      tag.text(l(dates[index], format: :chart_axis),
               class: "chart-axis-label",
               x: coord(xs[index]), y: height - 8,
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
  # Les montants y sont arrondis à l'euro et les parts à l'unité : une légende dit un ordre
  # de grandeur, la précision au centime se lit dans les tableaux du bilan. Les centimes
  # coûtaient ici une largeur que la colonne n'a pas.
  #
  # Une famille qui montre PLUSIEURS de ses usages passe en titre de section, ses usages
  # listés dessous : « Immobilier » écrit une fois plutôt que trois. Seule reste à part la
  # famille qui n'en montre qu'un — un titre pour une seule ligne n'apprendrait rien, et son
  # usage se met alors sous elle (voir #legend_item).
  def chart_legend(items, total)
    tag.ul(class: "chart-legend") do
      safe_join(legend_groups(items).map { |group|
        next legend_item(group.first, total) if group.one?

        tag.li(class: "chart-legend-group") do
          safe_join([
            tag.span(group.first[:label], class: "chart-legend-group-title"),
            tag.ul(class: "chart-legend-sublist") do
              safe_join(group.map { |item| legend_item(item, total, under_title: true) })
            end
          ])
        end
      })
    end
  end

  # Les entrées regroupées par famille. Le découpage se fait sur des voisins — jamais sur un
  # tri — parce que l'ordre de la légende est celui des bandes : regrouper deux usages séparés
  # par une autre catégorie les décrocherait de la pile qu'ils nomment. Le modèle range déjà
  # les usages d'une même famille côte à côte, dans les deux sens de lecture.
  def legend_groups(items)
    items.chunk_while { |before, after|
      before[:sublabel] && after[:sublabel] && before[:label] == after[:label]
    }
  end

  # +key+ marque une entrée qui commande une bande : elle seule se laisse basculer. La
  # légende de l'anneau n'en a pas, et reste une simple liste.
  def legend_item(item, total, under_title: false)
    tag.li(class: "chart-legend-item",
           data: item[:key] && { chart_series_target: "item", series: item[:key] }) do
      safe_join([
        legend_swatch(item),
        tag.span(legend_label(item, under_title), class: "chart-legend-label"),
        tag.span(number_to_currency(item[:amount], precision: 0), class: "chart-legend-amount"),
        tag.span(number_to_percentage(item[:amount].to_f / total * 100, precision: 0),
                 class: "chart-legend-share")
      ])
    end
  end

  # La pastille de couleur devient un BOUTON dès qu'elle commande une bande : cliquer dessus
  # retire la catégorie du graphique, recliquer la remet. Un bouton, et non un carré muni
  # d'un écouteur : le clavier l'atteint, aria-pressed dit dans quel état il se trouve, et
  # son nom accessible porte le libellé complet, la pastille n'ayant aucun texte à elle.
  def legend_swatch(item)
    classes = "chart-legend-swatch #{item[:tone]}"
    return tag.span(class: classes) if item[:key].nil?

    tag.button(type: "button", class: classes,
               "aria-pressed" => "true",
               "aria-label" => t("views.shared.toggle_series", label: item[:full_label] || item[:label]),
               data: { action: "chart-series#toggle" })
  end

  # Sous un titre de section, la famille est déjà écrite : il ne reste que l'usage. Hors
  # section, les deux tiennent sur deux lignes courtes — l'espace n'y est pas décoratif, la
  # sous-catégorie est un bloc donc invisible à l'écran, mais sans lui le texte accessible
  # dirait « ImmobilierLocatif ».
  def legend_label(item, under_title)
    return item[:sublabel] if under_title

    safe_join([
      item[:label],
      item[:sublabel] && tag.span(item[:sublabel], class: "chart-legend-sublabel")
    ].compact, " ")
  end

  # Le contour d'une bande : le bord extérieur de gauche à droite, puis le bord intérieur en
  # sens inverse pour refermer le polygone. Les deux bords sont des montants quelconques,
  # +low+ et +high+ étant les bornes de l'échelle — sous l'axe, +far+ est plus bas que +near+.
  def band_path(xs, near, far, low, high, height)
    outer = xs.each_with_index.map { |x, index|
      "#{index.zero? ? 'M' : 'L'} #{coord(x)} #{coord(chart_y(far[index], low, high, height))}"
    }
    inner = xs.each_with_index.reverse_each.map { |x, index|
      "L #{coord(x)} #{coord(chart_y(near[index], low, high, height))}"
    }

    (outer + inner + ["Z"]).join(" ")
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
