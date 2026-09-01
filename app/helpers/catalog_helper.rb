module CatalogHelper
  def money(amount)
    number_to_currency(amount, unit: "R$ ", separator: ",", delimiter: ".")
  end

  # Toggles the brand filter on or off, preserving the price range.
  def filter_link(slug, brand: :keep)
    query = { min: params[:min].presence, max: params[:max].presence }
    query[:brand] = brand == :keep ? params[:brand].presence : brand
    category_products_path(slug: slug, **query.compact)
  end

  # Renders a spec value using the FieldSpec's declared kind and unit, so the
  # view needs no per-category code.
  def spec_value(field_spec, value)
    return "—" unless field_spec.supplied?(value)
    return value ? "Sim" : "Não" if field_spec.kind == "boolean"

    [ value, field_spec.unit.presence ].compact.join(" ")
  end

  def spec_summary(product, limit: 3)
    product.category.field_specs
           .select { |fs| fs.supplied?(product.specs[fs.key]) }
           .first(limit)
           .map { |fs| "#{fs.label}: #{spec_value(fs, product.specs[fs.key])}" }
           .join(" · ")
  end
end
