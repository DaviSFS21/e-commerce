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

  # Does the value have the declared type? Presence is not this method's
  # business -- `false` is a type-correct boolean like any other.
  def matches?(value)
    case kind
    when "string"  then value.is_a?(String)
    when "number"  then value.is_a?(Numeric)
    when "boolean" then value == true || value == false
    else false
    end
  end

  # Was a value actually informed?
  #
  # Deliberately NOT `value.blank?`. In Ruby `false.blank?` is true, so a
  # presence check would reject `touchscreen: false` -- a shoe that is not
  # waterproof, a wine that is not organic. `0.blank?` is false, but the same
  # class of bug bites anyone who reaches for `present?` here.
  #
  # Only nil and a whitespace-only string count as "not informed".
  def supplied?(value)
    return false if value.nil?
    return false if value.is_a?(String) && value.strip.empty?

    true
  end
end
