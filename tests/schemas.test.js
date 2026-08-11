import test from 'node:test';
import assert from 'node:assert';
import Ajv2020 from 'ajv/dist/2020.js';
import fs from 'node:fs';
import path from 'node:path';

const ajv = new Ajv2020();

const loadSchema = (filename) => {
    const filePath = new URL(`../schemas/${filename}`, import.meta.url);
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
};

const tokensSchema = loadSchema('tokens.schema.json');
const componentsSchema = loadSchema('components.schema.json');
const screensSchema = loadSchema('screens.schema.json');
const contractsSchema = loadSchema('contracts.schema.json');

ajv.addSchema(tokensSchema, "tokens");
ajv.addSchema(componentsSchema, "components");
ajv.addSchema(screensSchema, "screens");
ajv.addSchema(contractsSchema, "contracts");

// The fixtures are read out of tests/Fixtures.elm rather than kept here,
// because two copies of a file format is exactly the problem this test exists
// to catch. FixturesTest asserts each one is byte-for-byte what the Elm encoder
// writes; this file asserts the schemas accept it. Before, the Elm suite
// checked codecs against Elm literals and this one checked schemas against JS
// literals, and neither could see the other — which is how `rules` stayed typed
// as a bare array of objects.
const readFixtures = () => {
    const filePath = new URL('./Fixtures.elm', import.meta.url);
    const source = fs.readFileSync(filePath, 'utf8');

    // One top-level `name : String` per fixture, assigned a """…""" literal.
    const pattern = /^(\w+)\s*:\s*String\s*\n\1\s*=\s*\n\s*"""([\s\S]*?)"""/gm;
    const fixtures = {};
    for (const match of source.matchAll(pattern)) {
        fixtures[match[1]] = JSON.parse(match[2]);
    }
    return fixtures;
};

const fixtures = readFixtures();

test('fixtures written by the Elm encoders satisfy the schemas', async (t) => {
    // If extraction silently found nothing, every assertion below would pass
    // vacuously — which is the failure mode this whole test is meant to close.
    await t.test('every fixture was found', () => {
        assert.deepStrictEqual(
            Object.keys(fixtures).sort(),
            ['component', 'contract', 'screen', 'tokens'],
        );
    });

    for (const [name, schema] of [
        ['tokens', 'tokens'],
        ['component', 'components'],
        ['screen', 'screens'],
        ['contract', 'contracts'],
    ]) {
        await t.test(`${name} validates against ${schema}`, () => {
            const validate = ajv.getSchema(schema);
            assert.strictEqual(
                validate(fixtures[name]),
                true,
                JSON.stringify(validate.errors),
            );
        });
    }
});

test('Tokens Schema', async (t) => {
    const validate = ajv.getSchema('tokens');

    await t.test('valid tokens payload', () => {
        const payload = {
            "color": {
                "primary": {
                    "$type": "color",
                    "$value": "#ff0000"
                }
            }
        };
        const valid = validate(payload);
        assert.strictEqual(valid, true, JSON.stringify(validate.errors));
    });

    await t.test('invalid tokens payload (array instead of object)', () => {
        const payload = [];
        assert.strictEqual(validate(payload), false);
    });

    await t.test('a name with a space is fine — DTCG only forbids . { } and $', () => {
        // The pattern was ^[a-zA-Z0-9_-]+$, which was stricter than DTCG and
        // stricter than Naming.check, so this could be typed, saved, and then
        // rejected by the app's own validator.
        const payload = {
            "brand color": {
                "$type": "color",
                "$value": "#ff0000"
            }
        };
        assert.strictEqual(validate(payload), true, JSON.stringify(validate.errors));
    });

    await t.test('a name containing a dot is not, because it separates path segments', () => {
        const payload = {
            "color.brand": {
                "$type": "color",
                "$value": "#ff0000"
            }
        };
        assert.strictEqual(validate(payload), false);
    });

    await t.test('an unknown $-prefixed key is rejected, since DTCG reserves them', () => {
        const payload = {
            "color": { "$type": "color", "$value": "#ff0000", "$extensions": {} }
        };
        assert.strictEqual(validate(payload), false);
    });
});

