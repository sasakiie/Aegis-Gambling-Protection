/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    "createRule": "@request.auth.id != ''",
    "deleteRule": null,
    "fields": [
      {
        "autogeneratePattern": "[a-z0-9]{15}",
        "hidden": false,
        "id": "text3208210256",
        "max": 15,
        "min": 15,
        "name": "id",
        "pattern": "^[a-z0-9]+$",
        "presentable": false,
        "primaryKey": true,
        "required": true,
        "system": true,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "hidden": false,
        "id": "text2812878347",
        "max": 255,
        "min": 3,
        "name": "domain",
        "pattern": "^[a-z0-9.-]+$",
        "presentable": false,
        "primaryKey": false,
        "required": true,
        "system": false,
        "type": "text"
      },
      {
        "hidden": false,
        "id": "json239235232",
        "maxSize": 4096,
        "name": "selectors",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "json"
      },
      {
        "hidden": false,
        "id": "bool1319269873",
        "name": "is_gambling",
        "presentable": false,
        "required": true,
        "system": false,
        "type": "bool"
      },
      {
        "autogeneratePattern": "",
        "hidden": false,
        "id": "text1001949196",
        "max": 500,
        "min": 0,
        "name": "reason",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "hidden": false,
        "id": "text3978401726",
        "max": 64,
        "min": 0,
        "name": "client_version",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "hidden": false,
        "id": "text1965592548",
        "max": 64,
        "min": 0,
        "name": "created_by_token",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "hidden": false,
        "id": "select4294097618",
        "maxSelect": 1,
        "name": "report_type",
        "presentable": false,
        "required": true,
        "system": false,
        "type": "select",
        "values": [
          "gambling_site",
          "ad_selector",
          "false_positive",
          "selector_miss"
        ]
      },
      {
        "hidden": false,
        "id": "select2063623452",
        "maxSelect": 1,
        "name": "status",
        "presentable": false,
        "required": true,
        "system": false,
        "type": "select",
        "values": [
          "pending",
          "accepted",
          "promoted",
          "rejected"
        ]
      },
      {
        "hidden": false,
        "id": "autodate2990389176",
        "name": "created",
        "onCreate": true,
        "onUpdate": false,
        "presentable": false,
        "system": false,
        "type": "autodate"
      },
      {
        "hidden": false,
        "id": "autodate3332085495",
        "name": "updated",
        "onCreate": true,
        "onUpdate": true,
        "presentable": false,
        "system": false,
        "type": "autodate"
      }
    ],
    "id": "pbc_1615648943",
    "indexes": [
      "CREATE INDEX `idx_9Hqsx3rofE` ON `reports` (\n  `domain`,\n  `created`\n)",
      "CREATE INDEX `idx_cgSCubqVry` ON `reports` (\n  `created_by_token`,\n  `created`\n)",
      "CREATE INDEX `idx_AiA5XG8TJa` ON `reports` (\n  `domain`,\n  `report_type`\n)"
    ],
    "listRule": "@request.auth.id != '' && created_by_token = @request.auth.id",
    "name": "reports",
    "system": false,
    "type": "base",
    "updateRule": null,
    "viewRule": "@request.auth.id != '' && created_by_token = @request.auth.id"
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_1615648943");

  return app.delete(collection);
})
