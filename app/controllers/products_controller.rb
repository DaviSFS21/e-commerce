class ProductsController < ApplicationController
  def index
    @categories = Category.asc(:name).to_a
    @category = params[:slug] ? Category.find_by(slug: params[:slug]) : @categories.first

    return render :empty if @category.nil?

    @facets = ProductFacets.new(category: @category).call
    @min_price = decimal_param(:min) || @facets.min_price
    @max_price = decimal_param(:max) || @facets.max_price
    @products = filtered_products.asc(:price).to_a
  end

  def show
    @product = Product.find(params[:id])
    @category = @product.category
  end

  private

  # The facet counts are computed over the whole category, not over the current
  # filter: selecting "Apple" must not collapse the brand list to Apple alone.
  def filtered_products
    scope = Product.where(category_id: @category.id)
    scope = scope.where(brand: params[:brand]) if params[:brand].present?

    min = decimal_param(:min)
    max = decimal_param(:max)
    scope = scope.gte(price: min) if min
    scope = scope.lte(price: max) if max
    scope
  end

  # Params arrive as strings and may be anything; a bad value filters nothing
  # rather than raising.
  def decimal_param(key)
    raw = params[key]
    return nil if raw.blank?

    BigDecimal(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
