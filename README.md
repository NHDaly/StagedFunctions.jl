# StagedFunctions

A module containing our explorations around unlocking `@generated` functions to not need a frozen world age by adding backedges to them.

# NOTE: Custom Version of Julia required
FOR NOW, THIS MUST BE BUILT WITH A MODIFIED VERSION OF JULIA TO EXPORT A NEEDED FUNCTION.
YOU CAN CHECKOUT AND BUILD FROM THIS BRANCH:
<br>https://github.com/NHDaly/julia/tree/export_jl_resolve_globals_in_ir

The only thing this does is export `jl_resolve_globals_in_ir`.

Currently, that branch contains only the following commit: [ff209631](https://github.com/NHDaly/julia/commit/ff2096312f1c066a0d4047e756f4cf6ef6c771a4), built against Julia commit [f552fb20](https://github.com/NHDaly/julia/commit/f552fb20). This is the diff:
```diff
diff --git a/src/julia_internal.h b/src/julia_internal.h
index b9ce810262..f3e2f9bf0c 100644
--- a/src/julia_internal.h
+++ b/src/julia_internal.h
@@ -1016,6 +1016,10 @@ void jl_log(int level, jl_value_t *module, jl_value_t *group, jl_value_t *id,

 int isabspath(const char *in);

+// TODO(NHDALY): Find the right spot for this.
+JL_DLLEXPORT void jl_resolve_globals_in_ir(jl_array_t *stmts, jl_module_t *m,
+                              jl_svec_t *sparam_vals, int binding_effects);
+
 extern jl_sym_t *call_sym;    extern jl_sym_t *invoke_sym;
 extern jl_sym_t *empty_sym;   extern jl_sym_t *top_sym;
 extern jl_sym_t *module_sym;  extern jl_sym_t *slot_sym;
diff --git a/src/method.c b/src/method.c
index 7f9189be0d..35abef0f4c 100644
--- a/src/method.c
+++ b/src/method.c
@@ -191,8 +191,8 @@ static jl_value_t *resolve_globals(jl_value_t *expr, jl_module_t *module, jl_sve
     return expr;
 }

-void jl_resolve_globals_in_ir(jl_array_t *stmts, jl_module_t *m, jl_svec_t *sparam_vals,
-                              int binding_effects)
+JL_DLLEXPORT void jl_resolve_globals_in_ir(jl_array_t *stmts, jl_module_t *m,
+                              jl_svec_t *sparam_vals, int binding_effects)
 {
     size_t i, l = jl_array_len(stmts);
     for (i = 0; i < l; i++) {
```
