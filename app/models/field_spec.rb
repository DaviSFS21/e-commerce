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
end
