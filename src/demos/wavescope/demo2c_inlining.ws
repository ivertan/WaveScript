
// Simple function should inline.
fun marmotscore(w) { 3.8 }

//ch1 = audio(0, 4096, 0, 44000);
//ch1 = (readFile("./countup.raw", "mode: binary  window: 4096", timer(10.0)) :: Stream (Sigseg Int));
ch1 = timer(10);

newwidth = 32;
step = 32;
rw1 = iterate w in ch1 {
  emit( marmotscore(w) );
};

main = rw1;
