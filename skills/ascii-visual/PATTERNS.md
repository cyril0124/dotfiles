# Diagram Patterns

## Architecture (Layered Boxes)

```
┌──────────────┐      ┌──────────────┐
│   Frontend   │─────>│   Backend    │
│   React 19   │      │   FastAPI    │
└──────────────┘      └───────┬──────┘
                              │
                              v
                      ┌──────────────┐
                      │  PostgreSQL  │
                      └──────────────┘
```

## File Tree (Annotated)

```
src/
├── api/
│   ├── routes.py          [M] +45 -12    !! high-traffic
│   └── schemas.py         [M] +20 -5
├── services/
│   └── billing.py         [A] +180       ** new
└── tests/
    └── test_billing.py    [A] +120       ** new

Legend: [A]dd [M]odify [D]elete  !! Risk  ** New
```

## Swimlane / Timeline

```
Backend  ===[Schema]======[API]====================[Deploy]====>
                |            |                          ^
                |            +------blocks------+       |
                |                               |       |
Frontend ------[Wait]--------[Components]=======[Integ]=+

=== Active   --- Blocked   | Dependency
```

## Blast Radius (Concentric Rings)

```
         Ring 3: Tests (8 files)
    +-------------------------------+
    |    Ring 2: Transitive (5)     |
    |   +------------------------+  |
    |   |  Ring 1: Direct (3)    |  |
    |   |   +--------------+     |  |
    |   |   | CHANGED FILE |     |  |
    |   |   +--------------+     |  |
    |   +------------------------+  |
    +-------------------------------+
```

## Reversibility Timeline

```
Phase 1  [================]  FULLY REVERSIBLE    (add column)
Phase 2  [================]  FULLY REVERSIBLE    (new endpoint)
Phase 3  [============....]  PARTIALLY           (backfill)
             --- POINT OF NO RETURN ---
Phase 4  [........????????]  IRREVERSIBLE        (drop column)
```

## Comparison (Before / After)

```
BEFORE                          AFTER
┌────────────┐                  ┌────────────┐
│  Monolith  │                  │  Service A │──┐
│  (all-in-1)│                  └────────────┘  │  ┌──────────┐
└────────────┘                  ┌────────────┐  ├─>│  Queue   │
                                │  Service B │──┘  └──────────┘
                                └────────────┘
```

## Progress Bar

```
[████████░░] 80% Complete
+ Design    (2 days)
+ Backend   (5 days)
~ Frontend  (3 days)
- Testing   (pending)
```

## Cross-Layer Consistency Table

```
Backend Endpoint          Frontend Consumer     Status
POST /invoices            createInvoice()       PLANNED
GET  /invoices/:id        useInvoice(id)        PLANNED
GET  /invoices            InvoiceList.tsx        MISSING  !!
```
