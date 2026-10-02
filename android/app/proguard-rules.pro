# ML Kit's text-recognition plugin references the Chinese, Devanagari,
# Japanese and Korean recognisers, but we only ship the Latin model.
# Tell R8 those optional classes are allowed to be absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
