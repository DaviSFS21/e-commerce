module Catalog
  # The catalogue as data.
  #
  # Lives in lib/ rather than in db/seeds.rb so that the aggregation specs
  # (checkpoint 7) can assert facet counts against exactly the same data that
  # `rails db:seed` loads, instead of duplicating the numbers.
  #
  # The three categories deliberately have nothing in common: a laptop has a
  # screen size, a wine has a vintage, a running shoe has a heel drop. All of
  # them live in one `products` collection.
  #
  # Note on spec keys: FieldSpec validates them against /\A[a-z0-9_]+\z/, so
  # they are snake_case and unaccented. The *values* are free.
  module Blueprint
    CATEGORIES = [
      {
        name: "Notebooks",
        slug: "notebooks",
        field_specs: [
          { key: "tela_polegadas",   label: "Tela",         kind: "number",  required: true,  unit: '"' },
          { key: "ram_gb",           label: "Memória RAM",  kind: "number",  required: true,  unit: "GB" },
          { key: "armazenamento_gb", label: "Armazenamento", kind: "number", required: true,  unit: "GB" },
          { key: "touchscreen",      label: "Touchscreen",  kind: "boolean", required: true },
          { key: "cpu",              label: "Processador",  kind: "string",  required: false }
        ],
        products: [
          { name: "ThinkPad X1 Carbon", brand: "Lenovo",    price: "8999.00",  specs: { "tela_polegadas" => 14.0, "ram_gb" => 16, "armazenamento_gb" => 512,  "touchscreen" => false, "cpu" => "Core Ultra 7" } },
          { name: "IdeaPad 3 15",       brand: "Lenovo",    price: "2499.00",  specs: { "tela_polegadas" => 15.6, "ram_gb" => 8,  "armazenamento_gb" => 256,  "touchscreen" => false, "cpu" => "Ryzen 5" } },
          { name: "Legion 5 Pro",       brand: "Lenovo",    price: "6499.00",  specs: { "tela_polegadas" => 16.0, "ram_gb" => 32, "armazenamento_gb" => 1024, "touchscreen" => false, "cpu" => "Ryzen 7" } },
          { name: "MacBook Air 13",     brand: "Apple",     price: "7999.00",  specs: { "tela_polegadas" => 13.6, "ram_gb" => 16, "armazenamento_gb" => 512,  "touchscreen" => false, "cpu" => "M4" } },
          { name: "MacBook Pro 14",     brand: "Apple",     price: "14999.00", specs: { "tela_polegadas" => 14.2, "ram_gb" => 32, "armazenamento_gb" => 1024, "touchscreen" => false, "cpu" => "M4 Pro" } },
          { name: "XPS 13",             brand: "Dell",      price: "9499.00",  specs: { "tela_polegadas" => 13.4, "ram_gb" => 16, "armazenamento_gb" => 512,  "touchscreen" => true,  "cpu" => "Core Ultra 5" } },
          { name: "Inspiron 15",        brand: "Dell",      price: "3299.00",  specs: { "tela_polegadas" => 15.6, "ram_gb" => 8,  "armazenamento_gb" => 512,  "touchscreen" => true,  "cpu" => "Core i5" } },
          { name: "Vivobook 14",        brand: "Asus",      price: "2899.00",  specs: { "tela_polegadas" => 14.0, "ram_gb" => 8,  "armazenamento_gb" => 256,  "touchscreen" => false, "cpu" => "Core i3" } },
          { name: "ROG Zephyrus G16",   brand: "Asus",      price: "11999.00", specs: { "tela_polegadas" => 16.0, "ram_gb" => 32, "armazenamento_gb" => 2048, "touchscreen" => false, "cpu" => "Ryzen 9" } },
          { name: "Framework 13",       brand: "Framework", price: "7499.00",  specs: { "tela_polegadas" => 13.5, "ram_gb" => 16, "armazenamento_gb" => 1024, "touchscreen" => false } }
        ]
      },
      {
        name: "Vinhos",
        slug: "vinhos",
        field_specs: [
          { key: "safra",          label: "Safra",          kind: "number",  required: true },
          { key: "teor_alcoolico", label: "Teor alcoólico", kind: "number",  required: true, unit: "%" },
          { key: "uva",            label: "Uva",            kind: "string",  required: true },
          { key: "pais",           label: "País",           kind: "string",  required: true },
          { key: "organico",       label: "Orgânico",       kind: "boolean", required: true }
        ],
        products: [
          { name: "Catena Alta Malbec",      brand: "Catena Zapata", price: "289.90", specs: { "safra" => 2019, "teor_alcoolico" => 13.9, "uva" => "Malbec",             "pais" => "Argentina",      "organico" => false } },
          { name: "Catena Cabernet",         brand: "Catena Zapata", price: "189.90", specs: { "safra" => 2021, "teor_alcoolico" => 13.5, "uva" => "Cabernet Sauvignon", "pais" => "Argentina",      "organico" => false } },
          { name: "Lote 43",                 brand: "Miolo",         price: "349.00", specs: { "safra" => 2018, "teor_alcoolico" => 14.2, "uva" => "Merlot",             "pais" => "Brasil",         "organico" => false } },
          { name: "Miolo Reserva Chardonnay", brand: "Miolo",        price: "89.90",  specs: { "safra" => 2023, "teor_alcoolico" => 12.5, "uva" => "Chardonnay",         "pais" => "Brasil",         "organico" => true } },
          { name: "Casillero Reserva",       brand: "Concha y Toro", price: "64.90",  specs: { "safra" => 2022, "teor_alcoolico" => 13.0, "uva" => "Cabernet Sauvignon", "pais" => "Chile",          "organico" => false } },
          { name: "Marques de Casa Concha",  brand: "Concha y Toro", price: "219.00", specs: { "safra" => 2020, "teor_alcoolico" => 14.0, "uva" => "Carmenere",          "pais" => "Chile",          "organico" => false } },
          { name: "Talento",                 brand: "Salton",        price: "129.90", specs: { "safra" => 2020, "teor_alcoolico" => 13.5, "uva" => "Tannat",             "pais" => "Brasil",         "organico" => true } },
          { name: "Salton Intenso",          brand: "Salton",        price: "54.90",  specs: { "safra" => 2023, "teor_alcoolico" => 12.0, "uva" => "Merlot",             "pais" => "Brasil",         "organico" => false } },
          { name: "Marlborough Sauvignon",   brand: "Cloudy Bay",    price: "399.00", specs: { "safra" => 2023, "teor_alcoolico" => 13.0, "uva" => "Sauvignon Blanc",    "pais" => "Nova Zelândia",  "organico" => true } },
          { name: "Pinot Noir Estate",       brand: "Cloudy Bay",    price: "529.00", specs: { "safra" => 2021, "teor_alcoolico" => 13.5, "uva" => "Pinot Noir",         "pais" => "Nova Zelândia",  "organico" => true } }
        ]
      },
      {
        name: "Tênis de corrida",
        slug: "tenis-de-corrida",
        field_specs: [
          { key: "tamanho_eu",  label: "Tamanho (EU)",  kind: "number",  required: true },
          { key: "drop_mm",     label: "Drop",          kind: "number",  required: true, unit: "mm" },
          { key: "peso_g",      label: "Peso",          kind: "number",  required: true, unit: "g" },
          { key: "impermeavel", label: "Impermeável",   kind: "boolean", required: true },
          { key: "superficie",  label: "Superfície",    kind: "string",  required: true }
        ],
        products: [
          { name: "Pegasus 41",        brand: "Nike",      price: "799.90",  specs: { "tamanho_eu" => 42, "drop_mm" => 10, "peso_g" => 286, "impermeavel" => false, "superficie" => "asfalto" } },
          { name: "Vaporfly 3",        brand: "Nike",      price: "1899.90", specs: { "tamanho_eu" => 43, "drop_mm" => 8,  "peso_g" => 196, "impermeavel" => false, "superficie" => "asfalto" } },
          { name: "Adizero Boston 12", brand: "Adidas",    price: "1099.00", specs: { "tamanho_eu" => 42, "drop_mm" => 6,  "peso_g" => 232, "impermeavel" => false, "superficie" => "asfalto" } },
          { name: "Terrex Agravic",    brand: "Adidas",    price: "1299.00", specs: { "tamanho_eu" => 44, "drop_mm" => 8,  "peso_g" => 310, "impermeavel" => true,  "superficie" => "trilha" } },
          { name: "Gel-Kayano 31",     brand: "Asics",     price: "1199.00", specs: { "tamanho_eu" => 41, "drop_mm" => 10, "peso_g" => 298, "impermeavel" => false, "superficie" => "asfalto" } },
          { name: "Gel-Trabuco 12",    brand: "Asics",     price: "949.00",  specs: { "tamanho_eu" => 43, "drop_mm" => 8,  "peso_g" => 306, "impermeavel" => true,  "superficie" => "trilha" } },
          { name: "Ghost 16",          brand: "Brooks",    price: "899.00",  specs: { "tamanho_eu" => 42, "drop_mm" => 12, "peso_g" => 275, "impermeavel" => false, "superficie" => "asfalto" } },
          { name: "Cascadia 18",       brand: "Brooks",    price: "1049.00", specs: { "tamanho_eu" => 45, "drop_mm" => 8,  "peso_g" => 295, "impermeavel" => true,  "superficie" => "trilha" } },
          { name: "Corre 3",           brand: "Olympikus", price: "349.90",  specs: { "tamanho_eu" => 40, "drop_mm" => 10, "peso_g" => 268, "impermeavel" => false, "superficie" => "asfalto" } },
          # drop_mm == 0 on purpose: zero is a legitimate value, and the
          # validator must not treat it as "not informed" (same trap as false).
          { name: "Grafite 2",         brand: "Olympikus", price: "599.90",  specs: { "tamanho_eu" => 42, "drop_mm" => 0,  "peso_g" => 214, "impermeavel" => false, "superficie" => "asfalto" } }
        ]
      }
    ].freeze

    module_function

    # Idempotent: wipes the catalogue and rebuilds it. Running it twice must
    # leave the same 30 products, otherwise the facet counts in checkpoint 7
    # would drift every time seeds are reloaded.
    def load!
      Product.delete_all
      Category.delete_all

      CATEGORIES.each do |definition|
        category = Category.create!(
          name: definition[:name],
          slug: definition[:slug],
          field_specs: definition[:field_specs].map { |attrs| FieldSpec.new(**attrs) }
        )

        definition[:products].each_with_index do |attrs, index|
          Product.create!(
            name: attrs[:name],
            brand: attrs[:brand],
            price: BigDecimal(attrs[:price]),
            in_stock: index != 9, # one out-of-stock product per category
            category: category,
            specs: attrs[:specs],
            images: [
              Image.new(url: "https://picsum.photos/seed/#{definition[:slug]}-#{index}/600/400",
                        alt: attrs[:name], position: 0)
            ]
          )
        end
      end

      { categories: Category.count, products: Product.count }
    end
  end
end
