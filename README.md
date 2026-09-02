# Catálogo — Rails + MongoDB (Mongoid)

Catálogo de e-commerce construído para demonstrar modelagem em banco não-relacional:
uma coleção de documentos heterogêneos cujo formato é **definido por dado**, não por DDL.

A ideia central é esta: **cada categoria carrega o próprio schema, e os produtos são
validados contra ele no momento da escrita.** Schema-on-read não significa ausência de
validação — significa que a validação saiu do DDL do banco e passou para a aplicação,
onde o schema é ele mesmo um documento que se pode inserir. Criar uma categoria nova
não exige classe nova, coluna nova nem migration.

**Stack:** Rails 8.1 · Mongoid 9.1 · MongoDB 8 · Ruby 3.4.10
Views renderizadas no servidor. Sem API separada, sem frontend à parte.

---

## Como rodar

```bash
docker compose up -d
```

```bash
bundle install
bin/rails db:seed
bin/rails db:mongoid:create_indexes
bin/rails server
```

Conferir os índices direto no servidor:

```bash
docker exec ecommerce-mongo mongosh e_commerce_development --eval 'db.products.getIndexes()'
```

---

## Modelo de dados

```
Category                          Product
  name                              name
  slug          <-- referenciado -- category_id
  field_specs[]  (embedado)         brand
    key                             price      (Decimal128)
    label                           in_stock
    kind                            specs      (Hash livre)
    required
    unit
```

O campo do produto se chama `specs` e **não** `attributes` de propósito:
`Mongoid::Document` já define `#attributes`, e o Mongoid recusa a declaração.

Diagramas completos em [`docs/modelagem.md`](docs/modelagem.md).

### A regra de embedar versus referenciar

> **Embede o que é possuído, limitado e sempre lido junto com o pai.
> Referencie o que é compartilhado, ilimitado ou consultado por conta própria.**

| Relação | Decisão | Por quê |
|---|---|---|
| `Category embeds_many :field_specs` | **embeda** | Um field spec não significa nada fora da categoria, nunca é consultado sozinho e são poucos. Embedar faz ler a categoria — *incluindo o schema dela* — custar uma única busca de documento, e isso importa porque **toda** validação de produto lê esse schema. |
| `Product belongs_to :category` | **referencia** | Uma categoria é compartilhada por dezenas de produtos, é mutável (renomeá-la não pode reescrever todos os produtos) e é listada por conta própria. Embedar duplicaria dado mutável — a anomalia de atualização clássica. |

A verificação não foi feita pelo model, e sim descendo ao driver cru para olhar o BSON
armazenado:

```ruby
raw = Mongoid.default_client[:categories].find(_id: categoria.id).first
raw["field_specs"]                                    # => Array aninhado
Mongoid.default_client.database.collection_names       # => ["categories", "products"]
```

Não existe coleção `field_specs`. E o documento do produto tem
`category_id`, não um sub-documento `category`.

---

## Validação dirigida pelo schema da categoria

`Product#specs_match_category` lê os `field_specs` da categoria em tempo de escrita e
aplica quatro regras:

| Regra | Rejeita |
|---|---|
| Nenhuma chave não declarada | notebook com `uva` |
| Tipo tem que bater com o `kind` | `ram_gb: "dezesseis"` |
| Chave obrigatória tem que ser informada | notebook sem `ram_gb` |
| **`false` é valor, não ausência** | `touchscreen: false` tem que **passar** |

A última linha é a sutil. Em Ruby `false.blank?` é `true`, então a checagem óbvia de
presença rejeita silenciosamente todo `false` legítimo — um tênis que não é
impermeável, um vinho que não é orgânico. `0` cai na mesma armadilha com `present?`.

Por isso `FieldSpec` separa duas perguntas que parecem uma só:

```ruby
def matches?(value)   # o tipo bate?
def supplied?(value)  # foi informado?
```

`supplied?` nunca usa `blank?`: só `nil` e string em branco contam como não informado.

Criar uma categoria é um único insert:

```ruby
Category.create!(name: "Câmeras", slug: "cameras", field_specs: [
  FieldSpec.new(key: "megapixels", label: "Resolução", kind: "number", required: true, unit: "MP")
])
```

