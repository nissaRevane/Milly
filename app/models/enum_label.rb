module EnumLabel
  # Looks up the French label for an enum value under views.shared.<scope>.
  # Blank-guarded: an interpolated blank key would otherwise make I18n resolve
  # the parent node and return the whole translations hash.
  def self.for(scope, value)
    return "" if value.blank?

    I18n.t("views.shared.#{scope}.#{value}", default: value.to_s)
  end
end
