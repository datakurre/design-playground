-- SQLite rule store for the design system.
--
-- The database does not merely hold the design knowledge - it ENFORCES
-- its invariants:
--   * foreign keys: steps and bindings can only reference real
--     components, flows and rules
--   * CHECK constraints: closed vocabularies (severity, category,
--     token type), mandatory recovery text on error states, JSON
--     payloads must parse
--   * triggers: destructive-action rules must require confirmation,
--     step rule-tags must resolve to at least one rule, and the audit
--     log is append-only
--
-- Connections must run `PRAGMA foreign_keys = ON` (done by
-- @design-playground/design-db).

CREATE TABLE tokens (
  path        TEXT PRIMARY KEY,
  type        TEXT NOT NULL CHECK (type IN
                ('color','dimension','fontFamily','fontWeight','number',
                 'duration','cubicBezier','shadow')),
  value       TEXT NOT NULL CHECK (json_valid(value)),
  description TEXT
);

CREATE TABLE components (
  id       TEXT PRIMARY KEY CHECK (id GLOB '[a-z]*'),
  purpose  TEXT NOT NULL CHECK (length(purpose) >= 10),
  metadata TEXT NOT NULL CHECK (json_valid(metadata))
);

CREATE TABLE component_variants (
  component_id TEXT NOT NULL REFERENCES components(id),
  name         TEXT NOT NULL,
  usage        TEXT NOT NULL CHECK (length(usage) > 0),
  PRIMARY KEY (component_id, name)
);

CREATE TABLE component_a11y (
  id           TEXT PRIMARY KEY CHECK (id LIKE 'a11y-%'),
  component_id TEXT NOT NULL REFERENCES components(id),
  requirement  TEXT NOT NULL CHECK (length(requirement) > 0),
  wcag         TEXT
);

CREATE TABLE component_constraints (
  id            TEXT PRIMARY KEY CHECK (id LIKE 'c-%'),
  component_id  TEXT NOT NULL REFERENCES components(id),
  rule          TEXT NOT NULL CHECK (length(rule) > 0),
  machine_check TEXT
);

CREATE TABLE flows (
  id              TEXT PRIMARY KEY CHECK (id GLOB '[a-z]*'),
  goal            TEXT NOT NULL CHECK (length(goal) >= 10),
  success_title   TEXT NOT NULL,
  success_message TEXT NOT NULL
);

CREATE TABLE flow_intents (
  flow_id TEXT NOT NULL REFERENCES flows(id),
  phrase  TEXT NOT NULL CHECK (length(phrase) > 0),
  PRIMARY KEY (flow_id, phrase)
);

CREATE TABLE flow_steps (
  flow_id    TEXT NOT NULL REFERENCES flows(id),
  step_id    TEXT NOT NULL,
  position   INTEGER NOT NULL CHECK (position >= 0),
  title      TEXT NOT NULL,
  definition TEXT NOT NULL CHECK (json_valid(definition)),
  PRIMARY KEY (flow_id, step_id),
  UNIQUE (flow_id, position)
);

CREATE TABLE flow_step_components (
  flow_id      TEXT NOT NULL,
  step_id      TEXT NOT NULL,
  component_id TEXT NOT NULL REFERENCES components(id),
  PRIMARY KEY (flow_id, step_id, component_id),
  FOREIGN KEY (flow_id, step_id) REFERENCES flow_steps(flow_id, step_id)
);

-- Every declared error state must offer a recovery: dead ends are
-- rejected by the database itself.
CREATE TABLE flow_errors (
  flow_id  TEXT NOT NULL REFERENCES flows(id),
  code     TEXT NOT NULL,
  message  TEXT NOT NULL CHECK (length(message) > 0),
  recovery TEXT NOT NULL CHECK (length(recovery) >= 10),
  PRIMARY KEY (flow_id, code)
);

CREATE TABLE rules (
  id                    TEXT PRIMARY KEY CHECK (id LIKE 'rule-%'),
  tag                   TEXT NOT NULL,
  category              TEXT NOT NULL CHECK (category IN
                          ('action','destructive-action','accessibility','flow',
                           'layout','content','safety','error-handling')),
  severity              TEXT NOT NULL CHECK (severity IN ('error','warn','info')),
  applies               TEXT NOT NULL CHECK (applies IN ('step','global')),
  title                 TEXT NOT NULL,
  description           TEXT NOT NULL CHECK (length(description) >= 20),
  machine_check         TEXT,
  requires_confirmation INTEGER NOT NULL DEFAULT 0
                          CHECK (requires_confirmation IN (0, 1)),
  wcag                  TEXT
);

-- Safety invariant: a destructive-action rule can never be stored
-- without the confirmation requirement.
CREATE TRIGGER rules_destructive_need_confirmation_ins
BEFORE INSERT ON rules
WHEN NEW.category = 'destructive-action' AND NEW.requires_confirmation = 0
BEGIN
  SELECT RAISE(ABORT, 'destructive-action rules must set requires_confirmation=1');
END;

CREATE TRIGGER rules_destructive_need_confirmation_upd
BEFORE UPDATE ON rules
WHEN NEW.category = 'destructive-action' AND NEW.requires_confirmation = 0
BEGIN
  SELECT RAISE(ABORT, 'destructive-action rules must set requires_confirmation=1');
END;

CREATE TABLE flow_step_rule_tags (
  flow_id TEXT NOT NULL,
  step_id TEXT NOT NULL,
  tag     TEXT NOT NULL,
  PRIMARY KEY (flow_id, step_id, tag),
  FOREIGN KEY (flow_id, step_id) REFERENCES flow_steps(flow_id, step_id)
);

-- A step may only be tagged with tags that resolve to at least one
-- rule; silent no-op tags are rejected.
CREATE TRIGGER step_tag_resolves_to_rule
BEFORE INSERT ON flow_step_rule_tags
WHEN NOT EXISTS (SELECT 1 FROM rules WHERE tag = NEW.tag)
BEGIN
  SELECT RAISE(ABORT, 'flow step rule tag does not match any rule');
END;

-- Append-only audit log: agents and reviewers can rely on history
-- never being rewritten.
CREATE TABLE audit_log (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  ts       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  actor    TEXT NOT NULL CHECK (length(actor) > 0),
  event    TEXT NOT NULL CHECK (event IN
             ('intent','retrieval','plan','validation','render','rejection')),
  scenario TEXT,
  detail   TEXT NOT NULL CHECK (json_valid(detail))
);

CREATE TRIGGER audit_log_no_update
BEFORE UPDATE ON audit_log
BEGIN
  SELECT RAISE(ABORT, 'audit_log is append-only');
END;

CREATE TRIGGER audit_log_no_delete
BEFORE DELETE ON audit_log
BEGIN
  SELECT RAISE(ABORT, 'audit_log is append-only');
END;

CREATE TABLE decision_traces (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  scenario TEXT NOT NULL,
  trace    TEXT NOT NULL CHECK (json_valid(trace))
);
