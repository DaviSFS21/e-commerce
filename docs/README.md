# Catálogo — diário de construção

Registro passo a passo da reconstrução do projeto. Cada checkpoint é uma sessão
de 40–60 minutos que termina em algo **observável**, não em algo que "deveria
funcionar".

**Stack:** Rails 8.1 · Mongoid 9.1 · MongoDB 8 · Redis 7 · Ruby 3.4.10
**Critério de avaliação:** proficiência com bancos não-relacionais — modelagem,
indexação e demonstração de consultas. Não é sobre UI.

**Branches:**

| branch | o que é |
|---|---|
| `rebuild` | a reconstrução, feita à mão. É aqui que se trabalha. |
| `main` | implementação de referência completa (não consultar antes de tentar) |
| `keycloak-spike` | integração OIDC com Keycloak + export do realm, para reuso futuro |

**Documentos:**

- [`modelagem.md`](modelagem.md) — o modelo de dados alvo, com diagramas: o que é
  embedado, o que é referenciado, e por quê. Consulte antes de cada checkpoint
  que cria um model.

---

## Plano — 11 checkpoints

| # | Checkpoint | Status |
|---|---|---|
| 1 | Serviços no ar (Mongo + Redis, `mongoid.yml`) | ✅ feito |
| 2 | `Category` + `FieldSpec` (schema embedado) | ✅ feito |
| 3 | `Product` + `specs`, sem validação | ✅ feito |
| 4 | A validação ⭐ | ✅ feito |
| 5 | Seeds | 🔄 em andamento |
| 6 | Índices + `explain` ⭐ | ⬜ |
| 7 | Agregação `$facet` ⭐ | ⬜ |
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

## Checkpoint 5 — Seeds 🔄

**Objetivo:** um catálogo de verdade, com três categorias de formatos
genuinamente diferentes, para os checkpoints 6 e 7 terem dados sobre os quais
medir.

*(a preencher ao concluir)*
