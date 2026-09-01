# Otimização com indexes
```ruby
# Indexes em produtos
index({ category_id: 1, price: 1 }, { name: "category_price" })
index({ "specs.$**" => 1 }, { name: "specs" })
index({ name: "text", brand: "text" }, { name: "name_brand" })

# Consulta testada:
Product.where(category_id: Category.find_by(slug: "notebooks").id)
       .where(:price.gte => 2000, :price.lte => 9000)
       .explain(verbosity: :execution_stats)
```

## Principal diferença:
De 30 documentos consultados, fomos para apenas 7. Nesse caso, **a otimização fez com que 
a consulta rodasse em menos de 25% do tempo da consulta feita antes da criação dos índices.** 
Uma diferença substancial, com ganhos exponenciais dependendo do tamanho do banco.

### Antes:

```ruby
{"explainVersion" => "1",
 "queryPlanner" =>
  {"namespace" => "e_commerce_development.products",
   "parsedQuery" =>
    {"$and" => [{"category_id" => {"$eq" => BSON::ObjectId('6a95a8ed4895994ccea729db')}}, {"price" => {"$lte" => 0.9e4}}, {"price" => {"$gte" => 0.2e4}}]},
   "indexFilterSet" => false,
   "queryHash" => "80076C22",
   "planCacheShapeHash" => "80076C22",
   "planCacheKey" => "6DA52931",
   "optimizationTimeMillis" => 0,
   "maxIndexedOrSolutionsReached" => false,
   "maxIndexedAndSolutionsReached" => false,
   "maxScansToExplodeReached" => false,
   "prunedSimilarIndexes" => false,
   "winningPlan" =>
    {"isCached" => false,
     "stage" => "COLLSCAN",
     "filter" =>
      {"$and" => [{"category_id" => {"$eq" => BSON::ObjectId('6a95a8ed4895994ccea729db')}}, {"price" => {"$lte" => 0.9e4}}, {"price" => {"$gte" => 0.2e4}}]},
     "direction" => "forward"},
   "rejectedPlans" => []},
 "executionStats" =>
  {"executionSuccess" => true,
   "nReturned" => 7,
   "executionTimeMillis" => 0,
   "totalKeysExamined" => 0,
   "totalDocsExamined" => 30,
   "executionStages" =>
    {"isCached" => false,
     "stage" => "COLLSCAN",
     "filter" =>
      {"$and" => [{"category_id" => {"$eq" => BSON::ObjectId('6a95a8ed4895994ccea729db')}}, {"price" => {"$lte" => 0.9e4}}, {"price" => {"$gte" => 0.2e4}}]},
     "nReturned" => 7,
     "executionTimeMillisEstimate" => 0,
     "works" => 31,
     "advanced" => 7,
     "needTime" => 23,
     "needYield" => 0,
     "saveState" => 0,
     "restoreState" => 0,
     "isEOF" => 1,
     "direction" => "forward",
     "docsExamined" => 30}},
 "queryShapeHash" => "677AA2918C5F6A537D36FD7FA3FA6C14187CDC2D2F0DB6505D1728FBF6E76983",
 "command" =>
  {"find" => "products",
   "filter" => {"category_id" => BSON::ObjectId('6a95a8ed4895994ccea729db'), "price" => {"$gte" => 0.2e4, "$lte" => 0.9e4}},
   "$db" => "e_commerce_development"},
 "serverInfo" => {"host" => "b5148a5f0e68", "port" => 27017, "version" => "8.2.12", "gitVersion" => "0f912e80210b8fdfdcec618b14b6c0fced055cb8"},
 "serverParameters" =>
  {"internalQueryFacetBufferSizeBytes" => 104857600,
   "internalQueryFacetMaxOutputDocSizeBytes" => 104857600,
   "internalLookupStageIntermediateDocumentMaxSizeBytes" => 104857600,
   "internalDocumentSourceGroupMaxMemoryBytes" => 104857600,
   "internalQueryMaxBlockingSortMemoryUsageBytes" => 104857600,
   "internalQueryProhibitBlockingMergeOnMongoS" => 0,
   "internalQueryMaxAddToSetBytes" => 104857600,
   "internalDocumentSourceSetWindowFieldsMaxMemoryBytes" => 104857600,
   "internalQueryFrameworkControl" => "trySbeRestricted",
   "internalQueryPlannerIgnoreIndexWithCollationForRegex" => 1},
 "ok" => 1.0}
```

## Depois

