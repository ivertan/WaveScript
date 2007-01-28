
// You can explicitely use the generic arith ops by prefixing them with 'g'.
//   Integer ops use +_
//   Float   ops use +.
//   Complex ops use +:

// Currently [2007.01.28] the plain form "+" is an alias for the
// integer ops, but eventually it will default to the generic ops
// instead.

fun f(x) { x g+ gint(3) }
fun g(x, y) { x g+ y }

s1 = audio(1, 4096, 0);

s2 = iterate (w in s1) {
  emit (f(3), f(4.5));
  emit (99, g(2.0, 1.0)); 

  print("Test: " ++ show(g(2.0+3.5i, 1.0+0.5i)) ++ "\n");
}

BASE <- s2;
