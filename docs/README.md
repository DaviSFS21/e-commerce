# Catálogo — diário de construção

Registro passo a passo da reconstrução do projeto. Cada checkpoint é uma sessão
de 40–60 minutos que termina em algo **observável**, não em algo que "deveria
funcionar".

**Stack:** Rails 8.1 · Mongoid 9.1 · MongoDB 8 · Redis 7 · Ruby 3.4.10
**Critério de avaliação:** proficiência com bancos não-relacionais — modelagem,
indexação e demonstração de consultas. Não é sobre UI.

**Documentos:**

- [`modelagem.md`](modelagem.md) — o modelo de dados alvo, com diagramas: o que é
  embedado, o que é referenciado, e por quê. Consulte antes de cada checkpoint
  que cria um model.
- [`index-optimization.md`](index-optimization.md) — a saída completa do
  `explain` antes e depois dos índices, para a consulta de listagem filtrada.

---

## Plano — 11 checkpoints

| # | Checkpoint | Status |
|---|---|---|
| 1 | Serviços no ar (Mongo + Redis, `mongoid.yml`) | ✅ feito |
| 2 | `Category` + `FieldSpec` (schema embedado) | ✅ feito |
| 3 | `Product` + `specs`, sem validação | ✅ feito |
| 4 | A validação ⭐ | ✅ feito |
| 5 | Seeds | ✅ feito |
| 6 | Índices + `explain` ⭐ | ✅ feito |
| 7 | Agregação `$facet` ⭐ | 🔄 em andamento |
| 8 | Carrinho no Redis | ⬜ |
| 9 | `Order` + snapshot | ⬜ |
| 10 | UI (listagem, sidebar facetada, detalhe) | ⬜ |
| 11 | README final + suíte verde | ⬜ |

⭐ = material diretamente avaliado.

**Cortados do escopo:** Keycloak (fica para a API em Django) e CRUD admin.

---

## Como rodar (estado atual)

Subir os bancos:

```bash
docker compose up -d
```

Conferir que estão saudáveis:

```bash
docker compose ps
```

Abrir o mongosh **sempre passando o banco** (ver pegadinha no checkpoint 1):

```bash
docker exec -it ecommerce-mongo mongosh e_commerce_development
```

---

## Checkpoint 1 — Rails falando com o MongoDB ✅

**Objetivo:** um documento, escrito do `rails console`, visível no `mongosh`.
Sem models, sem RSpec, sem seeds.

### O que foi construído

**`docker-compose.yml`** — dois serviços, `mongo:8` e `redis:7`, nas portas
padrão. Três decisões:

- **Volume nomeado** (`mongo_data:/data/db`). Sem ele o banco vive na camada
  gravável do container e um `docker rm` apaga tudo.
- **Sem flag `--replSet`** — mongod standalone. Certo para desenvolvimento, mas
  com uma consequência: MongoDB só oferece transações em replica set, então a
  suíte de testes não vai poder dar rollback entre exemplos e terá que deletar
  documentos (ver checkpoint 11).
- **Redis sem persistência** (`--save "" --appendonly no`). Tudo que ele guarda
  tem TTL e não é fonte da verdade; gravar em disco custaria latência em toda
  escrita sem comprar nada.

**`config/mongoid.yml`** — gerado com:

```bash
bin/rails g mongoid:config
```

O arquivo tem 369 linhas, das quais ~20 são configuração; o resto é documentação
comentada. Dois blocos importam:

| linha | bloco | banco |
|---|---|---|
| 1 | `development` | `e_commerce_development` |
| 360 | `test` | `e_commerce_test` |

O Mongoid escolhe o bloco pelo `RAILS_ENV` no boot. Como os nomes de banco são
diferentes, rodar a suíte apaga `e_commerce_test` sem encostar nos dados de
desenvolvimento.

### Verificação

No `bin/rails console`:

```ruby
Mongoid.default_client.database.name
Mongoid.default_client[:smoke].insert_one(hello: "world")
Mongoid.default_client[:smoke].find.first
```

