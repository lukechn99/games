class_name Query
extends RefCounted
## The page's query string (?autodrive&track=mine…). In a browser
## it's location.search; outside one (headless tools and tests) the same
## flags can be passed in the KW_QUERY environment variable.
##
## has() matches by substring, as the game always has: "intro" is also true
## for "introt=0.5" and "introreview", which turn on the fly-in too.

## Not cached: tests switch KW_QUERY between races, and it's read rarely.
static func text() -> String:
	return str(JavaScriptBridge.eval("location.search", true)) if OS.has_feature("web") else OS.get_environment("KW_QUERY")


static func has(flag: String) -> bool:
	return text().contains(flag)


## The value after "name=", up to the next "&"; `fallback` when absent.
static func value(name: String, fallback := "") -> String:
	var t := text()
	if not t.contains(name + "="):
		return fallback
	return t.split(name + "=")[1].split("&")[0]
