class Product
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :brand, type: String
  field :price, type: BigDecimal
  field :in_stock, type: Mongoid::Boolean, default: true
  field :specs, type: Hash, default: -> { {} }

  belongs_to :category

  validates :name, presence: true
  validates :brand, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
