# MainActivity loads this optional adapter by class/method name. Keep the two
# static entry points; their normal call graph retains the worker implementation.
-keep class com.lewiseman.journal.qvac.QvacWorklet {
    public static void register(android.app.Activity, io.flutter.embedding.engine.FlutterEngine);
    public static void registerPeople(android.app.Activity, io.flutter.embedding.engine.FlutterEngine);
}

# FlutterEngine identifies plugins by their concrete class. Do not merge the
# People plugin into QvacWorklet or the engine will treat it as a duplicate.
-keep class com.lewiseman.journal.qvac.PeopleWorklet {
    public <init>();
}

# BareKit's standalone JAR has no consumer rules. JNI looks up these classes,
# handles and callback methods by name; retain both class families, including
# their nested Options/callback types. This is limited to BareKit's JNI boundary.
-keep class to.holepunch.bare.kit.Worklet** { *; }
-keep class to.holepunch.bare.kit.IPC** { *; }
