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
  validate  :specs_match_category

  index({ category_id: 1, price: 1 }, { name: "category_price" })
  index({ "specs.$**" => 1 }, { name: "specs" })
  index({ name: "text", brand: "text" }, { name: "name_brand" })

  private

  def specs_match_category
    return if category.blank?

    category_specs = category.field_specs.index_by(&:key)
    required = category_specs.values.select(&:required?).map(&:key)

    specs.each do |key, value|
      spec = category_specs[key]

      if spec.nil?
        errors.add(:specs, "Atributo #{key} não está na categoria")
        next
      end

      next unless spec.supplied?(value)

      required.delete(key)

      errors.add(:specs, "Tipo do atributo #{key} deve ser #{spec.kind}") unless spec.matches?(value)
    end

    errors.add(:specs, "Atributos obrigatórios faltantes: #{required.join(', ')}") if required.any?
  end
end
