class Category
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :slug, type: String

  has_many :products
  embeds_many :field_specs

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  index({ slug: 1 }, { unique: true, name: "category_slug_unique" })
end
