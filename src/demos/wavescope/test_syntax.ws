
// This is an accumulation of random code to test the parser.

x = 3 + {5; 4}; 

//x = 3 + begin 5; 4 end; 
//x = 3 + (5; 4); 

//y = (true ? 3 : 4); 
//y = if true then 3 else 4

//if (<exp>) <exp> else <exp>;
//if <exp> then <exp> else <exp>;
//if e0 then begin e1; e2 end else e3;

y = { x=4; let z=3; };

fun foo() {
  fun f(x) x;
  fun g(y) {y};

  for i = 1 to 10 {
    foo();
    if false
    then bar()
    else baz();
    if false
    then bar();
    else baz();
    34;
  }
  for j = 3 to 4 {
  };
  blah(3, if true then 4 else 5);
  
  if true 
    then foo()
    else 
      flurp();
      //{ for k = 1 to 2 {3} }
      //for k = 1 to 2 {3};
  
  //3 // Return
};

fun id(x) 
  if true 
  then x 
  else x;

BASE <- audio(0,100,0);
