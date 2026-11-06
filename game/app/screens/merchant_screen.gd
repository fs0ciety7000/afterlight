extends ProgressionScreen
## Marchande (GDD §10.6, §17 panel.merchant): consumables of the Aubelin shop
## with their price, carried / max, and a buy button that tells why it is
## disabled ("Or insuffisant : 30 requis", "Vous en portez déjà le maximum").

const SHOP := "shop.aubelin_merchant"


func _init() -> void:
	screen_id = "merchant"


func _build(into: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	var col := one_pane(into)
	heading(col, Content.display_name(SHOP))
	for line: Dictionary in api.shop_stock(SHOP):
		var id: String = line["id"]
		var short := id.get_slice(".", 1)
		var card := Kit.panel("CardPanel")
		var row := Kit.hbox()
		card.add_child(row)
		var tile := ItemTile.make(TILE)
		tile.show_kind(ItemTile.KIND_CONSUMABLE, id)
		tile.focus_mode = Control.FOCUS_NONE
		row.add_child(tile)
		var text := Kit.vbox(UiTokens.SPACE["xs"])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(Kit.label(Content.display_name(id), "LeadLabel"))
		text.add_child(
			Kit.label(tr(Content.get_entity(id).get("desc_key", id)), "MutedLabel", true)
		)
		var price := Kit.label(tr("ui.fmt.gold").format({"gold": line["price"]}), "NumberLabel")
		UiProbe.register("shop.price." + short, price)
		text.add_child(price)
		var carried := Kit.label(
			tr("ui.shop.carried").format({"carried": line["carried"], "max": line["carry_max"]}),
			"MutedLabel"
		)
		UiProbe.register("shop.carried." + short, carried)
		text.add_child(carried)
		row.add_child(text)
		action(
			row,
			tr("ui.shop.buy"),
			"shop.buy." + short,
			api.buy_quote(SHOP, id),
			func() -> void:
				report(
					api.buy(SHOP, id),
					tr("ui.shop.bought").format({"name": Content.display_name(id)})
				)
		)
		col.add_child(card)
