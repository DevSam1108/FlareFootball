
# --- SnakeYAML fix ---
-keep class org.yaml.snakeyaml.** { *; }
-dontwarn org.yaml.snakeyaml.**

# Prevent R8 stripping java.beans references
-dontwarn java.beans.**
