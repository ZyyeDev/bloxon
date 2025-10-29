extends Button

var product_id: String = ""
var currency_amount: int = 0
var price_usd: float = 0.0

func set_product_data(id: String, amount: int, price: float):
	product_id = id
	currency_amount = amount
	price_usd = price
	update_display()

func update_display():
	var formatted_amount = Client.format_number(currency_amount)
	text = formatted_amount + " Coins\n$" + str(price_usd)
