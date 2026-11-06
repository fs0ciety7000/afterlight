class_name ProgressionText
extends RefCounted
## Display helpers shared by the progression screens: stat values, affix
## lines with their range (« +7 % [5-9] »), item, rune and cost labels.
## Every word comes from strings.csv.

const ROMAN := ["I", "II", "III", "IV", "V"]
## Stats stored as fractions and shown as percentages (0.05 → 5 %).
const RATIO_STATS := [
	"crit_chance",
	"crit_damage",
	"haste",
	"damage_bonus",
	"element_bonus_arcane",
	"element_bonus_fire",
	"element_bonus_frost",
	"element_bonus_lightning",
	"resist_all",
	"shield_bonus",
	"gold_find",
]
## Order of the stats on the character sheet.
const SHEET_STATS := [
	"max_hp",
	"max_mana",
	"mana_regen",
	"power",
	"defense",
	"crit_chance",
	"crit_damage",
	"haste",
	"resist_all",
	"shield_bonus",
	"gold_find",
	"element_bonus_arcane",
	"element_bonus_fire",
	"element_bonus_frost",
	"element_bonus_lightning",
]


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)


static func stat_name(stat: String) -> String:
	return tr_key("ui.stat." + stat)


static func is_ratio(stat: String, layer: String) -> bool:
	return layer == "percent" or RATIO_STATS.has(stat)


## A number with at most one decimal, French comma ("4,5", "12").
static func number(value: float) -> String:
	if absf(value - roundf(value)) < 0.05:
		return str(roundi(value))
	return String.num(value, 1).replace(".", tr_key("ui.fmt.decimal"))


## Value of a stat or modifier: "12", "5 %"; `signed` adds + / −.
static func value(stat: String, layer: String, amount: float, signed: bool = false) -> String:
	var shown := absf(amount) if signed else amount
	var text := number(shown * 100.0) if is_ratio(stat, layer) else number(shown)
	if is_ratio(stat, layer):
		text = tr_key("ui.fmt.percent").format({"value": text})
	if signed:
		var sign_key := "ui.fmt.minus" if amount < 0.0 else "ui.fmt.plus"
		text = tr_key(sign_key).format({"value": text})
	return text


## Bare range "5-9" of an affix (same unit as its value).
static func range_text(stat: String, layer: String, bounds: Array) -> String:
	var scale := 100.0 if is_ratio(stat, layer) else 1.0
	return tr_key("ui.fmt.range").format(
		{"min": number(float(bounds[0]) * scale), "max": number(float(bounds[1]) * scale)}
	)


static func rarity_name(rarity: String) -> String:
	return tr_key("ui.rarity." + rarity)


static func rarity_color(rarity: String) -> Color:
	return UiTokens.RARITY.get(rarity, UiTokens.DAY["line"])


static func slot_name(slot: String) -> String:
	return tr_key("ui.slot." + slot)


## "Bâton de frêne cendré +3".
static func item_name(item: Dictionary) -> String:
	var name := Content.display_name(str(item.get("item_id", "")))
	var level := int(item.get("enhance", 0))
	if level <= 0:
		return name
	return tr_key("ui.item.name_enhanced").format({"name": name, "level": level})


## "Braise II".
static func rune_name(rune_id: String, tier: int) -> String:
	return tr_key("ui.rune.name_tier").format(
		{"name": Content.display_name(rune_id), "tier": ROMAN[clampi(tier, 1, 5) - 1]}
	)


## "120 or · 4 Poussière de mana" from a gold amount and {material: qty}.
static func cost(gold: int, materials: Dictionary = {}) -> String:
	var parts := PackedStringArray()
	if gold > 0:
		parts.append(tr_key("ui.fmt.gold").format({"gold": gold}))
	var ids := materials.keys()
	ids.sort()
	for id in ids:
		if int(materials[id]) > 0:
			parts.append(
				tr_key("ui.fmt.material").format(
					{"qty": materials[id], "name": Content.display_name(id)}
				)
			)
	if parts.is_empty():
		return tr_key("ui.fmt.free")
	return tr_key("ui.common.separator").join(parts)


## "75 %" from a 0..1 chance.
static func chance(p: float) -> String:
	return tr_key("ui.fmt.percent").format({"value": number(clampf(p, 0.0, 1.0) * 100.0)})


## One modifier line of an item card. Affixes show their name and rolled
## range: "Précision : +3 % [2-4]"; the implicit shows the stat name.
static func modifier_line(mod: Dictionary, item_level: int) -> String:
	var from: String = mod.get("from", "")
	var amount := value(mod["stat"], mod["layer"], float(mod["value"]), true)
	if from == "implicit" or from == "":
		return tr_key("ui.item.implicit_line").format(
			{"name": stat_name(mod["stat"]), "value": amount}
		)
	var bounds := GameState.progression.affix_range(from, item_level)
	return (
		tr_key("ui.item.affix_line")
		. format(
			{
				"name": Content.display_name(from),
				"value": amount,
				"range": range_text(mod["stat"], mod["layer"], bounds),
			}
		)
	)