A partir daí o validador aplica o schema novo, a barra lateral ganha um bloco de filtro,
a página de detalhe renderiza o rótulo e a unidade novos, e o índice wildcard torna
`specs.megapixels` uma busca indexada. **Nenhuma linha de código mudou.**

---

## Índices

Declarados nos models, criados com `db:mongoid:create_indexes`, conferidos no mongosh:

```
products                                    categories
  _id_            {"_id":1}                   _id_                  {"_id":1}
  category_price  {"category_id":1,"price":1} category_slug_unique  {"slug":1}  UNIQUE
  specs           {"specs.$**":1}
  name_brand      {"_fts":"text","_ftsx":1}
```

- **`{ category_id: 1, price: 1 }`** — a listagem é sempre "esta categoria, nesta faixa
  de preço, do mais barato". Igualdade primeiro, faixa e ordenação depois, para um índice
  só servir o filtro **e** a ordenação sem estágio `SORT` bloqueante.
- **`{ "specs.$**": 1 }`** — ver abaixo.
- **índice de texto** em `name` + `brand`.
- **índice único** em `Category#slug`, no servidor e não só no validador `uniqueness`,
  que tem condição de corrida entre duas requisições simultâneas.

### O que o índice wildcard resolve

O ponto de um schema definido por categoria é que **ninguém sabe as chaves de antemão**.
Notebooks têm `ram_gb`, vinhos têm `uva`, e a categoria criada daqui a cinco minutos vai
ter outra coisa. Hoje a coleção já tem 15 chaves de spec distintas:

```
armazenamento_gb, cpu, drop_mm, impermeavel, organico, pais, peso_g, ram_gb,
safra, superficie, tamanho_eu, tela_polegadas, teor_alcoolico, touchscreen, uva
```

Não dá para declarar um índice por chave quando o conjunto é aberto, e declarar um para
cada chave futura não escala — cada índice é custo de escrita em toda inserção.

`{ "specs.$**": 1 }` indexa **todo** caminho sob `specs`, presente e futuro, num índice
só. O plano mostra o mecanismo:

```
keyPattern: {"$_path": 1, "specs.uva": 1}
```

O MongoDB limita `$_path` à chave consultada e varre os valores dentro dela — um índice
físico se comportando como um índice por chave, para qualquer chave.

### Antes e depois do `explain`

Listagem filtrada (uma categoria, faixa de preço), com 30 produtos na coleção:

| Métrica | Antes | Depois |
|---|---|---|
| estágio | `COLLSCAN` | `IXSCAN` → `FETCH` |
| `totalDocsExamined` | 30 | 7 |
| `totalKeysExamined` | 0 | 7 |
| `works` | 31 | 8 |
| `nReturned` | 7 | 7 |

Passou a examinar exatamente os 7 documentos que devolve, em vez dos 30 da coleção.

As demais consultas, já com os índices:

```
specs.uva = Malbec             IXSCAN  idx=specs       ret=1  docs=1   keys=1
specs.impermeavel = true       IXSCAN  idx=specs       ret=3  docs=3   keys=3
specs.ram_gb >= 16             IXSCAN  idx=specs       ret=7  docs=7   keys=7
texto: MacBook                 IXSCAN  idx=name_brand  ret=2  docs=2   keys=2
in_stock = false (sem índice)  COLLSCAN                ret=3  docs=30  keys=0
```

A última linha é o **caso de controle** e não é decorativa: sem ela, "deu IXSCAN" não
provaria nada, porque poderia ser que toda consulta desse IXSCAN. Com ela fica
demonstrado que a medição distingue os dois casos. As três primeiras usam categorias
diferentes e o **mesmo** índice `specs`.

Uma observação honesta sobre tempo: em 30 documentos o relógio não mede nada útil — a
coleção inteira cabe em memória e o próprio planejamento do plano custa mais que a
varredura. O que o `explain` prova é mudança de **classe de complexidade**: `COLLSCAN` é
O(n) no tamanho da coleção, `IXSCAN` é O(log n + k) com k = tamanho do resultado. Em 30
documentos isso é invisível; em 300 mil, é a diferença entre milissegundos e segundos.

Saída bruta completa em [`docs/index-optimization.md`](docs/index-optimization.md).

---

## Agregação: um `$facet`, uma ida ao servidor

[`ProductFacets`](app/services/product_facets.rb) monta a barra lateral inteira numa
única chamada `aggregate`:

```ruby
[ { "$match" => { "category_id" => categoria.id } },
  { "$facet" => {
      "brands"        => [ { "$sortByCount" => "$brand" } ],
      "price_buckets" => [ { "$bucket" => { "groupBy" => "$price", "boundaries" => [...],
                                            "default" => "acima",
                                            "output" => { "count" => { "$sum" => 1 } } } } ],
      "price_range"   => [ { "$group" => { "_id" => nil, "min" => { "$min" => "$price" },
                                                         "max" => { "$max" => "$price" } } } ],
      "total"         => [ { "$count" => "value" } ] } } ]
```

O `$match` é o **primeiro estágio da pipeline externa**, não um estágio dentro de um
sub-pipeline: todas as facetas precisam ver os mesmos documentos filtrados. Colocá-lo
dentro de um sub-pipeline não dá erro — dá números errados em silêncio para os outros.

A alternativa ingênua é uma consulta por bloco da barra: N idas ao servidor cujos
resultados podem discordar entre si por terem rodado em instantes diferentes.
Assinando o monitor de comandos do driver, o tráfego de rede desta chamada é
exatamente `["aggregate"]`.

O Mongoid **não tem DSL para `$facet`**, então aqui se desce ao driver cru
(`Product.collection.aggregate`). É o único lugar da aplicação onde isso acontece — o
ODM cobre o resto do caminho.

`price` está gravado como `Decimal128` (o Mongoid mapeia `BigDecimal` para ele), então
`$min`, `$max` e `$bucket` comparam numericamente e dinheiro nunca passa por float. As
fronteiras da pipeline são `BigDecimal`, para casar com o tipo armazenado.

**Fronteiras fixas em vez de `$bucketAuto`**, deliberadamente: as três categorias têm
escalas muito diferentes (vinhos de R$ 55 a R$ 529, notebooks de R$ 2.499 a R$ 14.999), e
o `$bucket` omite os baldes vazios sozinho — então cada categoria mostra só as faixas que
de fato tem, com fronteiras previsíveis e testáveis.

---

## Interface

Uma listagem por categoria, com barra lateral facetada, e uma página de detalhe.

O que vale reparar: **não existe código específico por categoria em lugar nenhum das
views.** A página de detalhe percorre os `field_specs` da categoria e tira dali o rótulo,
a ordem e a unidade:

```erb
<% @category.field_specs.each do |field_spec| %>
  <dt><%= field_spec.label %></dt>
  <dd><%= spec_value(field_spec, @product.specs[field_spec.key]) %></dd>
<% end %>
```

O mesmo template renderiza "Safra / 2019 / Teor alcoólico / 13.9 %" para um vinho e
"Memória RAM / 16 GB / Touchscreen / Não" para um notebook. Uma categoria nova entra
funcionando.

O filtro de preço é um slider de faixa com duas alças, cujos limites vêm do `$min`/`$max`
do próprio `$facet`; atrás dele, um histograma desenhado com as contagens do `$bucket`
mostra onde os produtos se concentram. Sem JavaScript os dois `input[type=range]` ainda
submetem o formulário.

As contagens de marca são calculadas sobre a categoria inteira, não sobre o filtro
corrente — selecionar "Apple" não pode reduzir a lista de marcas a Apple sozinha.

---

## Escopo

Ficaram deliberadamente de fora: carrinho, `Order` com snapshot denormalizado do produto
comprado, e suíte de testes automatizados. O projeto entrega o catálogo — modelagem,
validação, indexação e agregação —, que é onde está o argumento sobre banco
não-relacional.

A verificação foi feita no `rails console` e no `mongosh`, e está registrada passo a
passo em [`docs/README.md`](docs/README.md).

---

## Onde olhar

```
app/models/category.rb      name, slug, embeds_many :field_specs, índice único
app/models/field_spec.rb    o schema como dado: key, label, kind, required, unit
app/models/product.rb       specs (Hash livre), a validação, os três índices
app/services/               ProductFacets — a pipeline $facet
lib/catalog/blueprint.rb    o catálogo de seed, lido também pelo db:seed
docs/README.md              diário de construção, checkpoint a checkpoint
docs/modelagem.md           diagramas do modelo de dados
docs/index-optimization.md  saída bruta do explain, antes e depois
```