No mongosh: `show collections` e `db.smoke.find()`.

### O que ficou entendido

**Não existe código de conexão com o MongoDB nesta aplicação.** A cadeia é:

```
Gemfile tem "mongoid"
  → Bundler.require carrega no boot
    → a railtie do Mongoid lê config/mongoid.yml para o RAILS_ENV atual
      → abre um client e registra como `default`
        → Mongoid.default_client
```

**Mongoid não faz parte do Rails.** É uma gem mantida pela MongoDB Inc.
(`The MongoDB Ruby Team`). O que é do Rails é o ActiveRecord, desligado aqui pelo
`--skip-active-record`. O Mongoid parece nativo porque depende de `activemodel`
— o contrato de validações, callbacks e naming — e porque se pluga como railtie.
ActiveRecord é um **ORM** (Object-*Relational* Mapping); Mongoid é um **ODM**
(Object-*Document* Mapping).

**`Mongoid.default_client` é o driver cru**, um `Mongo::Client`. O smoke test não
passou por nenhum documento, validação ou associação. A camada de ODM só começa
no checkpoint 2, com `include Mongoid::Document`.

**A coleção `smoke` nunca foi declarada.** Ela passou a existir no instante do
primeiro `insert_one`. No PostgreSQL a mesma linha teria falhado com
`relation "smoke" does not exist`, exigindo um `CREATE TABLE` antes com todas as
colunas e tipos. Essa é a primeira diferença concreta entre os dois modelos — e
ela aparece antes de qualquer código de aplicação.

Atenção: *não declarar* ≠ *não validar*. O checkpoint 4 mostra que a validação
não sumiu, só mudou de lugar.

**Standalone confirmado** por `db.hello()` — a ausência do campo `setName` é como
se verifica que não há replica set.

### Pegadinha encontrada

Abrir o `mongosh` **sem passar o nome do banco** conecta num banco chamado
`test`, que é o padrão. Aí `db.e_commerce_development.insertOne(...)` é lido como
"no banco `test`, na coleção `e_commerce_development`" — cria uma coleção com o
nome do banco, dentro do banco errado.

Em mongosh, `db` **é** o banco; o que vem depois do ponto é sempre a coleção.

Limpeza:

```bash
docker exec -it ecommerce-mongo mongosh test --eval 'db.dropDatabase()'
```

`db.dropDatabase()` apaga o banco em que você **está** — sempre confirmar com
`db.getName()` antes.

---

## Checkpoint 2 — `Category` + `FieldSpec` ✅

**Objetivo:** o schema de uma categoria, guardado como dado, aninhado dentro do
próprio documento da categoria.

### O que foi construído

`app/models/field_spec.rb` — `key`, `label`, `kind`, `required`, `unit`.
`embedded_in :category`. Validações: presença em `key`/`label`, formato no `key`,
`inclusion` do `kind` em `%w[string number boolean]`, e `uniqueness` no `key`.

`app/models/category.rb` — `name`, `slug`, `embeds_many :field_specs`,
`Mongoid::Timestamps`. Validações de presença, `uniqueness` no `slug` e presença
de pelo menos um `field_spec`. Índice único em `slug` declarado aqui.

### Verificação

```ruby
c = Category.create!(name: "Notebooks", slug: "notebooks",
                     field_specs: [ FieldSpec.new(key: "ram_gb", label: "Memória RAM",
                                                  kind: "number", required: true, unit: "GB") ])

Mongoid.default_client[:categories].find(_id: c.id).first   # field_specs é array aninhado
Mongoid.default_client.database.collection_names            # => ["categories"] apenas
```

Resultado: `field_specs` aninhado no documento, **nenhuma coleção `field_specs`**.

### O que ficou entendido

**A camada de ODM começa aqui.** `include Mongoid::Document` é módulo incluído,
não herança — não existe `< ApplicationRecord`. Até o checkpoint 1 só havia
driver cru.

