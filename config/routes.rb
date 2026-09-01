Rails.application.routes.draw do
  root "products#index"

  # Category#slug is the URL segment; the listing is always scoped to one category.
  get "catalogo/:slug", to: "products#index", as: :category_products
  resources :products, only: [ :show ], path: "produtos"

  get "up" => "rails/health#show", as: :rails_health_check
end
