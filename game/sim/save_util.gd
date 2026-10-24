class_name SaveUtil
extends RefCounted
## 存读档小工具。JSON 读回来的数字都是 float，这里统一转回 int。


static func int_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for key in src:
		out[String(key)] = int(src[key])
	return out


static func float_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for key in src:
		out[String(key)] = float(src[key])
	return out


static func string_array(src: Array) -> Array[String]:
	var out: Array[String] = []
	for v in src:
		out.append(String(v))
	return out


static func total(counts: Dictionary) -> int:
	var n := 0
	for key in counts:
		n += int(counts[key])
	return n


static func add_counts(target: Dictionary, counts: Dictionary, times: int = 1) -> void:
	for key in counts:
		target[key] = int(target.get(key, 0)) + int(counts[key]) * times


static func remove_counts(target: Dictionary, counts: Dictionary) -> void:
	for key in counts:
		var left := int(target.get(key, 0)) - int(counts[key])
		assert(left >= 0, "库存不能为负")
		if left == 0:
			target.erase(key)
		else:
			target[key] = left


## Godot 的浮点数文本解析不能保证逐位还原（约一成数值会差最后一位），
## 存档前把所有 float 编成 8 字节十六进制字符串，读档后再还原，保证存读档无损。
const FLOAT_PREFIX := "f64:"


static func encode_floats(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return FLOAT_PREFIX + PackedFloat64Array([value]).to_byte_array().hex_encode()
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[key] = encode_floats(value[key])
			return out
		TYPE_ARRAY:
			var out := []
			for v in value:
				out.append(encode_floats(v))
			return out
	return value


static func decode_floats(value: Variant) -> Variant:
	match typeof(value):
		TYPE_STRING:
			if value.begins_with(FLOAT_PREFIX):
				return value.substr(FLOAT_PREFIX.length()).hex_decode().decode_double(0)
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[key] = decode_floats(value[key])
			return out
		TYPE_ARRAY:
			var out := []
			for v in value:
				out.append(decode_floats(v))
			return out
	return value