test('Components Schema', async (t) => {
    const validate = ajv.getSchema('components');

    await t.test('valid component payload', () => {
        const payload = {
            "name": "Button",
            "variants": ["primary", "secondary"],
            "slots": ["icon", "label"],
            "states": ["hover", "active"],
            "layout": {
                "type": "element",
                "isSlot": false,
                "styles": {},
                "content": "Click me"
            }
        };
        const valid = validate(payload);
        assert.strictEqual(valid, true, JSON.stringify(validate.errors));
    });

    await t.test('a layout with no type is rejected', () => {
        // `layout` was typed as a bare object, so this passed validation,
        // committed, and then failed to decode on load.
        const payload = {
            "name": "Button",
            "variants": [],
            "slots": [],
            "states": [],
            "layout": {}
        };
        assert.strictEqual(validate(payload), false);
    });

    await t.test('a layout with an unknown type is rejected', () => {
        const payload = {
            "name": "Button",
            "variants": [],
            "slots": [],
            "states": [],
            "layout": { "type": "carousel", "styles": {}, "children": [] }
        };
        assert.strictEqual(validate(payload), false);
    });

    await t.test('invalid component payload (missing required field)', () => {
        const payload = {
            "name": "Button",
            "variants": ["primary", "secondary"],
            "slots": ["icon", "label"]
        };
        assert.strictEqual(validate(payload), false);
    });
});

test('Screens Schema', async (t) => {
    const validate = ajv.getSchema('screens');

    await t.test('valid screen payload', () => {
        const payload = {
            "name": "Home",
            "path": "/",
            "root": { "type": "text", "content": "Hello" }
        };
        const valid = validate(payload);
        assert.strictEqual(valid, true, JSON.stringify(validate.errors));
    });

    await t.test('invalid screen payload (missing path)', () => {
        const payload = {
            "name": "Home",
            "root": { "type": "text", "content": "Hello" }
        };
        assert.strictEqual(validate(payload), false);
    });

    await t.test('a root with no type is rejected', () => {
        const payload = { "name": "Home", "path": "/", "root": {} };
        assert.strictEqual(validate(payload), false);
    });
});

test('Contracts Schema', async (t) => {
    const validate = ajv.getSchema('contracts');

    await t.test('valid contract payload', () => {
        const payload = {
            "component": "Button",
            "rules": [
                { "type": "allowedTokenGroups", "groups": ["colors"] }
            ]
        };
        const valid = validate(payload);
        assert.strictEqual(valid, true, JSON.stringify(validate.errors));
    });

    await t.test('invalid contract payload (wrong type for component)', () => {
        const payload = {
            "component": 123,
            "rules": []
        };
        assert.strictEqual(validate(payload), false);
    });

    await t.test('a rule missing its required field is rejected', () => {
        // `rules` was {"type": "object"}, so this validated, committed, and
        // then failed to decode on load — where the failure was swallowed and
        // the whole contract silently vanished.
        const payload = {
            "component": "Button",
            "rules": [{ "type": "allowedTokenGroups" }]
        };
        assert.strictEqual(validate(payload), false);
    });

    await t.test('a rule of an unknown type is rejected', () => {
        const payload = {
            "component": "Button",
            "rules": [{ "type": "noVibes", "properties": [] }]
        };
        assert.strictEqual(validate(payload), false);
    });

    await t.test('a contrastThreshold without its ratio is rejected', () => {
        const payload = {
            "component": "Button",
            "rules": [{ "type": "contrastThreshold", "foreground": "color", "background": "background-color" }]
        };
        assert.strictEqual(validate(payload), false);
    });
});
