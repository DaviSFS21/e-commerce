class ProductFacets
  PRICE_BOUNDARIES = [ 0, 1000, 2500, 5000, 10_000 ].map { BigDecimal(_1.to_s) }.freeze
  OVERFLOW_KEY = "acima".freeze

  Bucket = Struct.new(:key, :label, :count, keyword_init: true)
  Result = Struct.new(:total, :brands, :price_buckets, :min_price, :max_price, keyword_init: true)

  # Translates a bucket key from the sidebar back into a price range, so the
  # listing and the facet counts agree on what a bucket means.
  def self.price_condition(bucket_key)
    return nil if bucket_key.blank?
    return { :price.gte => PRICE_BOUNDARIES.last } if bucket_key == OVERFLOW_KEY

    lower = PRICE_BOUNDARIES.find { |b| b.to_s == bucket_key.to_s }
    return nil if lower.nil?

    upper = PRICE_BOUNDARIES[PRICE_BOUNDARIES.index(lower) + 1]
    upper ? { :price.gte => lower, :price.lt => upper } : { :price.gte => lower }
  end

  def initialize(category:)
    @category = category
  end

  def call
    raw = Product.collection.aggregate(pipeline).first || {}

    Result.new(
      total:         raw.dig("total", 0, "value").to_i,
      brands:        brand_buckets(raw["brands"]),
      price_buckets: price_buckets(raw["price_buckets"]),
      min_price:     raw.dig("price_range", 0, "min"),
      max_price:     raw.dig("price_range", 0, "max")
    )
  end

  # The $match is the FIRST stage of the outer pipeline, not a stage inside one
  # sub-pipeline: every facet has to see the same filtered documents.
  def pipeline
    [
      { "$match" => { "category_id" => @category.id } },
      { "$facet" => {
          "brands" => [ { "$sortByCount" => "$brand" } ],
          "price_buckets" => [
            { "$bucket" => {
                "groupBy" => "$price",
                "boundaries" => PRICE_BOUNDARIES,
                "default" => OVERFLOW_KEY,
                "output" => { "count" => { "$sum" => 1 } }
            } }
          ],
          "price_range" => [
            { "$group" => { "_id" => nil,
                            "min" => { "$min" => "$price" },
                            "max" => { "$max" => "$price" } } }
          ],
          "total" => [ { "$count" => "value" } ]
      } }
    ]
  end

  private

  def brand_buckets(rows)
    Array(rows).map { |row| Bucket.new(key: row["_id"], label: row["_id"], count: row["count"]) }
  end

  def price_buckets(rows)
    Array(rows).map do |row|
      lower = row["_id"]

      if lower == OVERFLOW_KEY
        Bucket.new(key: OVERFLOW_KEY, label: "#{money(PRICE_BOUNDARIES.last)} +", count: row["count"])
      else
        upper = PRICE_BOUNDARIES[PRICE_BOUNDARIES.index(lower).to_i + 1]
        Bucket.new(key: lower.to_s, label: "#{money(lower)} – #{money(upper)}", count: row["count"])
      end
    end
  end

  def money(amount)
    ActiveSupport::NumberHelper.number_to_currency(
      amount, unit: "R$ ", separator: ",", delimiter: ".", precision: 0
    )
  end
end