**`field` declara na aplicação, não no banco.** O MongoDB não sabe que esses
campos existem; inserir um campo extra pelo mongosh passa sem reclamação. E
`type:` é *conversão*, não restrição — quem restringe é validação.

**Um documento embedado não pode ser salvo sozinho.** `FieldSpec.new(...).save`
falha: ele não tem coleção própria, então não existe onde salvá-lo. Só passa a
existir quando a categoria dona é salva. Essa é a diferença concreta entre
embedar e referenciar — não é teoria, é o que o Mongoid impede.

**`uniqueness` funciona dentro do embed.** O Mongoid escopa a validação aos
irmãos do mesmo pai, então duas `field_specs` com a mesma `key` na mesma
categoria são rejeitadas. A mensagem é genérica (`"Field specs is invalid"`) e
não diz qual chave duplicou.

**O Mongoid protege nomes reservados.** Declarar `field :attributes` levanta erro
na hora da declaração, porque `Mongoid::Document` já define `#attributes`. É por
isso que o hash livre do produto vai se chamar `specs` no checkpoint 3.

### Armadilha encontrada: índice em model embedado falha em silêncio

O índice único do slug foi declarado por engano dentro do `FieldSpec`. Como ele é
embedado e não tem coleção, o Mongoid **ignorou o índice sem erro nenhum**:

```
FieldSpec.index_specifications: [{slug: 1}]
Category.index_specifications:  []
create_indexes rodou sem erro
índices reais em categories:    ["_id_"]      ← o índice não existe
```

Nenhuma exceção, nenhum aviso. O erro só apareceria no checkpoint 6, como um
`COLLSCAN` inexplicável — ou nunca. Depois de mover a declaração para o
`Category`, `create_indexes` passou a criar `category_slug_unique` de verdade.

Lição geral: **declarar não é criar.** A linha no model registra a intenção; o
índice só existe depois de `rails db:mongoid:create_indexes`.

### Decisões tomadas

| Decisão | Consequência |
|---|---|
| `validates :field_specs, presence: true` | Uma categoria sem schema é inválida. Os `field_specs` têm que ir na mesma chamada de criação — afeta as seeds do checkpoint 5. |
| `slug` com formato `/\A[a-z0-9_]+\z/` | Slugs usam underscore, não hífen: `tenis_de_corrida`, não `tenis-de-corrida`. |
| Validador `uniqueness` **e** índice único no `slug` | O validador dá mensagem legível; o índice é o que segura duas requisições simultâneas, onde o validador tem condição de corrida. |

---

## Checkpoint 3 — `Product` + `specs` ✅

**Objetivo:** heterogeneidade visível. Três produtos com conjuntos de chaves
diferentes convivendo na mesma coleção. Ainda **sem validação**.

### O que foi construído

`app/models/product.rb` — `name`, `brand`, `price` (`BigDecimal`), `in_stock`
(`Mongoid::Boolean`), `specs` (`Hash`). `belongs_to :category`,
`embeds_many :images`.

`app/models/image.rb` — `url`, `alt`, `position`, `embedded_in :product`.

E o `has_many :products` do `Category` foi descomentado.

### Verificação

```
ThinkPad X1     ["ram_gb", "touchscreen"]
Catena Malbec   ["safra", "uva"]
Pegasus 41      ["tamanho_eu", "impermeavel"]
coleções: ["categories", "products"]
```

Três formatos, uma coleção, sem `null` preenchendo coluna que não existe.

### O que ficou entendido

**O `Hash` vira sub-documento BSON de verdade, não texto serializado.**

```ruby
{"_id" => ..., "name" => "notebook",
 "specs" => {"ram_gb" => 16, "touchscreen" => false, "cpu" => "M4"}}
```

E os tipos sobrevivem: `16` continua `Integer`, `false` continua `FalseClass`,
`"M4"` continua `String`.

**Consequência: dá para consultar dentro do hash.**

```ruby
Product.where("specs.uva" => "Malbec")
Product.where(:"specs.safra".gte => 2015)
Product.where("specs.uva" => { "$exists" => true })
```

