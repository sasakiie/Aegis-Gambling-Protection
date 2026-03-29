/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    "createRule": null,
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
        "hidden": false,
        "id": "number2948940571",
        "max": 100000,
        "min": null,
        "name": "report_count",
        "onlyInt": true,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "hidden": false,
        "id": "bool256245529",
        "name": "verified",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "bool"
      },
      {
        "hidden": false,
        "id": "select2371146282",
        "maxSelect": 1,
        "name": "source_type",
        "presentable": false,
        "required": true,
        "system": false,
        "type": "select",
        "values": [
          "admin_verified",
          "report_promoted",
          "seeded"
        ]
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
        "id": "date31787990",
        "max": "",
        "min": "",
        "name": "last_reported_at",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "date"
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
    "id": "pbc_4105477024",
    "indexes": [
      "CREATE UNIQUE INDEX `idx_NtpH09Gr6P` ON `ad_rules` (`domain`)",
      "CREATE INDEX `idx_GWMHSgqF0U` ON `ad_rules` (\n  `verified`,\n  `report_count`\n)",
      "CREATE INDEX `idx_CyaDT5muo9` ON `ad_rules` (`updated`)"
    ],
    "listRule": "verified = true || report_count >= 10",
    "name": "ad_rules",
    "system": false,
    "type": "base",
    "updateRule": null,
    "viewRule": "verified = true || report_count >= 10"
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_4105477024");

  return app.delete(collection);
})
