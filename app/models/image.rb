class Image
  include Mongoid::Document
  include Mongoid::Timestamps

  embedded_in :product

  field :url, type: String
  field :alt, type: String
  field :position, type: Integer

  validates :url, presence: true
end
