class FieldSpec
  include Mongoid::Document

  embedded_in :category

  field :key,      type: String
  field :label,    type: String
  field :kind,     type: String
  field :required, type: Mongoid::Boolean, default: false
  field :unit,     type: String

  KINDS = %w[string number boolean].freeze

  validates :key,   presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :label, presence: true
  validates :kind,  presence: true, inclusion: { in: KINDS }

  def matches?(value)
    case kind
    when "string"  then value.is_a?(String)
    when "number"  then value.is_a?(Numeric)
    when "boolean" then value == true || value == false
    else false
    end
  end

  def supplied?(value)
    return false if value.nil?
    return false if value.is_a?(String) && value.strip.empty?

    true
  end
end
