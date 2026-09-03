# WarpTalk Qdrant Logical Vector Storage Model Plan

## Goal

Create a separate **Qdrant Logical Vector Storage Model** diagram for WarpTalk.

This must not pretend Qdrant is a relational database. The main ERD remains the PostgreSQL/domain ERD. The Qdrant diagram explains the vector store shape, the collections used at runtime, the payload stored in each point, and the source tables that produce those points.

The visual style should stay consistent with the existing ERD:

- rectangular entity boxes;
- orthogonal connector lines;
- Crow's Foot-like cardinality where useful;
- clear labels on relationships;
- no curved/freehand arrows.

Reference style: `warptalk-infrastructure/docs/erd/warptalk-erd.puml`.

## Evidence To Ground The Diagram

### Qdrant Runtime Model

`warptalk-ai/embedding_worker/vector_store.py`

- `QdrantVectorStore.upsert(...)` creates/ensures a collection.
- Each Qdrant point is written as:
  - `id`
  - `vector`
  - `payload`
- Collection vector config uses:
  - `size = dimensions`
  - `distance = distance_metric`

`warptalk-ai/shared/config.py`

- `EMBEDDING_MODEL = text-embedding-3-small`
- `EMBEDDING_DIMENSIONS = 1536`
- `VECTOR_DB_PROVIDER = qdrant`
- `VECTOR_DB_DISTANCE_METRIC = cosine`

### Main Collection Naming

`warptalk-ai/ai_assistant_worker/chat_tools.py`

- Semantic search queries:
  - `workspace_{workspace_id}`
  - `global_glossary`
- `global_glossary` uses sentinel payload field:
  - `workspace_id = global`

`warptalk-backend/workspace/src/WarpTalk.WorkspaceService.Infrastructure/Adapters/QdrantKnowledgeChunkReader.cs`

- Workspace Knowledge page scrolls:
  - `collections/workspace_{workspaceId}/points/scroll`
- It filters by:
  - `workspace_id`
  - optional `source_type`
  - optional `fact_category`
- It reads payload fields such as:
  - `chunk_id`
  - `source_type`
  - `text`
  - `fact`
  - `fact_category`
  - `document_id`
  - `document_name`
  - `chunk_index`
  - `speaker_name`
  - `start_ms`
  - `retention_state`
  - `deletion_state`
  - `ai_retrieval`
  - `source_title`
  - `source_term`

### Producer Sources

`warptalk-backend/workspace/src/WarpTalk.WorkspaceService.Infrastructure/Adapters/RedisEmbeddingIndexPublisher.cs`

- Source: `workspace.workspace_documents`
- Collection: `workspace_{document.WorkspaceId}`
- Source type: `document`
- Point ids: stable UUID per document chunk.
- Metadata:
  - `document_id`
  - `document_name`
  - `chunk_index`
  - `ingestion_revision`

`warptalk-backend/transcript/src/WarpTalk.TranscriptService.Infrastructure/Redis/TranscriptRedisConsumerService.cs`

- Source: `transcript.transcripts` and `transcript.transcript_segments`
- Collection: `workspace_{transcript.WorkspaceId}`
- Source type: `transcript`
- Point id: `segment.Id`
- Metadata:
  - `transcript_id`
  - `translation_room_id`
  - `segment_id`
  - `speaker_name`
  - `start_ms`

`warptalk-backend/transcript/src/WarpTalk.TranscriptService.Application/Services/GlossaryService.cs`

- Source: `transcript.glossary_terms`
- Collection: `workspace_{workspaceId}`
- Source type: `glossary_term`
- Point id: `term.Id`
- Metadata:
  - `glossary_id`
  - `term_id`
  - `source_term`
  - `target_term`
  - `domain`

`warptalk-backend/transcript/src/WarpTalk.TranscriptService.Application/Services/GlobalGlossaryService.cs`

- Source: `transcript.global_glossary_terms`
- Collection: `global_glossary`
- Source type: `global_glossary_term`
- Payload workspace sentinel:
  - `workspace_id = global`
- Metadata:
  - `global_glossary_term_id`
  - `term`
  - `preferred_translation`
  - `business_domain`

`warptalk-backend/translation-room/src/WarpTalk.TranslationRoomService.Infrastructure/Adapters/RedisKnowledgeFactRequestPublisher.cs`

- Source: meeting summary artifacts from Translation Room flow.
- Publishes `knowledge:fact_requests`.
- `warptalk-ai/ai_assistant_worker/knowledge_fact_worker.py` converts them into `embedding:index_requests`.
- Collection: `workspace_{workspace_id}`
- Source type: usually `meeting_summary`
- Metadata:
  - `source_title`
  - optional `chunk_index`
  - optional `fact`
  - optional `fact_category`

### Generic Payload Written By EmbeddingWorker

`warptalk-ai/embedding_worker/worker.py`

Every indexed point payload includes:

- source-specific metadata from the producer;
- `workspace_id`
- `source_type`
- `source_id`
- `chunk_id`
- `text`
- `ai_retrieval`
- `retention_state`
- `deletion_state`

Deletion uses the same stream contract with:

- `deletion_state = deleted`
- `collection_id`
- `chunk.id`

The worker deletes points by id instead of embedding/upserting them.

### Auxiliary Document Path To Treat Carefully

`warptalk-backend/workspace/src/WarpTalk.WorkspaceService.Infrastructure/Clients/WorkspaceDocumentAuxiliaryPublisher.cs`

- Publishes to collection:
  - `warptalk_workspace_documents`
- Source type:
  - `workspace_document`

