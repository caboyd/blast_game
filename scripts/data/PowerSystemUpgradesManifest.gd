class_name PowerSystemUpgradesManifest
extends Resource

## Global shop upgrades (`ShipUpgradeData`) merged into `ShipDataRegistry` for `UpgradeBus` and save persistence
## (weapon systems, block effects, etc.).
@export var upgrades: Array[ShipUpgradeData] = []