```ruby
{"explainVersion" => "1",
 "queryPlanner" =>
  {"namespace" => "e_commerce_development.products",
   "parsedQuery" => {"$and" => [{"category_id" => {"$eq" => BSON::ObjectId('6a95a8ed4895994ccea729db')}}, {"price" => {"$lte" => 0.9e4}}, {"price" => {"$gte" => 0.2e4}}]},
   "indexFilterSet" => false,
   "queryHash" => "80076C22",
   "planCacheShapeHash" => "80076C22",
   "planCacheKey" => "6460A3F9",
   "optimizationTimeMillis" => 2,
   "maxIndexedOrSolutionsReached" => false,
   "maxIndexedAndSolutionsReached" => false,
   "maxScansToExplodeReached" => false,
   "prunedSimilarIndexes" => false,
   "winningPlan" =>
    {"isCached" => false,
     "stage" => "FETCH",
     "inputStage" =>
      {"stage" => "IXSCAN",
       "keyPattern" => {"category_id" => 1, "price" => 1},
       "indexName" => "category_price",
       "isMultiKey" => false,
       "multiKeyPaths" => {"category_id" => [], "price" => []},
       "isUnique" => false,
       "isSparse" => false,
       "isPartial" => false,
       "indexVersion" => 2,
       "direction" => "forward",
       "indexBounds" => {"category_id" => ["[ObjectId('6a95a8ed4895994ccea729db'), ObjectId('6a95a8ed4895994ccea729db')]"], "price" => ["[2000, 9000]"]}}},
   "rejectedPlans" => []},
 "executionStats" =>
  {"executionSuccess" => true,
   "nReturned" => 7,
   "executionTimeMillis" => 6,
   "totalKeysExamined" => 7,
   "totalDocsExamined" => 7,
   "executionStages" =>
    {"isCached" => false,
     "stage" => "FETCH",
     "nReturned" => 7,
     "executionTimeMillisEstimate" => 0,
     "works" => 8,
     "advanced" => 7,
     "needTime" => 0,
     "needYield" => 0,
     "saveState" => 0,
     "restoreState" => 0,
     "isEOF" => 1,
     "docsExamined" => 7,
     "alreadyHasObj" => 0,
     "inputStage" =>
      {"stage" => "IXSCAN",
       "nReturned" => 7,
       "executionTimeMillisEstimate" => 0,
       "works" => 8,
       "advanced" => 7,
       "needTime" => 0,
       "needYield" => 0,
       "saveState" => 0,
       "restoreState" => 0,
       "isEOF" => 1,
       "keyPattern" => {"category_id" => 1, "price" => 1},
       "indexName" => "category_price",
       "isMultiKey" => false,
       "multiKeyPaths" => {"category_id" => [], "price" => []},
       "isUnique" => false,
       "isSparse" => false,
       "isPartial" => false,
       "indexVersion" => 2,
       "direction" => "forward",
       "indexBounds" => {"category_id" => ["[ObjectId('6a95a8ed4895994ccea729db'), ObjectId('6a95a8ed4895994ccea729db')]"], "price" => ["[2000, 9000]"]},
       "keysExamined" => 7,
       "seeks" => 1,
       "dupsTested" => 0,
       "dupsDropped" => 0}}},
 "queryShapeHash" => "677AA2918C5F6A537D36FD7FA3FA6C14187CDC2D2F0DB6505D1728FBF6E76983",
 "command" =>
  {"find" => "products",
   "filter" => {"category_id" => BSON::ObjectId('6a95a8ed4895994ccea729db'), "price" => {"$gte" => 0.2e4, "$lte" => 0.9e4}},
   "$db" => "e_commerce_development"},
 "serverInfo" => {"host" => "b5148a5f0e68", "port" => 27017, "version" => "8.2.12", "gitVersion" => "0f912e80210b8fdfdcec618b14b6c0fced055cb8"},
 "serverParameters" =>
  {"internalQueryFacetBufferSizeBytes" => 104857600,
   "internalQueryFacetMaxOutputDocSizeBytes" => 104857600,
   "internalLookupStageIntermediateDocumentMaxSizeBytes" => 104857600,
   "internalDocumentSourceGroupMaxMemoryBytes" => 104857600,
   "internalQueryMaxBlockingSortMemoryUsageBytes" => 104857600,
   "internalQueryProhibitBlockingMergeOnMongoS" => 0,
   "internalQueryMaxAddToSetBytes" => 104857600,
   "internalDocumentSourceSetWindowFieldsMaxMemoryBytes" => 104857600,
   "internalQueryFrameworkControl" => "trySbeRestricted",
   "internalQueryPlannerIgnoreIndexWithCollationForRegex" => 1},
 "ok" => 1.0}
```
