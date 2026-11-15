class_name BenchCopy
extends RefCounted
## Every benchmark ends with a "Copy result" button: plain text to paste back
## into a chat, instead of a screenshot (design doc 14.5). Also kept in
## window.__bench_text for tools.


## The run's context: which build, the effects really in use, the screen.
static func header(vp: Viewport) -> String:
	var env: Environment = vp.world_3d.environment if vp.world_3d else null
	var lights := 0
	for n in vp.get_tree().get_nodes_in_group("track_lights"):
		if (n as Light3D).is_visible_in_tree():
			lights += 1
	return "build=%s glow=%s lights=%d aa=%dx screen=%dx%d scale=%.2f switches=%s" % [
		BuildId.ID, "?" if env == null else ("on" if env.glow_enabled else "off"), lights,
		[1, 2, 4, 8][vp.msaa_3d], vp.size.x, vp.size.y, vp.scaling_3d_scale, Bench.switches()]


static func offer(text: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.__bench_text = %s;" % JSON.stringify(text), true)
	JavaScriptBridge.eval("""(function(t){
		var old=document.getElementById('kw-copy'); if(old) old.remove();
		var b=document.createElement('button');b.id='kw-copy';b.textContent='Copy result';
		b.style.cssText='position:fixed;left:50%%;bottom:24px;transform:translateX(-50%%);z-index:99;font:600 18px system-ui;padding:14px 22px;border-radius:12px;border:0;background:#ffd23f;color:#111';
		b.onclick=function(){
			var shown=function(){var a=document.createElement('textarea');a.value=t;a.readOnly=true;a.style.cssText='position:fixed;left:5%%;right:5%%;bottom:84px;width:90%%;height:140px;z-index:99;font:12px monospace';document.body.appendChild(a);a.focus();a.select();};
			if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).then(function(){b.textContent='Copied'},shown)}else{shown()}
		};
		document.body.appendChild(b);
	})(%s);""" % JSON.stringify(text), true)
