# Catálogo — Rails + MongoDB

Catálogo de e-commerce onde **cada categoria carrega o próprio schema**. Notebooks têm
RAM e touchscreen, vinhos têm safra e uva, tênis têm drop e impermeabilidade — tudo na
mesma coleção, e os produtos são validados contra o schema da própria categoria no
momento da escrita.

Criar uma categoria nova não exige classe nova, coluna nova nem migration.

**Rails 8.1 · Mongoid 9.1 · MongoDB 8 · Ruby 3.4.10**

---

## Como executar

Suba o MongoDB:

```bash
docker compose up -d
```

Instale as dependências, carregue o catálogo e crie os índices:

```bash
bundle install && bin/rails db:seed && bin/rails db:mongoid:create_indexes
```

Suba a aplicação:

```bash
bin/rails server
```

Acesse `http://localhost:3000`. O seed cria 3 categorias e 30 produtos.

---

## Validando as funcionalidades

### 1. Schema por categoria, na tela

Navegue entre **Notebooks**, **Vinhos** e **Tênis de corrida** pelas abas.

A barra lateral **muda de forma** em cada uma, e a página de detalhe de um produto mostra
rótulos e unidades diferentes — "Safra / 2019" num vinho, "Memória RAM / 16 GB" num
notebook. Não existe código específico por categoria em lugar nenhum das views: tudo vem
dos `field_specs` da categoria.

### 2. Filtros

Na listagem, clique numa marca e arraste as alças do slider de preço. A barra lateral
mostra as contagens de cada marca e um histograma da distribuição de preços.

### 3. Validação em tempo de escrita

No `bin/rails console`:

```ruby
notebooks = Category.find_by(slug: "notebooks")
def testar(cat, specs) = Product.new(name: "X", brand: "Y", price: 1, category: cat, specs: specs).tap(&:valid?).errors[:specs]

ok = { "tela_polegadas" => 14, "ram_gb" => 16, "armazenamento_gb" => 512, "touchscreen" => true }

testar(notebooks, ok)                             # => []  válido
testar(notebooks, ok.merge("uva" => "Malbec"))    # => chave não declarada na categoria
testar(notebooks, ok.merge("ram_gb" => "muita"))  # => tipo não bate com o declarado
testar(notebooks, ok.except("ram_gb"))            # => obrigatória faltando
testar(notebooks, ok.merge("touchscreen" => false)) # => []  false é valor, não ausência
```

A última linha é a que importa: em Ruby `false.blank?` é `true`, então uma checagem
ingênua de presença rejeitaria todo `false` legítimo — um tênis que não é impermeável, um
vinho que não é orgânico.

### 4. Heterogeneidade no banco

```bash
docker exec -it ecommerce-mongo mongosh e_commerce_development
```

```javascript
db.products.aggregate([{ $sample: { size: 5 } }, { $project: { name: 1, specs: 1, _id: 0 } }])
```

Cinco produtos aleatórios, conjuntos de chaves completamente diferentes, uma coleção só —
sem `null` preenchendo coluna que não existe.

### 5. Agregação numa ida só

```ruby
ProductFacets.new(category: Category.find_by(slug: "vinhos")).call
```

Contagens por marca, faixas de preço e min/max vêm de **uma única** chamada `aggregate`,
usando `$facet`. A alternativa seriam quatro consultas cujos resultados podem divergir
por terem rodado em instantes diferentes.

---

## Índices

Quatro índices, declarados nos models e criados por `db:mongoid:create_indexes`:

```
products                                     categories
  category_price  {"category_id":1,"price":1}  category_slug_unique  {"slug":1}  UNIQUE
  specs           {"specs.$**":1}
  name_brand      {"_fts":"text","_ftsx":1}
```

**`{ category_id: 1, price: 1 }`** — a listagem é sempre "esta categoria, nesta faixa de
preço, do mais barato". Igualdade primeiro, faixa e ordenação depois, para um índice só
servir o filtro **e** a ordenação.

**`{ "specs.$**": 1 }` — o índice *wildcard*, e o mais interessante do projeto.** Como
cada categoria define suas próprias chaves, ninguém sabe quais existirão: a coleção já
tem 15 chaves distintas e uma categoria nova acrescenta mais. Não dá para declarar um
índice por chave que ainda não existe. O wildcard indexa **todo** caminho sob `specs`,
presente e futuro.

O ganho, medido com `explain` na listagem filtrada:

| | Antes | Depois |
|---|---|---|
| estágio | `COLLSCAN` | `IXSCAN` |
| documentos examinados | 30 | 7 |
| chaves examinadas | 0 | 7 |

Passou a examinar exatamente os documentos que devolve. Em 30 documentos isso não muda o
relógio — o que muda é a classe de complexidade, de O(n) no tamanho da coleção para
O(log n + k). Em 300 mil produtos, é a diferença entre milissegundos e segundos.

Para reproduzir:

```ruby
Product.where(category_id: Category.find_by(slug: "notebooks").id)
       .where(:price.gte => 2000, :price.lte => 9000)
       .explain(verbosity: :execution_stats)
```

Saída completa em [`docs/index-optimization.md`](docs/index-optimization.md).

---

## Por que MongoDB

Porque **produtos de categorias diferentes não têm os mesmos atributos**, e esse é
exatamente o caso em que o modelo relacional fica desconfortável.

Num banco relacional haveria três saídas, todas ruins:

- **uma coluna por atributo de toda categoria que existir** — uma tabela larga e cheia de
  `NULL`, e uma migration a cada categoria nova;
- **uma tabela por categoria** — schema duplicado e consulta impossível de generalizar;
- **uma tabela EAV** (`produto_id`, `chave`, `valor`) — tudo vira texto, perde-se a
  tipagem, e cada leitura vira um monte de junções.

No MongoDB o produto guarda um documento aninhado com as chaves que a categoria dele
declara, e o índice wildcard mantém isso consultável sem saber as chaves de antemão.

O que se ganha em flexibilidade se paga em validação: como o banco não impõe formato, a
aplicação impõe. É o que o `Product#specs_match_category` faz, lendo o schema declarado
pela categoria. **Schema flexível não é ausência de schema — é schema em outro lugar.**

## Por que Rails

Agilidade. O framework já entrega roteamento, camada de views, validações, console
interativo e geradores, então o esforço foi todo para a modelagem e as consultas, que é
o que este projeto quer demonstrar.

O Mongoid se encaixa nisso porque implementa o ActiveModel — o mesmo contrato de
validações e callbacks do ActiveRecord — então `validates`, `errors.full_messages` e os
helpers de formulário funcionam igual, mesmo sem nenhum banco relacional envolvido.

---

## Vídeo explicativo

<!-- Substituir pelo link do vídeo -->

_Em breve._

---

## Documentação complementar

| | |
|---|---|
| [`docs/README.md`](docs/README.md) | diário de construção, checkpoint a checkpoint |
| [`docs/modelagem.md`](docs/modelagem.md) | diagramas do modelo de dados e a regra de embedar vs. referenciar |
| [`docs/index-optimization.md`](docs/index-optimization.md) | saída bruta do `explain`, antes e depois dos índices |
