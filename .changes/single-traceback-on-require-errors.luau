return {
	bump = "patch",
	category = "Fixes",
	kind = "requiring",
	pr = 78,
	summary = "An error raised inside a chain of requires now carries one stack traceback.",
	body = "Each module in the chain used to append the full stack again, so the message grew with every level.",
}