This is not the collection read by current semantic search or Workspace Knowledge page, which use `workspace_{workspaceId}`. In the diagram, show this only as an **auxiliary/compatibility path** or a note, not as the primary Qdrant model.

## Diagram Scope

Include:

- Qdrant collections and points.
- The source PostgreSQL entities that produce vector points.
- The Redis stream contracts that move source content into Qdrant.
- Payload fields important for retrieval, tenancy, lifecycle, and display.

Exclude:

- Full PostgreSQL ERD.
- Full AI service architecture.
- Qdrant infrastructure deployment details such as StatefulSet, Helm values, backup scripts, and storage volumes.
- Detailed Redis stream implementation internals beyond the contract names.

## Proposed Diagram Structure

### Package 1: Relational Sources

Entities:

- `workspace_documents`
- `transcripts`
- `transcript_segments`
- `glossary_terms`
- `global_glossary_terms`
- `translation_room_artifacts`

Only show minimal fields:

- `id`
- `workspace_id` where applicable
- source text/title fields if useful
- lifecycle fields if they affect indexing

### Package 2: Embedding Pipeline Contract

Entities:

- `EmbeddingIndexRequest`
- `EmbeddingChunk`
- `KnowledgeFactRequest`

Relationships:

- source entities publish `EmbeddingIndexRequest`
- `KnowledgeFactRequest` creates `EmbeddingIndexRequest`
- `EmbeddingIndexRequest` contains one or many `EmbeddingChunk`

### Package 3: Qdrant Vector Store

Entities:

- `WorkspaceCollection`
- `GlobalGlossaryCollection`
- `AuxiliaryDocumentCollection`
- `QdrantPoint`
- `PointPayload`

Fields:

`WorkspaceCollection`

- `name = workspace_{workspaceId}`
- `vector_size = 1536`
- `distance = cosine`
- `embedding_model = text-embedding-3-small`

`GlobalGlossaryCollection`

- `name = global_glossary`
- `workspace_id payload sentinel = global`
- `vector_size = 1536`
- `distance = cosine`

`AuxiliaryDocumentCollection`

- `name = warptalk_workspace_documents`
- note: auxiliary/compatibility path, not current main semantic search target

`QdrantPoint`

- `id`
- `vector`
- `payload`

`PointPayload`

- `workspace_id`
- `source_type`
- `source_id`
- `chunk_id`
- `text`
- `ai_retrieval`
- `retention_state`
- `deletion_state`
- optional source metadata fields

## Relationship Rules

Use logical, dashed relationships for source-to-Qdrant links because they are not PostgreSQL foreign keys.

Suggested labels:

- `indexed as`
- `stored in`
- `contains`
- `searches`
- `scrolls`
- `deletes by point id`

Cardinality:

- one `WorkspaceCollection` contains many `QdrantPoint`
- one source row can produce one or many `QdrantPoint`
- one `EmbeddingIndexRequest` contains one or many `EmbeddingChunk`
- one `EmbeddingChunk` becomes one `QdrantPoint`
- one `GlobalGlossaryCollection` contains many global glossary points

## Must-Have Notes On The Diagram

Add a visible note:

> Qdrant is modeled logically as Collection -> Point(id, vector, payload). These links are indexing/provenance links, not relational foreign keys.

Add a second note:

> Main semantic search queries both `workspace_{workspaceId}` and `global_glossary`. Workspace Knowledge listing scrolls only `workspace_{workspaceId}` and excludes raw transcript points from the listing, while WarpBot can still search them.

Add a third note near `warptalk_workspace_documents`:

> Auxiliary path found in backend. Current main read/search paths do not query this collection; verify before presenting it as production RAG.

## Implementation Steps

1. Create `warptalk-infrastructure/docs/erd/warptalk-qdrant-vector-model.puml`.
2. Reuse the visual setup from `warptalk-erd.puml`:
   - `hide circle`
   - `hide empty members`
   - `skinparam linetype ortho`
   - `skinparam packageStyle rectangle`
3. Define packages:
   - `Relational Sources`
   - `Embedding Pipeline`
   - `Qdrant Vector Store`
4. Draw source entities with only the fields needed to explain vector indexing.
5. Draw `EmbeddingIndexRequest`, `EmbeddingChunk`, `QdrantCollection`, `QdrantPoint`, and `PointPayload`.
6. Connect source entities to chunks/points using logical dashed arrows.
7. Add notes for:
   - Qdrant not being relational;
   - `workspace_{workspaceId}` vs `global_glossary`;
   - auxiliary `warptalk_workspace_documents`.
8. Render to PNG/SVG.
9. Check visual quality:
   - orthogonal lines;
   - readable text;
   - no overlapping boxes;
   - source types visible;
   - collection names visible.
10. Cross-check the rendered diagram against these code paths before using it in the report.

## Acceptance Checklist

- [ ] Diagram uses orthogonal connectors like the current ERD.
- [ ] Qdrant is not represented as SQL tables with physical FKs.
- [ ] `workspace_{workspaceId}` is shown as the main per-workspace collection.
- [ ] `global_glossary` is shown as a separate collection.
- [ ] `warptalk_workspace_documents` is marked auxiliary or needs verification.
- [ ] Generic payload fields are listed.
- [ ] Source-specific metadata fields are listed.
- [ ] Source tables are connected to the correct `source_type`.
- [ ] Meeting summary/fact path via `knowledge:fact_requests` is represented.
- [ ] Transcript points are shown as searchable but excluded from the Workspace Knowledge listing.
- [ ] Notes clearly state that links are logical indexing/provenance links, not relational FKs.