É por isso que o campo é `Hash` e não `String`. Serializado em JSON dentro de uma
string, seria preciso trazer tudo para a memória e filtrar em Ruby — e o índice
wildcard do checkpoint 6 seria impossível, porque não existiria caminho
`specs.uva` para indexar.

**Chave symbol vira string sozinha.** `specs: { ram_gb: 32 }` já sai do
construtor como `{"ram_gb" => 32}`. Não há inconsistência entre antes e depois de
salvar.

**`default: -> { {} }`, não `default: {}`.** Com o literal, todas as instâncias
compartilham o *mesmo* objeto hash e escrever numa contamina as outras.

**`price` como `BigDecimal` vira `decimal` (Decimal128) no BSON.** Confirmado com
`{ $type: "$price" }`. Float não representa dinheiro exatamente; e se tivesse
virado String, `price >= 2000` compararia texto — ordenação lexicográfica em
dinheiro é bug garantido.

**`belongs_to` é referência.** O documento tem `category_id` e não um
sub-documento `category` — a regra do checkpoint 2 aplicada na direção oposta.

### O gancho para o checkpoint 4

Isto entrou no banco sem um pio:

```ruby
Product.create!(name: "ThinkPad", category: notebooks, specs: { "uva" => "Malbec" })
```

Um notebook com uva. É o custo real do schema-on-read, sentido na prática antes
de resolver.

---

## Checkpoint 4 — a validação ⭐ ✅

**A peça central do projeto.** Schema-on-read não significa ausência de
validação: significa que ela saiu do DDL e virou dado.

### O que foi construído

`Product#specs_match_category` — validação customizada que lê
`category.field_specs` em tempo de escrita e aplica quatro regras:

| # | Regra |
|---|---|
| 1 | Rejeita chave não declarada pela categoria |
| 2 | Rejeita valor cujo tipo não bate com o `kind` |
| 3 | Rejeita chave obrigatória não informada |
| 4 | **Aceita `false`** para booleano obrigatório |

E dois métodos no `FieldSpec`, que respondem a perguntas diferentes:

```ruby
def matches?(value)   # o tipo bate?
def supplied?(value)  # foi informado?
```

### A armadilha do `false`

`supplied?` **não** usa `blank?`. Em Ruby `false.blank?` é `true`, então uma
checagem de presença rejeitaria `touchscreen: false` — um tênis que não é
impermeável, um vinho que não é orgânico. `0` é o irmão do mesmo problema.

Só `nil` e string em branco contam como não informado.

### Dois bugs encontrados na revisão

**`return` no lugar de `next`.** Ao achar uma chave não declarada, o `return`
saía do método inteiro, então a checagem de obrigatórias nunca rodava. Pior:
o resultado dependia da ordem das chaves no hash — o mesmo erro reportava coisas
diferentes conforme a ordem de iteração.

**String vazia passava em campo obrigatório.** `"".is_a?(String)` é `true`, então
`matches?` aprovava e a chave contava como preenchida. A correção foi checar
`supplied?` **antes** de marcar a obrigatória como satisfeita — o que também
corrigiu a mensagem de `nil`, que antes reclamava de tipo quando o problema era
ausência.

### Verificação — 14 casos

```
ok  1. specs corretas                       true
ok  2. chave não declarada                  false  "Atributo uva não está na categoria"
ok  3. tipo errado                          false  "Tipo do atributo ram_gb deve ser number"
ok  4. obrigatória ausente                  false  "Atributos obrigatórios faltantes: ram_gb"
ok  5. FALSE em booleano obrigatório        true
ok  6. não declarada + falta obrigatória    false  reporta os dois problemas
ok  7. duas não declaradas                  false  reporta as duas
ok  9. string vazia em obrigatória          false
ok 10. nil em obrigatória                   false  "faltantes", não "tipo errado"
ok 11. zero em número obrigatório           true
ok 12. opcional ausente                     true
ok 13. opcional com string vazia            true
ok 14. opcional com tipo errado             false
ok 15. specs vazio                          false  lista as três obrigatórias
```

