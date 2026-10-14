package com.zdmgold.photosur

import io.flutter.embedding.android.FlutterActivity

// This file never existed until now. AndroidManifest.xml (File 56)
// references android:name=".MainActivity" and declares flutterEmbedding
// value="2", but without this actual class file extending the real v2
// embedding base class, Flutter's tooling has nothing to validate against
// — this is the concrete missing piece behind the "Build failed due to
// use of deleted Android v1 embedding" CI error, not a manifest content
// problem.
class MainActivity : FlutterActivity()
