
// ensbox platform testing
// test for timer sources

include "timersource.ws";

s = timer_source("test", 1000);

main = iterate f in s {
  print("got counter " ++ f ++ "\n");
}