### Refatorações aplicadas

`for ... in` → `each`; `.keys.include?` → busca direta no hash (o `index_by`
existe justamente para dar busca O(1)); `.pluck(:key)` → `.map(&:key)`;
`select(&:required)` → `select(&:required?)`; `!required.blank?` →
`required.any?`; e removido o `errors.add(:category, ...)` que duplicava o erro
já emitido pelo `belongs_to` (obrigatório por padrão no Mongoid 9).

---

## Checkpoint 5 — Seeds ✅

**Objetivo:** um catálogo de verdade, com três categorias de formatos
genuinamente diferentes, para os checkpoints 6 e 7 terem dados sobre os quais
medir.

### O que foi construído

`lib/catalog/blueprint.rb` — o catálogo como dado, três categorias × 10 produtos.
`db/seeds.rb` apenas chama `Catalog::Blueprint.load!`.

**Por que em `lib/` e não direto em `db/seeds.rb`:** no checkpoint 7 os testes de
agregação vão afirmar contagens de faceta ("Lenovo = 3"). Com o catálogo em
`lib/`, o seed e o teste leem a mesma fonte, em vez de duplicar os números.
`lib/` já é autoloaded, então `Catalog::Blueprint` funciona sem require.

`load!` faz `delete_all` antes de recriar — rodar duas vezes deixa os mesmos 30
produtos, senão as contagens do checkpoint 7 mudariam a cada `db:seed`.

### Resultado

```
categorias=3 produtos=30   todos válidos: true

notebooks          10 produtos  min=2499.00  max=14999.00
tenis-de-corrida   10 produtos  min=349.90   max=1899.90
vinhos             10 produtos  min=54.90    max=529.00

marcas (notebooks): Lenovo=3, Apple=2, Dell=2, Asus=2, Framework=1
```

### Como os dados foram desenhados

Pensando no checkpoint 7, porque uma faceta só demonstra algo se houver o que
contar:

- **Marcas repetem.** 4–5 marcas por categoria, com contagens diferentes. Se cada
  produto tivesse marca única, a faceta seria uma lista de contagens 1.
- **Preços espalhados**, e em três escalas bem diferentes entre categorias
  (dezenas de reais nos vinhos, milhares nos notebooks). É o que vai obrigar a
  decidir, no checkpoint 7, se os baldes de faixa de preço são fixos ou
  calculados por categoria.
- **Valores de spec repetem**: `uva` tem Cabernet×2 e Merlot×2, `pais` tem
  Brasil×4, `superficie` tem asfalto×7 e trilha×3.

### Casos plantados de propósito

| Caso | Onde | Para quê |
|---|---|---|
| `drop_mm: 0` | Grafite 2 | zero é valor legítimo — irmão do `false` |
| `impermeavel`/`touchscreen: false` | maioria dos produtos | se a validação regredir para `blank?`, o seed quebra na hora |
| sem `cpu` (opcional) | Framework 13 | chave ausente **não** obrigatória tem que passar |
| `in_stock: false` | 1 por categoria | filtro de estoque no checkpoint 10 |

O seed funciona como teste de regressão da validação do checkpoint 4: se ela
quebrar, `db:seed` estoura.

### A descoberta que motiva o checkpoint 6

Listando todas as chaves de spec distintas da coleção inteira:

```ruby
Product.all.flat_map { |p| p.specs.keys }.uniq.sort
# => ["armazenamento_gb", "cpu", "drop_mm", "impermeavel", "organico", "pais",
#     "peso_g", "ram_gb", "safra", "superficie", "tamanho_eu", "tela_polegadas",
#     "teor_alcoolico", "touchscreen", "uva"]
```

**Quinze chaves diferentes, e nenhuma delas é conhecida em tempo de código.** Uma
quarta categoria acrescentaria mais cinco amanhã.

