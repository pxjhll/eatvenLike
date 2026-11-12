class_name SpecShopTemplate
extends Resource
## Declarative public capabilities. The compiler rejects unknown fields and
## callbacks; shop instances cannot replace capability implementations.
@export var version: int = 1
@export var hop_seconds: float = 0.6
@export var places: Dictionary = {}
@export var machines: Dictionary = {}
@export var restocks: Dictionary = {}
@export var recipes: Dictionary = {}
@export var service: Dictionary = {}
@export var dispatch: Dictionary = {}
