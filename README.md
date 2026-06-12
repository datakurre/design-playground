# design-playground

End-to-end demonstration of how design intent evolves into
agent-managed user interfaces, using a deliberately lightweight stack:
**JSON · SQLite · MCP · React**.

```
Design Tokens → Component Metadata → Flow Definitions → SQLite Rule Store
→ MCP Design Server → Agent Planner → UI AST → JSON Schema Validation
→ React Renderer → Audit Logs
```

> Work in progress — phases are committed one by one. See
> `docs/architecture.md` for the full architecture once it lands.

## Development environment

The environment is declared with [devenv.sh](https://devenv.sh):

```sh
devenv shell   # toolchain: node 22, pnpm, sqlite, jq
```

Without devenv, plain Node 22 + pnpm works too:

```sh
pnpm install
pnpm pipeline   # tokens -> db -> scenarios -> governance
```