É exatamente por isso que o índice do checkpoint 6 precisa ser *wildcard*: não dá
para declarar um índice por chave quando o conjunto de chaves é aberto, e
declarar um índice para cada chave futura não escala — cada índice é custo de
escrita em toda inserção.

---

## Checkpoint 6 — Índices + `explain` ⭐ ✅

**Objetivo:** provar, com saída de `explain`, que as consultas do catálogo
deixaram de varrer a coleção inteira.

A saída bruta do `explain`, antes e depois, está em
[`index-optimization.md`](index-optimization.md).

### Índices declarados

```ruby
index({ category_id: 1, price: 1 }, { name: "category_price" })
index({ "specs.$**" => 1 },         { name: "specs" })
index({ name: "text", brand: "text" }, { name: "name_brand" })
```

Criados com `bin/rails db:mongoid:create_indexes` e conferidos no servidor, não
só no model:

```
_id_            {"_id":1}
category_price  {"category_id":1,"price":1}
specs           {"specs.$**":1}
name_brand      {"_fts":"text","_ftsx":1}
```

### O ganho, medido

Consulta de listagem filtrada — uma categoria, faixa de preço:

| Métrica | Antes | Depois |
|---|---|---|
| estágio | `COLLSCAN` | `IXSCAN` → `FETCH` |
| `totalDocsExamined` | 30 | 7 |
| `totalKeysExamined` | 0 | 7 |
| `works` | 31 | 8 |
| `nReturned` | 7 | 7 |

Examinou exatamente os 7 documentos que devolveu, em vez dos 30 da coleção.

**O que isso significa, e o que não significa.** Numa coleção de 30 documentos o
tempo de relógio não mede nada útil — tudo cabe em memória e o próprio
planejamento do plano custa mais que a varredura. O que o `explain` prova é
mudança de **classe de complexidade**: `COLLSCAN` é O(n) no tamanho da coleção,
`IXSCAN` é O(log n + k), com k = tamanho do resultado. Em 30 documentos isso é
invisível; em 300 mil é a diferença entre milissegundos e segundos.

### As demais consultas

```
specs.uva = Malbec             IXSCAN  idx=specs       ret=1  docs=1   keys=1
specs.impermeavel = true       IXSCAN  idx=specs       ret=3  docs=3   keys=3
specs.ram_gb >= 16             IXSCAN  idx=specs       ret=7  docs=7   keys=7
texto: MacBook                 IXSCAN  idx=name_brand  ret=2  docs=2   keys=2
in_stock = false (sem índice)  COLLSCAN                ret=3  docs=30  keys=0
```

A última linha é o **caso de controle**, e importa: sem ela, "deu IXSCAN" não
prova nada — poderia ser que toda consulta desse IXSCAN. Com ela, fica
demonstrado que a medição distingue os dois casos.

### Por que wildcard e não um índice por chave

O checkpoint 5 mostrou 15 chaves de spec distintas, nenhuma conhecida em tempo de
código. O `keyPattern` do plano explica como um índice só dá conta:

```
{"$_path" => 1, "specs.uva" => 1}
```

O MongoDB limita `$_path` à chave consultada e varre os valores dentro dela. Um
índice físico se comporta como um índice por chave — para qualquer chave,
inclusive as que ainda não existem. As três consultas de spec acima usam
categorias diferentes e o mesmo índice `specs`.

A alternativa seria declarar 15 índices e mais 5 a cada categoria nova. Cada
índice é custo de escrita em toda inserção, e nenhum deles cobriria a chave
inventada amanhã.

### Sobre a ordem das chaves no índice composto

`{ category_id: 1, price: 1 }`, nessa ordem: igualdade primeiro, faixa e
ordenação depois. Invertido, o índice ainda serve o filtro mas não a ordenação, e
aparece um estágio `SORT` bloqueante no plano.

---

## Checkpoint 7 — Agregação `$facet` ⭐ 🔄

**Objetivo:** a sidebar inteira — contagens por marca, por faixa de preço, e
min/max — numa única ida ao servidor.

*(a preencher ao concluir)*
