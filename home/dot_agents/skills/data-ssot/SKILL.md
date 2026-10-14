---
name: data-ssot
description: Single source of truth for data shapes — derive zod from drizzle tables, TS types from zod, and validate boundaries with the derived schemas. Use when modeling data, adding or changing fields, building forms or validators, or whenever duplicate or parallel type definitions for the same concept appear.
---

# Data SSOT

One concept = one canonical definition. Every other representation is
derived, never written by hand. Codegen's default failure mode is inventing a
new shape per layer (DB row, DTO, form values, API payload, UI props) — this
skill makes that a violation, not a vibe.

## The derivation chain

drizzle table → zod schema → composed variants → TS types → boundary
validation

1. **Table** is the source of truth for persisted shape.
2. **Schema**: `createInsertSchema(table, { column: refinementSchema })` or
   `createSelectSchema(table)`.
3. **Variants** are composed, never re-declared: `.omit()`, `.extend()`,
   `.partial()`, `.refine()`. Draft = `insert.partial()`, completed = insert,
   preview = `completed.extend(...)`, split-per-table = re-parse with each
   table's own schema and let zod strip unknown keys.
4. **Types** come from `z.infer<typeof schema>` or `table.$inferSelect`.
   Compositions use `Omit<...> & ...` over inferred types only.
5. **Boundaries** (server fn validators, API bodies, form resolvers) parse
   with the derived schema: `(data: unknown) => schema.parse(data)`.

## Client-safe derivation

When the table → schema chain would ship pg-core or classic zod to the client,
derive client schemas (zod/mini) from the same dependency-free domain root the
table derives from (enum/question/field definitions). The root stays single;
the derivations fan out:

domain definitions → drizzle columns → table → `createInsertSchema` (server)
domain definitions → zod/mini schemas (client)

- Both sides derive from shared definitions — a hand-written parallel shape is
  still a violation.
- Add a parity contract test (fixture round-trip + key-set equality) between
  the client schema and the `createInsertSchema` output. This replaces the
  guarantee codegen gave you for free — do not skip it.

## Never

- No `interface`/`type` that mirrors a table or restates a schema's fields.
- No separate "form types", "DTO", or "API types" files duplicating a
  concept.
- No re-listed enum/option literals — export values from one module, import
  everywhere.
- No hand-maintained payload types at boundaries.

## Adding a field

Touch the table and the UI. If a change requires editing a third place, a
derivation is missing — fix the chain, don't patch the copy.

Under client-safe derivation, enum/question fields still touch one place (the
domain root). A new non-question column touches the table and the client field
defs; forgetting one side must fail the parity test.

## Non-persisted shapes

Shapes that never hit the DB still get exactly one zod schema in the domain
module; types come from `z.infer`. The rule is one canonical definition per
concept — drizzle is just the most common root.
