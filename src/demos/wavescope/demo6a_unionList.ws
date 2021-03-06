
// Simple test of unionList.

//s1 = (readFile("./countup.txt", "mode: binary", timer(44000.0)) :: Stream (Int16 * Int16));
s1 = iterate _ in timer(10) {
  emit (1,2);
}

s2 = iterate((i,f) in s1) { emit int16ToFloat(i) };
//s3 = iterate((i,f) in s1) { emit floatToInt(f) + 100 };
s3 = iterate((i,f) in s1) { emit int16ToFloat(f) + 100.0 };

//main = s3;
//main = s2;

main = unionList([s2, s3]);
