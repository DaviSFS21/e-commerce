class ProductsController < ApplicationController
  def index
    @categories = Category.asc(:name).to_a
    @category = params[:slug] ? Category.find_by(slug: params[:slug]) : @categories.first

    return render :empty if @category.nil?

    @facets = ProductFacets.new(category: @category).call
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

    price = ProductFacets.price_condition(params[:bucket])
    price ? scope.where(price) : scope
  end
end
