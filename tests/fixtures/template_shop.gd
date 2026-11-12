extends RefCounted
const Schema := preload("res://content/rules/spec_shop_template.gd")

static func definition() -> Resource:
	var template := Schema.new()
	template.places = {
		"pantry":{"port":Vector2(100,100),"infinite":["raw_a","raw_b"]},
		"a_in":{"port":Vector2(200,100),"capacity":4}, "a_out":{"port":Vector2(200,100),"capacity":4},
		"b_in":{"port":Vector2(300,100),"capacity":4}, "b_out":{"port":Vector2(300,100),"capacity":4},
		"join_in":{"port":Vector2(400,100),"capacity":4}, "join_out":{"port":Vector2(400,100),"capacity":4}}
	template.machines = {
		"a":{"input":"a_in","output":"a_out","profile":{"manual":true}},
		"b":{"input":"b_in","output":"b_out","profile":{"manual":true}},
		"join":{"input":"join_in","output":"join_out","profile":{"manual":true}}}
	template.recipes = {"meal":{"nodes":[
		{"id":"merge","capability":"process","machine":"join","consumes":{"a":1,"b":1},"produces":{"meal":1},"inputs":{"a":"a","b":"b"},"seconds":1.0},
		{"id":"a","capability":"process","machine":"a","consumes":{"raw_a":1},"produces":{"a":1},"inputs":{"raw_a":"raw_a"},"seconds":2.0},
		{"id":"raw_a","capability":"source","place":"pantry","item":"raw_a","seconds":0.6},
		{"id":"b","capability":"process","machine":"b","consumes":{"raw_b":1},"produces":{"b":1},"inputs":{"raw_b":"raw_b"},"seconds":2.0},
		{"id":"raw_b","capability":"source","place":"pantry","item":"raw_b","seconds":0.6}],
		"output":{"node":"merge","item":"meal","count":1}}}
	return template

static func linear() -> Resource:
	var template := definition()
	template.recipes = {"drink":{"nodes":[
		{"id":"raw","capability":"source","place":"pantry","item":"raw_a","seconds":0.6},
		{"id":"drink","capability":"process","machine":"a","consumes":{"raw_a":1},"produces":{"drink":1},"inputs":{"raw_a":"raw"},"seconds":2.0}],
		"output":{"node":"drink","item":"drink","count":1}}}
	return template
