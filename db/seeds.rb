# The catalogue itself lives in lib/catalog/blueprint.rb so that the RSpec suite
# can assert aggregation results against exactly the same data loaded here.
result = Catalog::Blueprint.load!

puts "Semeado: #{result[:categories]} categorias, #{result[:products]} produtos."

Category.asc(:name).each do |category|
  puts format("  %-18s %2d produtos   specs: %s",
              category.slug,
              category.products.count,
              category.field_specs.map(&:key).join(", "))
end
