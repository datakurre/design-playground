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

    await t.test('invalid tokens payload (invalid pattern)', () => {
        const payload = {
            "invalid space": {
                "$type": "color",
                "$value": "#ff0000"
            }
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
            "layout": {}
        };
        const valid = validate(payload);
        assert.strictEqual(valid, true, JSON.stringify(validate.errors));
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
            "root": {}
        };
        const valid = validate(payload);
        assert.strictEqual(valid, true, JSON.stringify(validate.errors));
    });

    await t.test('invalid screen payload (missing path)', () => {
        const payload = {
            "name": "Home",
            "root": {}
        };
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
});
