# R8 rules for release builds.
# Manifest components (activities, services, receivers) are kept automatically.

# Keep all app classes: small app, and avoids surprises with anything looked up by name.
-keep class com.example.ak47clk.** { *; }

# Flutter deferred-components references Play Core, which this app doesn't use.
-dontwarn com.google.android.play.core.**
